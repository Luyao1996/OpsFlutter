import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../channel/presentation/platform_helper.dart';
import '../data/auth_api.dart';

// 小程序配置
const String _wxMiniAppId = 'wxd10d1fac349fe344';
const String _wxMiniPath = 'pages/index/index';

/// 保存的用户
class SavedUser {
  final String id;
  final String username; // 登录用户名
  final String displayName; // 显示名称
  final String role;
  final Color avatarColor;
  final String lastLogin;
  final String? password; // base64(utf8)

  SavedUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.avatarColor,
    required this.lastLogin,
    this.password,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'displayName': displayName,
    'role': role,
    'avatarColor': avatarColor.value,
    'lastLogin': lastLogin,
    if (password != null && password!.isNotEmpty) 'password': password,
  };

  factory SavedUser.fromJson(Map<String, dynamic> json) => SavedUser(
    id: json['id'] ?? '',
    username: json['username'] ?? json['name'] ?? '', // 兼容旧数据
    displayName: json['displayName'] ?? json['name'] ?? '',
    role: json['role'] ?? '',
    avatarColor: Color(json['avatarColor'] ?? 0xFF007AFF),
    lastLogin: json['lastLogin'] ?? '',
    password: json['password'],
  );
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  // 视图状态: qrcode, wechat_mobile（手机端微信登录）
  String _viewState = 'qrcode';
  SavedUser? _selectedUser;

  // 是否为移动端
  bool _isMobile = false;

  // iOS(iPhone/iPad) 默认账号密码登录: App Store 审核要求第三方登录不得是唯一/强制入口
  // (Guideline 4.8/4.2.3(i)), 微信登录与扫码登录保留为次要入口
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  bool _isAppleLoggingIn = false; // Sign in with Apple 进行中防重入
  String? _loginError;

  // 时间
  late Timer _timer;
  DateTime _currentTime = DateTime.now();

  // QR码相关
  String _qrStatus =
      'loading'; // loading, pending, scanned, confirmed, expired, error
  String _qrData = '';
  Uint8List? _qrImageBytes; // 缓存解码后的二维码图像数据
  String _qrSessionId = '';
  String? _qrError;
  Timer? _qrPollTimer;
  Timer? _qrRefreshTimer; // 二维码刷新定时器
  int _qrCountdown = 30; // 二维码刷新倒计时（秒）
  static const int _qrRefreshInterval = 60; // 二维码刷新间隔（秒）
  int _qrCreateAttempts = 0; // 二维码创建连续失败计数（≥5 次转为 error 展示真实错误）

  List<SavedUser> _savedUsers = [];

  // Aurora 动画控制器
  late AnimationController _auroraController1;
  late AnimationController _auroraController2;
  late AnimationController _auroraController3;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _currentTime = DateTime.now());
    });

    // 初始化 Aurora 动画 (再快50%: 2.8s->1.4s, 3.5s->1.75s, 4.2s->2.1s)
    _auroraController1 = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);

    _auroraController2 = AnimationController(
      duration: const Duration(milliseconds: 1750),
      vsync: this,
    )..repeat(reverse: true);

    _auroraController3 = AnimationController(
      duration: const Duration(milliseconds: 2100),
      vsync: this,
    )..repeat(reverse: true);

    // 延迟检测移动端，确保 MediaQuery 可用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectMobileAndInit();
    });
  }

  /// 检测是否为移动端并初始化登录方式
  void _detectMobileAndInit() {
    // 基于物理平台判断，而非屏幕宽度，确保折叠屏展开后仍能跳转微信
    _isMobile = platformHelper.isMobile;

    if (_isIOS) {
      // iOS 默认账号密码登录, 微信/扫码通过界面入口切换
      setState(() {
        _viewState = 'manual';
        _qrStatus = 'idle';
      });
    } else if (_isMobile) {
      // 移动端：显示微信登录按钮（初始状态为 idle，显示按钮）
      setState(() {
        _viewState = 'wechat_mobile';
        _qrStatus = 'idle'; // 初始状态，显示登录按钮
      });
    } else {
      // 桌面端：显示二维码
      _createQRSession();
    }
  }

  Future<void> _loadSavedUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('ops_pro_saved_users');
      if (saved != null) {
        final List<dynamic> list = jsonDecode(saved);
        setState(() {
          _savedUsers = list.map((e) => SavedUser.fromJson(e)).toList();
          if (_savedUsers.isNotEmpty) {
            _viewState = 'users';
          }
        });
      }
    } catch (e) {
      debugPrint('加载保存用户失败: $e');
    }
  }

  Future<void> _saveUser(
    String userId,
    String username,
    String displayName,
    String role,
    String encodedPassword,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colors = [
        Colors.blue,
        Colors.purple,
        Colors.orange,
        Colors.pink,
        Colors.green,
        Colors.teal,
      ];
      final newUser = SavedUser(
        id: userId,
        username: username,
        displayName: displayName.isNotEmpty ? displayName : username,
        role: role, // 已经是中文角色名
        avatarColor: colors[math.Random().nextInt(colors.length)],
        lastLogin: '刚刚',
        password: encodedPassword,
      );

      final exists = _savedUsers.indexWhere((u) => u.username == username);
      if (exists >= 0) {
        _savedUsers[exists] = SavedUser(
          id: _savedUsers[exists].id,
          username: _savedUsers[exists].username,
          displayName: _savedUsers[exists].displayName,
          role: _savedUsers[exists].role,
          avatarColor: _savedUsers[exists].avatarColor,
          lastLogin: '刚刚',
          password: encodedPassword.isNotEmpty
              ? encodedPassword
              : _savedUsers[exists].password,
        );
      } else {
        _savedUsers.add(newUser);
      }

      await prefs.setString(
        'ops_pro_saved_users',
        jsonEncode(_savedUsers.map((u) => u.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('保存用户失败: $e');
    }
  }

  Future<void> _deleteUser(SavedUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _savedUsers.removeWhere((u) => u.username == user.username);
        // 如果删除后没有用户了，切换到手动登录
        if (_savedUsers.isEmpty) {
          _viewState = 'manual';
        }
      });
      await prefs.setString(
        'ops_pro_saved_users',
        jsonEncode(_savedUsers.map((u) => u.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('删除用户失败: $e');
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _qrPollTimer?.cancel();
    _qrRefreshTimer?.cancel();
    _auroraController1.dispose();
    _auroraController2.dispose();
    _auroraController3.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    return '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';
  }

  String get _formattedDate {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[_currentTime.weekday - 1];
    return '${_currentTime.month}月${_currentTime.day}日 $weekday';
  }

  Future<void> _handleLogin() async {
    if (_isLoggingIn) return;
    final username = _viewState == 'manual'
        ? _usernameController.text
        : _selectedUser?.username ?? ''; // 使用 username 而非 name
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });

    try {
      final authNotifier = ref.read(authNotifierProvider.notifier);
      await authNotifier.login(username, password);

      // 保存用户到历史记录
      final authState = ref.read(authNotifierProvider);
      if (authState.user != null) {
        final encodedPassword = base64Encode(utf8.encode(password));
        // 根据后端逻辑判断角色
        final roleLabel = authState.user!.isTopManager
            ? '总部管理员'
            : authState.user!.isSubManager
                ? '分部管理员'
                : '操作员';
        await _saveUser(
          authState.user!.id.toString(),
          authState.user!.username, // 登录用户名
          authState.user!.name, // 显示名称
          roleLabel,
          encodedPassword,
        );
      }

      if (mounted) context.go('/monitor');
    } catch (e) {
      setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  String? _decodeSavedPassword(SavedUser user) {
    final raw = user.password;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = utf8.decode(base64Decode(raw));
      return decoded.isEmpty ? null : decoded;
    } catch (_) {
      return raw.isEmpty ? null : raw;
    }
  }

  Future<void> _createQRSession() async {
    // 取消之前的刷新定时器
    _qrRefreshTimer?.cancel();
    _qrPollTimer?.cancel();

    _qrCreateAttempts++;

    setState(() {
      _qrStatus = 'loading';
      _qrError = null;
      _qrCountdown = _qrRefreshInterval;
      _qrImageBytes = null; // 清空缓存的图像数据
    });

    try {
      final api = ref.read(authApiProvider);
      // 调用预登录接口获取二维码
      final response = await api.preLogin();

      // 解码二维码图像数据并缓存
      String base64Data = response.qrCode;
      if (base64Data.contains(',')) {
        base64Data = base64Data.split(',').last;
      }
      final imageBytes = base64Decode(base64Data);

      _qrCreateAttempts = 0;

      setState(() {
        _qrSessionId = response.pwd; // pwd 作为会话ID
        _qrData = response.qrCode; // base64 二维码图片
        _qrImageBytes = imageBytes; // 缓存解码后的图像数据
        _qrStatus = 'pending';
        _qrCountdown = _qrRefreshInterval;
      });
      _startQRPolling();
      _startQRRefreshCountdown();
    } catch (e) {
      if (!mounted) return;
      // 连续失败 ≥5 次：停止无限转圈，把真实错误亮到界面
      // （error 分支自带"重试"按钮；重试后重新计数）
      if (_qrCreateAttempts >= 5) {
        setState(() {
          _qrStatus = 'error';
          _qrError = _describeQRError(e);
        });
        _qrCreateAttempts = 0;
        return;
      }
      // 创建失败时自动重试（常见于 token 过期跳回登录页时旧 token 未清理完）
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted && _qrStatus == 'loading') {
          _createQRSession();
        }
      });
    }
  }

  /// 把二维码创建失败的异常转成现场可读文案：
  /// 业务文案 + 底层网络异常（HandshakeException/SocketException 等），截断防撑爆 UI
  String _describeQRError(Object e) {
    var s = e.toString();
    if (e is ApiError) {
      final raw = e.raw;
      if (raw is DioException && raw.error != null) {
        s = '$s\n${raw.error}';
      }
    }
    return s.length > 200 ? '${s.substring(0, 200)}…' : s;
  }

  /// 启动二维码刷新倒计时
  void _startQRRefreshCountdown() {
    _qrRefreshTimer?.cancel();
    _qrRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _qrRefreshTimer?.cancel();
        return;
      }

      setState(() {
        _qrCountdown--;
      });

      if (_qrCountdown <= 0) {
        _qrRefreshTimer?.cancel();
        if (_qrStatus == 'pending') {
          _createQRSession();
        }
      }
    });
  }

  void _startQRPolling() {
    _qrPollTimer?.cancel();
    int pollCount = 0;
    const maxPollCount = 150; // 5分钟 (150 * 2秒)

    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      pollCount++;
      if (_qrSessionId.isEmpty || (_viewState != 'qrcode' && _viewState != 'wechat_mobile')) {
        _qrPollTimer?.cancel();
        return;
      }

      // 超时处理
      if (pollCount >= maxPollCount) {
        _qrPollTimer?.cancel();
        setState(() => _qrStatus = 'expired');
        return;
      }

      try {
        final api = ref.read(authApiProvider);
        // 轮询获取token接口
        final tokenResponse = await api.getToken(_qrSessionId);

        if (tokenResponse.isValid) {
          // 登录成功
          _qrPollTimer?.cancel();
          _qrRefreshTimer?.cancel();
          setState(() => _qrStatus = 'confirmed');

          // 1. 先存 token（不触发路由跳转）
          await TokenStore.setToken(tokenResponse.accessToken);

          // 2. 完成登录（获取用户信息 + 设 isLoggedIn → 触发路由跳转）
          // 注意：不在此处 invalidate dashboard provider，
          // 由 MainLayout._initializeNetbarTabs 完成网吧上下文初始化后再刷新
          final authNotifier = ref.read(authNotifierProvider.notifier);
          await authNotifier.loginWithToken(tokenResponse.accessToken);

          if (mounted) context.go('/dashboard');
        }
      } catch (e) {
        // 继续轮询，未授权时后端返回错误
        // 检查是否是已扫码状态（如果后端支持）
      }
    });
  }

  /// 手机端微信登录 - 跳转小程序
  Future<void> _handleWeChatLogin() async {
    setState(() {
      _qrStatus = 'loading';
      _qrError = null;
    });

    try {
      final api = ref.read(authApiProvider);
      // 获取登录会话
      final response = await api.preLogin();
      _qrSessionId = response.pwd;

      // 构造小程序 URL Scheme（明文格式）
      final query = Uri.encodeComponent('pwd=${response.pwd}');
      final schemeUrl = 'weixin://dl/business/?appid=$_wxMiniAppId&path=$_wxMiniPath&query=$query';

      setState(() => _qrStatus = 'pending');

      // 启动轮询
      _startQRPolling();
      _startQRRefreshCountdown();

      // 直接尝试跳转（不使用 canLaunchUrl，因为对自定义 scheme 检测不准确）
      final uri = Uri.parse(schemeUrl);
      bool launched = false;
      try {
        launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        // 未安装微信：iOS 抛 PlatformException，Android 返回 false，统一走降级
        launched = false;
      }
      if (!launched) {
        _qrPollTimer?.cancel();
        _qrRefreshTimer?.cancel();
        setState(() {
          _qrStatus = 'error';
          _qrError = '未检测到微信客户端，请使用账号密码登录';
        });
      }
    } catch (e) {
      setState(() {
        _qrStatus = 'error';
        _qrError = e.toString();
      });
    }
  }

  /// Sign in with Apple 登录（App Store 4.8：iOS 提供微信登录必须成对提供）
  Future<void> _handleAppleLogin() async {
    if (_isAppleLoggingIn) return;
    setState(() {
      _isAppleLoggingIn = true;
      _loginError = null;
    });
    try {
      final rawNonce = _generateAppleNonce();
      // 30 秒超时自愈：系统授权面板卡死（模拟器认证服务/Metal 故障等）时
      // 复位按钮状态，不必重启 App。注意超时不会关闭系统面板；用户若在超时后
      // 才完成授权，该次结果被忽略，重新点按钮即可
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [], // 隐私最小化：不索取邮箱/姓名，身份只认 sub
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      ).timeout(const Duration(seconds: 30));
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        throw ApiError(message: 'Apple 授权失败，请重试');
      }
      if (kDebugMode) {
        // 联调期供后端 curl 实时回放（token 约 10 分钟过期），release 不输出
        // TODO: 与后端联调结束后删除本段（debug 日志里的 token 是有效登录凭证）
        debugPrint('[SIWA][debug] nonce=$rawNonce');
        debugPrint('[SIWA][debug] identityToken=$identityToken');
      }
      final api = ref.read(authApiProvider);
      try {
        final tokenResp = await api.loginWithApple(
          identityToken: identityToken,
          nonce: rawNonce,
        );
        await _finishAppleLogin(tokenResp.accessToken);
      } on AppleIdNotBoundException catch (nb) {
        if (!mounted) return;
        final loggedIn = await showAdaptive<bool>(
          context,
          (_) => _AppleBindDialog(bindTicket: nb.bindTicket),
          routeName: 'apple-bind',
        );
        // 弹窗内已完成账密登录与绑定尝试，此处只负责跳转
        if (loggedIn == true && mounted) context.go('/monitor');
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _loginError = 'Apple 授权超时，请重试');
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // 用户主动取消授权：静默返回不报错
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        debugPrint('[SIWA] 授权失败: ${e.code} ${e.message}'); // 线上排障抓手
        setState(() => _loginError = 'Apple 授权失败，请重试');
      }
    } catch (e) {
      if (mounted) setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => _isAppleLoggingIn = false);
    }
  }

  /// Apple 登录拿到业务 token 后的收尾（与账密/扫码登录后半程同路）
  Future<void> _finishAppleLogin(String accessToken) async {
    final authNotifier = ref.read(authNotifierProvider.notifier);
    await authNotifier.loginWithToken(accessToken);
    if (mounted) context.go('/monitor');
  }

  /// 从账号密码界面返回微信/扫码登录
  void _backToWeChatLogin() {
    _usernameController.clear();
    _passwordController.clear();
    setState(() {
      _loginError = null;
      if (_isMobile) {
        _viewState = 'wechat_mobile';
        _qrStatus = 'idle'; // 手机端回到"通过微信登录"按钮
      } else {
        _viewState = 'qrcode'; // 桌面端回到二维码
      }
    });
    if (!_isMobile) _createQRSession();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // 键盘弹出或窗口过矮（iPad 兼容窗口/小屏/分屏）时收起时钟与底部装饰，
    // 防止 Positioned 元素被压进登录表单造成控件重叠（App Store Guideline 4 拒审点）
    final compact = media.viewInsets.bottom > 0 || media.size.height < 700;
    // 手机端微信/扫码视图的卡片较高（图标+状态区+双登录按钮+切换入口），
    // 与顶部时钟/日期装饰必然纵向重叠（iOS 模拟器实测），该场景单独收起时钟；
    // 底部备案号/版本区不受影响，仍按 compact 规则
    final hideClock = compact ||
        (_isMobile &&
            (_viewState == 'wechat_mobile' || _viewState == 'qrcode'));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFF1a1a2e)),
        child: Stack(
          // 装饰元素用 Visibility 控制显隐而非 if 增删 children：
          // 子级数量/顺序必须恒定，否则 compact 翻转时 Center 表单子树被销毁重建，
          // TextField 焦点丢失导致键盘弹出后立即收起（收起后 compact 又翻回，死循环）
          children: [
            _buildAuroraBackground(),
            Visibility(visible: !hideClock, child: _buildTimeDisplay()),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: _buildMainContent(),
              ),
            ),
            Visibility(visible: !compact, child: _buildFooterControls()),
            // iOS 端工信部 App 备案号（仅展示：普通 Text 不可复制，无手势不可点击）
            if (_isIOS) Visibility(visible: !compact, child: _buildIcpFooter()),
          ],
        ),
      ),
    );
  }

  Widget _buildAuroraBackground() {
    final screenSize = MediaQuery.of(context).size;
    final baseSize = screenSize.width * 0.7; // 占屏幕宽度70%

    return Stack(
      children: [
        // 紫色光晕 - 左上角 (blur-[120px] 对应 sigmaX/Y ~40)
        AnimatedBuilder(
          animation: _auroraController1,
          builder: (context, child) {
            final scale = 0.9 + (_auroraController1.value * 0.2);
            final opacity = 0.25 + (_auroraController1.value * 0.1);
            return Positioned(
              top: -screenSize.height * 0.2,
              left: -screenSize.width * 0.1,
              child: Transform.scale(
                scale: scale,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                  child: Container(
                    width: baseSize,
                    height: baseSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.purple.withValues(alpha: opacity),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // 蓝色光晕 - 右下角
        AnimatedBuilder(
          animation: _auroraController2,
          builder: (context, child) {
            final scale = 0.9 + (_auroraController2.value * 0.2);
            final opacity = 0.25 + (_auroraController2.value * 0.1);
            return Positioned(
              bottom: -screenSize.height * 0.2,
              right: -screenSize.width * 0.1,
              child: Transform.scale(
                scale: scale,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                  child: Container(
                    width: baseSize,
                    height: baseSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue.withValues(alpha: opacity),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        // 粉色光晕 - 中间偏左
        AnimatedBuilder(
          animation: _auroraController3,
          builder: (context, child) {
            final scale = 0.85 + (_auroraController3.value * 0.15);
            final opacity = 0.18 + (_auroraController3.value * 0.08);
            return Positioned(
              top: screenSize.height * 0.25 + (_auroraController3.value * 50),
              left: screenSize.width * 0.2 + (_auroraController3.value * 50),
              child: Transform.scale(
                scale: scale,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                  child: Container(
                    width: baseSize * 0.6,
                    height: baseSize * 0.6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.pink.withValues(alpha: opacity),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTimeDisplay() {
    return Positioned(
      top: 48,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Text(
            _formattedTime,
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w300,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formattedDate,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_viewState) {
      case 'wechat_mobile':
        return _buildWeChatMobileLogin();
      case 'manual':
        return _buildManualLogin();
      case 'users':
        return _buildUserSelection();
      case 'password':
        return _buildPasswordInput();
      case 'qrcode':
      default:
        // 桌面端：二维码登录
        return _buildQRCodeLogin();
    }
  }

  /// 手机端微信登录界面
  Widget _buildWeChatMobileLogin() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 微信图标
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF07C160), // 微信绿
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              LucideIcons.messageCircle,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '欢迎登录',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用微信快速登录',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 32),

          // 根据状态显示不同内容
          if (_qrStatus == 'loading')
            _buildWeChatLoading()
          else if (_qrStatus == 'pending')
            _buildWeChatPending()
          else if (_qrStatus == 'error')
            _buildWeChatError()
          else if (_qrStatus == 'confirmed')
            _buildWeChatSuccess()
          else // idle 或其他状态，显示登录按钮
            _buildWeChatButton(),

          // iOS：App Store 4.8 —— 凡出现第三方登录的界面须同屏提供等权 Apple 入口
          if (_isIOS) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SignInWithAppleButton(
                onPressed: _isAppleLoggingIn ? null : _handleAppleLogin,
                text: '通过 Apple 登录',
                height: 44,
                style: SignInWithAppleButtonStyle.white,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ],

          const SizedBox(height: 24),
          // 切换到扫码登录（用另一台设备扫）
          TextButton(
            onPressed: () {
              setState(() => _viewState = 'qrcode');
              _createQRSession();
            },
            child: Text(
              '使用其他设备扫码登录',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
          // 切换到账号密码登录（无微信 / App 审核场景）
          TextButton(
            onPressed: () {
              _qrPollTimer?.cancel();
              _qrRefreshTimer?.cancel();
              setState(() => _viewState = 'manual');
            },
            child: Text(
              '使用账号密码登录',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 微信登录按钮
  Widget _buildWeChatButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _handleWeChatLogin,
        icon: const Icon(LucideIcons.messageCircle, size: 20),
        label: const Text('通过微信登录', style: TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF07C160),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  /// 微信登录 - 加载中
  Widget _buildWeChatLoading() {
    return Column(
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Color(0xFF07C160),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '正在准备...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  /// 微信登录 - 等待授权
  Widget _buildWeChatPending() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF07C160).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(
                LucideIcons.smartphone,
                size: 32,
                color: Color(0xFF07C160),
              ),
              const SizedBox(height: 12),
              Text(
                '请在微信中完成授权',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '授权后将自动登录',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 倒计时
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.clock,
              size: 14,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 6),
            Text(
              '$_qrCountdown 秒后需重新操作',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 重新跳转按钮
        TextButton.icon(
          onPressed: _handleWeChatLogin,
          icon: Icon(
            LucideIcons.refreshCw,
            size: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
          label: Text(
            '重新打开微信',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// 微信登录 - 错误
  Widget _buildWeChatError() {
    return Column(
      children: [
        Icon(
          LucideIcons.alertCircle,
          size: 48,
          color: Colors.redAccent.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 12),
        Text(
          _qrError ?? '登录失败',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _buildWeChatButton(),
      ],
    );
  }

  /// 微信登录 - 成功
  Widget _buildWeChatSuccess() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF07C160),
            borderRadius: BorderRadius.circular(32),
          ),
          child: const Icon(
            LucideIcons.check,
            size: 32,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '登录成功',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '正在跳转...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildUserSelection() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 24,
          runSpacing: 24,
          alignment: WrapAlignment.center,
          children: [
            ..._savedUsers.map((user) => _buildUserAvatar(user)),
            _buildAddUserButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildUserAvatar(SavedUser user) {
    return _HoverableUserAvatar(
      user: user,
      onTap: () {
        final savedPassword = _decodeSavedPassword(user);
        setState(() {
          _selectedUser = user;
          _viewState = 'password';
          _passwordController.text = savedPassword ?? '';
          _loginError = null;
        });

        if (savedPassword != null && savedPassword.isNotEmpty) {
          Future.microtask(_handleLogin);
        }
      },
      onDelete: () => _showDeleteConfirm(user),
    );
  }

  void _showDeleteConfirm(SavedUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2a2a3e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除用户', style: TextStyle(color: Colors.white)),
        content: Text(
          '确定要删除 "${user.displayName}" 吗？',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteUser(user);
            },
            child: const Text('删除', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddUserButton() {
    return GestureDetector(
      onTap: () => setState(() {
        _viewState = 'manual';
        _usernameController.clear();
        _passwordController.clear();
      }),
      child: Column(
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 2,
              ),
            ),
            child: Icon(
              LucideIcons.user,
              size: 32,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '其他账户',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                _selectedUser?.avatarColor ?? AppColors.iosBlue,
                (_selectedUser?.avatarColor ?? AppColors.iosBlue).withValues(
                  alpha: 0.7,
                ),
              ],
            ),
          ),
          child: Center(
            child: Text(
              (_selectedUser?.displayName ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _selectedUser?.displayName ?? '',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          _selectedUser?.role ?? '',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _buildPasswordField(),
              if (_loginError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loginError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => setState(() {
            if (_savedUsers.isNotEmpty) {
              _viewState = 'users';
              _selectedUser = null;
              _loginError = null; // 清除错误
              _passwordController.clear(); // 清除密码
            }
          }),
          icon: Icon(
            LucideIcons.chevronLeft,
            size: 16,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          label: Text(
            '切换用户',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildManualLogin() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 2,
            ),
          ),
          child: Icon(
            LucideIcons.user,
            size: 40,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '欢迎登录',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          '请输入账号和密码',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: 280,
          child: Column(
            children: [
              _buildTextField(_usernameController, '账号 / 邮箱', false),
              const SizedBox(height: 16),
              _buildPasswordField(),
              if (_loginError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        size: 16,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _loginError!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 登录方式入口：
        // - iOS：Apple 官方按钮 + 微信按钮等权并列（App Store 4.8 要求提供
        //   第三方登录必须成对提供 Apple 登录，且微信不得比 Apple 更突出）
        // - 其他平台：保持原有"返回微信登录"文字入口
        if (_isIOS) ...[
          SizedBox(
            width: 280, // 与上方表单同宽，防止拉满屏宽与表单错位
            child: SignInWithAppleButton(
              onPressed: _isAppleLoggingIn ? null : _handleAppleLogin,
              text: '通过 Apple 登录',
              height: 44,
              style: SignInWithAppleButtonStyle.white,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 280,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _backToWeChatLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07C160), // 微信品牌绿
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(LucideIcons.messageCircle, size: 18),
              label: const Text('使用微信登录', style: TextStyle(fontSize: 16)),
            ),
          ),
          if (_isAppleLoggingIn) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
          ],
        ] else
          TextButton.icon(
            onPressed: _backToWeChatLogin,
            icon: Icon(
              LucideIcons.chevronLeft,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            label: Text(
              '返回微信登录',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
        if (_savedUsers.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _viewState = 'users'),
            icon: Icon(
              LucideIcons.chevronLeft,
              size: 16,
              color: Colors.white.withValues(alpha: 0.5),
            ),
            label: Text(
              '返回用户列表',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    bool obscure,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _handleLogin(),
              decoration: InputDecoration(
                hintText: '密码',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          if (_isLoggingIn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _handleLogin,
              icon: Icon(
                LucideIcons.arrowRight,
                size: 18,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQRCodeLogin() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '扫码安全登录',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          _buildQRContent(),
          const SizedBox(height: 16),
          if (_qrStatus == 'pending') ...[
            Text(
              '请使用 网维助手 App 扫一扫',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            // 倒计时显示
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.refreshCw,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  '$_qrCountdown 秒后自动刷新',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
          // 如果是移动端，显示返回微信登录的按钮
          if (_isMobile) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                _qrPollTimer?.cancel();
                _qrRefreshTimer?.cancel();
                setState(() {
                  _viewState = 'wechat_mobile';
                  _qrStatus = 'idle'; // 返回时显示登录按钮
                });
              },
              icon: Icon(
                LucideIcons.chevronLeft,
                size: 16,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              label: Text(
                '返回微信登录',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQRContent() {
    if (_qrStatus == 'loading') {
      return _buildQRLoading('正在创建...');
    }
    if (_qrStatus == 'error') {
      return Container(
        width: 192,
        height: 192,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _qrError ?? '创建失败',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _createQRSession,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_qrStatus == 'expired') {
      return Container(
        width: 192,
        height: 192,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '二维码已过期',
              style: TextStyle(color: Colors.amber, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _createQRSession,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('刷新二维码'),
            ),
          ],
        ),
      );
    }
    if (_qrStatus == 'scanned') {
      return Container(
        width: 192,
        height: 192,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.scanLine,
              size: 24,
              color: Colors.green.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            const Text(
              '扫描成功',
              style: TextStyle(
                color: Colors.green,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '请在手机上确认登录',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    // pending - 显示二维码，如果图像数据为空则显示加载动画
    if (_qrImageBytes == null || _qrImageBytes!.isEmpty) {
      return _buildQRLoading('生成二维码...');
    }

    return Container(
      width: 192,
      height: 192,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: Image.memory(
        _qrImageBytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true, // 防止图像切换时闪烁
        errorBuilder: (context, error, stackTrace) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.alertCircle,
                  size: 36,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 8),
                Text(
                  '二维码解析失败',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _createQRSession,
                  child: Text(
                    '点击重试',
                    style: TextStyle(fontSize: 12, color: AppColors.iosBlue),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQRLoading(String text) {
    return Container(
      width: 192,
      height: 192,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.iosBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  /// iOS 端 App 备案号（工信部《APP 备案通知》要求，仅 iOS 渲染）
  static const String _kIosIcpNumber = '蜀ICP备18023210号-16A';

  Widget _buildIcpFooter() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _kIosIcpNumber,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterControls() {
    return Positioned(
      bottom: 32,
      right: 32,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Netbar Ops Pro v2.5.0',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
          Text(
            'Designed by Gemini',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 可悬停显示删除按钮的用户头像
class _HoverableUserAvatar extends StatefulWidget {
  final SavedUser user;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HoverableUserAvatar({
    required this.user,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_HoverableUserAvatar> createState() => _HoverableUserAvatarState();
}

class _HoverableUserAvatarState extends State<_HoverableUserAvatar>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _showActions = false;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onEnter() {
    setState(() => _isHovered = true);
    setState(() => _showActions = true);
    _scaleController.forward();
  }

  void _onExit() {
    setState(() => _isHovered = false);
    setState(() => _showActions = false);
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () {
          setState(() => _showActions = !_showActions);
        },
        child: Column(
          children: [
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Stack(
                    children: [
                      Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              widget.user.avatarColor,
                              widget.user.avatarColor.withValues(alpha: 0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isHovered
                                  ? widget.user.avatarColor.withValues(
                                      alpha: 0.5,
                                    )
                                  : Colors.black.withValues(alpha: 0.3),
                              blurRadius: _isHovered ? 30 : 20,
                              spreadRadius: _isHovered ? 2 : 0,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            widget.user.displayName[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // 删除按钮 - 悬停或长按时显示（移动端无 hover）
                      if (_showActions)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: widget.onDelete,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.7),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                LucideIcons.x,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              widget.user.displayName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              widget.user.role,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 生成 SIWA 防重放随机串（原文送后端校验，sha256 后传给 Apple）
String _generateAppleNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
  final random = math.Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

/// Apple 登录首次使用：关联已有账号弹窗（窄屏全屏页 / 宽屏对话框）。
/// 后端票据制流程（docs/SignInWithApple前端接口文档_后端定稿.md §5）：
/// 弹窗内完成账密登录（600 秒近期认证窗口）→ 消费一次性 bind_ticket 绑定。
/// 登录成功即 pop(true)（绑定失败不阻断进入系统），取消返回 null。
class _AppleBindDialog extends ConsumerStatefulWidget {
  final String bindTicket;

  const _AppleBindDialog({required this.bindTicket});

  @override
  ConsumerState<_AppleBindDialog> createState() => _AppleBindDialogState();
}

class _AppleBindDialogState extends ConsumerState<_AppleBindDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请输入账号和密码');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // 1) 账密登录建立登录态：后端要求绑定必须携带"近期账密认证"的 JWT
      //    （600 秒窗口）；login 内部落 token + 拉 profile，与正常登录同路
      await ref.read(authNotifierProvider.notifier).login(username, password);

      // 2) 拦截器此时自动携带新 JWT，立即消费一次性票据完成绑定。
      //    登录已成功，绑定失败不阻断进入系统——下次 Apple 登录会重走本流程
      try {
        await ref
            .read(authApiProvider)
            .bindApple(bindTicket: widget.bindTicket);
      } catch (bindErr) {
        debugPrint('[SIWA] 绑定失败(登录已成功,不阻断): $bindErr');
      }

      if (!mounted) return;
      // 路由已在退场（用户点了 X/遮罩）时不再 pop，防止误弹掉下层登录页
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      // 账密登录失败（密码错误/网络等）：留在弹窗内提示，可修改后重试
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '关联已有账号',
      maxWidth: 420,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '首次使用 Apple 登录，需要关联管理员分配的账号（仅需一次，之后可直接一键登录）。',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '账号',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          // 错误提示只追加在末尾：不改变前面输入框的子级下标，键盘焦点不丢
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('关联并登录'),
          ),
        ],
      ),
    );
  }
}
