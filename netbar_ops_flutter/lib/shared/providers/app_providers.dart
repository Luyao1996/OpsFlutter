import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/network/api_client.dart';
import '../../core/network/task_ws_provider.dart';
import '../../core/network/window_runtime.dart';
import '../../core/storage/token_store.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/monitor/data/terminal_api.dart';
import '../services/terminal_window_bridge.dart';

// API 实例
final authApiProvider = Provider((ref) => AuthApi());
final terminalApiProvider =
    Provider((ref) => TerminalApi(ref.read(taskWsProvider)));

/// 认证状态
class AuthState {
  final bool isLoggedIn;
  final User? user;

  AuthState({required this.isLoggedIn, this.user});

  AuthState copyWith({bool? isLoggedIn, User? user}) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      user: user ?? this.user,
    );
  }
}

/// 扫码登录状态
enum QRLoginState {
  idle,       // 空闲
  loading,    // 加载中
  waiting,    // 等待扫码
  scanned,    // 已扫码
  confirmed,  // 已确认
  expired,    // 已过期
  error,      // 错误
}

/// 扫码登录会话
class QRLoginSessionState {
  final QRLoginState state;
  final String? pwd;
  final String? qrCode; // base64图片
  final String? errorMessage;

  QRLoginSessionState({
    this.state = QRLoginState.idle,
    this.pwd,
    this.qrCode,
    this.errorMessage,
  });

  QRLoginSessionState copyWith({
    QRLoginState? state,
    String? pwd,
    String? qrCode,
    String? errorMessage,
  }) {
    return QRLoginSessionState(
      state: state ?? this.state,
      pwd: pwd ?? this.pwd,
      qrCode: qrCode ?? this.qrCode,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// 认证状态管理
///
/// Token 生命周期完全由后端控制：
/// - 不再主动定时刷新（旧逻辑已移除）
/// - 不再被动 401 续命（由 ApiClient 拦截器直接强制登出）
/// - 过期即 401 → onUnauthorized → 跳登录页
///
/// Token watchdog：仅主窗口每 60s 调一次 `/passport/profile` 验证 token；
/// 收到 401 → 关闭所有子窗口（含 WebRTC 远程）→ forceLogout → 路由跳扫码登录页。
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _authApi;
  Timer? _profileWatchdog;
  bool _handlingInvalid = false;

  AuthNotifier(this._authApi)
      : super(AuthState(isLoggedIn: TokenStore.isLoggedIn())) {
    if (state.isLoggedIn && WindowRuntime.isMainWindow) {
      _startWatchdog();
    }
  }

  /// 传统登录（后端不支持，会报错）
  Future<void> login(String username, String password) async {
    final response = await _authApi.login(
      LoginRequest(username: username, password: password),
    );
    await TokenStore.setToken(response.token);
    await TokenStore.setUser(response.user.toJson());
    state = AuthState(isLoggedIn: true, user: response.user);
    _startWatchdog();
  }

  /// 使用Token登录（扫码登录第二步）
  Future<void> loginWithToken(String token) async {
    await TokenStore.setToken(token);
    // 获取用户信息
    final user = await _authApi.getCurrentUser();
    await TokenStore.setUser(user.toJson());
    state = AuthState(isLoggedIn: true, user: user);
    _startWatchdog();
  }

  /// 登出
  Future<void> logout() async {
    _stopWatchdog();
    // 先切换到未登录状态，确保立即触发路由重定向
    state = AuthState(isLoggedIn: false);
    // 异步通知后端登出（不阻塞 UI）
    unawaited(() async {
      try {
        await _authApi.logout();
      } catch (_) {}
    }());
    await TokenStore.clearAuth();
  }

  /// 401/强制登出：只更新状态，触发路由跳转
  /// token 清理由调用方（ApiClient 拦截器）负责，此处不重复调用 clearAuth
  void forceLogout() {
    _stopWatchdog();
    state = AuthState(isLoggedIn: false);
  }

  /// 加载当前用户
  Future<void> loadCurrentUser() async {
    if (!TokenStore.isLoggedIn()) return;
    try {
      final user = await _authApi.getCurrentUser();
      state = AuthState(isLoggedIn: true, user: user);
    } catch (_) {
      forceLogout();
    }
  }

  /// 启动 token watchdog：仅主窗口启用，每 60s 验证一次
  void _startWatchdog() {
    if (!WindowRuntime.isMainWindow) return;
    _profileWatchdog?.cancel();
    _profileWatchdog = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _pollProfile(),
    );
  }

  void _stopWatchdog() {
    _profileWatchdog?.cancel();
    _profileWatchdog = null;
  }

  /// 单次校验 token：调 /passport/profile
  /// - 401 → 立即处理失效
  /// - 其他错误（超时/5xx/断网）→ 忽略，等下一次
  Future<void> _pollProfile() async {
    if (!state.isLoggedIn || _handlingInvalid) return;
    try {
      final user = await _authApi.getCurrentUser();
      // 顺带刷新用户信息，避免后端字段变更后客户端不同步
      await TokenStore.setUser(user.toJson());
      if (mounted) state = state.copyWith(user: user);
    } on ApiError catch (e) {
      if (e.code == 401) {
        await _handleTokenInvalid();
      }
    } catch (_) {
      // 网络异常忽略，下一轮再试
    }
  }

  /// Token 失效处理：先关所有子窗口，再 forceLogout
  Future<void> _handleTokenInvalid() async {
    if (_handlingInvalid) return;
    _handlingInvalid = true;
    _stopWatchdog();
    try {
      // 先关子窗口，让 WebRTC 等资源在窗口 dispose 时正常释放
      await TerminalWindowBridge.closeAllSubWindows();
    } catch (_) {}
    try {
      await TokenStore.clearAuth();
    } catch (_) {}
    if (mounted) {
      state = AuthState(isLoggedIn: false);
    }
    _handlingInvalid = false;
  }

  @override
  void dispose() {
    _stopWatchdog();
    super.dispose();
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authApiProvider));
});

/// 扫码登录管理
class QRLoginNotifier extends StateNotifier<QRLoginSessionState> {
  final AuthApi _authApi;
  Timer? _pollTimer;

  QRLoginNotifier(this._authApi) : super(QRLoginSessionState());

  /// 创建扫码登录会话
  Future<void> createSession() async {
    state = QRLoginSessionState(state: QRLoginState.loading);
    try {
      final response = await _authApi.preLogin();
      state = QRLoginSessionState(
        state: QRLoginState.waiting,
        pwd: response.pwd,
        qrCode: response.qrCode,
      );
    } catch (e) {
      state = QRLoginSessionState(
        state: QRLoginState.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// 开始轮询检查登录状态
  void startPolling(Function(String token) onSuccess) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (state.pwd == null) {
        timer.cancel();
        return;
      }
      try {
        final response = await _authApi.getToken(state.pwd!);
        if (response.isValid) {
          timer.cancel();
          state = state.copyWith(state: QRLoginState.confirmed);
          onSuccess(response.accessToken);
        }
      } catch (e) {
        // 继续轮询，直到超时
        // 可以在这里检查是否过期
      }
    });

    // 5分钟后自动停止轮询
    Future.delayed(const Duration(minutes: 5), () {
      if (state.state == QRLoginState.waiting) {
        _pollTimer?.cancel();
        state = state.copyWith(state: QRLoginState.expired);
      }
    });
  }

  /// 停止轮询
  void stopPolling() {
    _pollTimer?.cancel();
  }

  /// 重置状态
  void reset() {
    _pollTimer?.cancel();
    state = QRLoginSessionState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

final qrLoginProvider = StateNotifierProvider<QRLoginNotifier, QRLoginSessionState>((ref) {
  return QRLoginNotifier(ref.read(authApiProvider));
});

/// 当前网吧状态
class CurrentNetbar {
  final int? id;
  final String? name;
  final String? status;
  final String? subdomainFull; // 网吧完整域名，用于终端API请求
  final String? groupName; // 网吧所属分组名称
  final int version; // 用于触发刷新

  CurrentNetbar({this.id, this.name, this.status, this.subdomainFull, this.groupName, this.version = 0});

  CurrentNetbar copyWith({int? id, String? name, String? status, String? subdomainFull, String? groupName, int? version}) {
    return CurrentNetbar(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      subdomainFull: subdomainFull ?? this.subdomainFull,
      groupName: groupName ?? this.groupName,
      version: version ?? this.version,
    );
  }
}

/// 当前网吧状态管理
class CurrentNetbarNotifier extends StateNotifier<CurrentNetbar> {
  CurrentNetbarNotifier() : super(_loadFromStorage());

  static CurrentNetbar _loadFromStorage() {
    final data = TokenStore.getCurrentNetbar();
    if (data == null) return CurrentNetbar();
    return CurrentNetbar(
      id: data['id'],
      name: data['name'],
      status: data['status'],
      subdomainFull: data['subdomain_full'],
      groupName: data['group_name'],
    );
  }

  /// 设置当前网吧
  Future<void> setNetbar(int id, String name, String status, {String? subdomainFull, String? groupName}) async {
    state = CurrentNetbar(
      id: id,
      name: name,
      status: status,
      subdomainFull: subdomainFull,
      groupName: groupName,
      version: state.version + 1,
    );
    final netbar = {
      'id': id,
      'name': name,
      'status': status,
      if (subdomainFull != null) 'subdomain_full': subdomainFull,
      if (groupName != null) 'group_name': groupName,
    };
    await TokenStore.setCurrentNetbar(netbar);
  }

  /// 清除当前网吧
  Future<void> clear() async {
    await TokenStore.removeCurrentNetbar();
    state = CurrentNetbar(version: state.version + 1);
  }
}

final currentNetbarProvider = StateNotifierProvider<CurrentNetbarNotifier, CurrentNetbar>((ref) {
  return CurrentNetbarNotifier();
});

/// 仅暴露"当前网吧 id"，作为 family provider 的稳定 key。
/// 只有 id 变化时才通知下游，避免因无关字段变化误触 family 重建。
final currentNetbarIdProvider = Provider<int?>((ref) {
  return ref.watch(currentNetbarProvider.select((n) => n.id));
});
