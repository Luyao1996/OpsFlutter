import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';

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
  // 视图状态: users, password, qrcode, manual
  String _viewState = 'manual';
  SavedUser? _selectedUser;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoggingIn = false;
  String? _loginError;

  // 时间
  late Timer _timer;
  DateTime _currentTime = DateTime.now();

  // QR码相关
  String _qrStatus =
      'loading'; // loading, pending, scanned, confirmed, expired, error
  String _qrData = '';
  String _qrSessionId = '';
  String? _qrError;
  Timer? _qrPollTimer;

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

    // 加载保存的用户
    _loadSavedUsers();
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
        role: switch (role) {
          'super_admin' => '超级管理员',
          'admin' => '管理员',
          _ => '网吧运维',
        },
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
        await _saveUser(
          authState.user!.id.toString(),
          authState.user!.username, // 登录用户名
          authState.user!.name, // 显示名称
          authState.user!.role,
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
    setState(() {
      _qrStatus = 'loading';
      _qrError = null;
    });

    try {
      final api = ref.read(authApiProvider);
      final session = await api.createQRSession();
      setState(() {
        _qrSessionId = session.sessionId;
        _qrData = session.qrData;
        _qrStatus = 'pending';
      });
      _startQRPolling();
    } catch (e) {
      setState(() {
        _qrStatus = 'error';
        _qrError = e.toString();
      });
    }
  }

  void _startQRPolling() {
    _qrPollTimer?.cancel();
    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_qrSessionId.isEmpty || _viewState != 'qrcode') {
        _qrPollTimer?.cancel();
        return;
      }
      try {
        final api = ref.read(authApiProvider);
        final status = await api.checkQRStatus(_qrSessionId);
        if (status.status == 'scanned') {
          setState(() => _qrStatus = 'scanned');
        } else if (status.status == 'confirmed' && status.token != null) {
          _qrPollTimer?.cancel();
          setState(() => _qrStatus = 'confirmed');
          // TODO: 保存 token 并跳转
          if (mounted) context.go('/monitor');
        } else if (status.status == 'expired') {
          _qrPollTimer?.cancel();
          setState(() => _qrStatus = 'expired');
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFF1a1a2e)),
        child: Stack(
          children: [
            _buildAuroraBackground(),
            _buildTimeDisplay(),
            Center(child: _buildMainContent()),
            _buildFooterControls(),
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
      case 'users':
        return _buildUserSelection();
      case 'password':
        return _buildPasswordInput();
      case 'qrcode':
        return _buildQRCodeLogin();
      default:
        return _buildManualLogin();
    }
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
        if (_savedUsers.isNotEmpty) ...[
          const SizedBox(height: 24),
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
          if (_qrStatus == 'pending')
            Text(
              '请使用 网维助手 App 扫一扫',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => setState(
              () => _viewState = _savedUsers.isNotEmpty ? 'users' : 'manual',
            ),
            child: Text(
              '返回账号登录',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _qrError ?? '创建失败',
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
            ),
            const SizedBox(height: 12),
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
    // pending - 显示二维码，如果 qrData 为空则显示加载动画
    if (_qrData.isEmpty) {
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
      child: Image.network(
        'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(_qrData)}',
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          final progress = loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
              : null;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    value: progress,
                    color: AppColors.iosBlue,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  progress != null ? '${(progress * 100).toInt()}%' : '加载中...',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        },
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
                  '加载失败',
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

  Widget _buildFooterControls() {
    return Positioned(
      bottom: 32,
      right: 32,
      child: Row(
        children: [
          if (_viewState != 'qrcode')
            _buildCircleButton(LucideIcons.qrCode, '扫码登录', () {
              setState(() => _viewState = 'qrcode');
              _createQRSession();
            }),
          const SizedBox(width: 16),
          _buildCircleButton(LucideIcons.shield, '需要帮助?', () {}),
          const SizedBox(width: 16),
          Column(
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
        ],
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.1),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
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
