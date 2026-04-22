import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../../core/storage/token_store.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/monitor/data/terminal_api.dart';

// API 实例
final authApiProvider = Provider((ref) => AuthApi());
final terminalApiProvider = Provider((ref) => TerminalApi());

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
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _authApi;
  Timer? _refreshTimer;

  AuthNotifier(this._authApi) : super(AuthState(isLoggedIn: TokenStore.isLoggedIn())) {
    // 应用启动时，如果已登录则启动定时刷新
    if (state.isLoggedIn) {
      _scheduleTokenRefresh();
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
  }

  /// 使用Token登录（扫码登录第二步）
  Future<void> loginWithToken(String token, {int? expireIn, int? createIn}) async {
    await TokenStore.setToken(token);
    // 计算并存储过期时间
    if (expireIn != null && expireIn > 0) {
      final baseMs = (createIn != null && createIn > 0)
          ? createIn * 1000
          : DateTime.now().millisecondsSinceEpoch;
      await TokenStore.setTokenExpireAt(baseMs + expireIn * 1000);
    }
    // 获取用户信息
    final user = await _authApi.getCurrentUser();
    await TokenStore.setUser(user.toJson());
    state = AuthState(isLoggedIn: true, user: user);
    _scheduleTokenRefresh();
  }

  /// 登出
  Future<void> logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
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
    _refreshTimer?.cancel();
    _refreshTimer = null;
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

  /// 定时主动刷新 Token（在过期前 20% 时间点刷新）
  void _scheduleTokenRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    final expireAt = TokenStore.getTokenExpireAt();
    if (expireAt == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = expireAt - now;
    if (remaining <= 0) {
      // 已过期，立即尝试刷新
      _doRefresh();
      return;
    }

    // 在剩余寿命的 80% 时刷新（即过期前 20% 的时间点）
    final refreshDelay = (remaining * 0.8).toInt();
    _refreshTimer = Timer(Duration(milliseconds: refreshDelay), _doRefresh);
  }

  /// 执行 Token 刷新
  Future<void> _doRefresh() async {
    if (!state.isLoggedIn) return;
    try {
      final tokenResponse = await _authApi.refreshToken();
      if (tokenResponse.isValid) {
        await TokenStore.setToken(tokenResponse.accessToken);
        if (tokenResponse.expireIn != null && tokenResponse.expireIn! > 0) {
          final baseMs = (tokenResponse.createIn != null && tokenResponse.createIn! > 0)
              ? tokenResponse.createIn! * 1000
              : DateTime.now().millisecondsSinceEpoch;
          await TokenStore.setTokenExpireAt(baseMs + tokenResponse.expireIn! * 1000);
        }
        // 刷新成功，重新调度下次刷新
        _scheduleTokenRefresh();
      } else {
        // 刷新返回无效 token，不强制登出（等 401 拦截器处理）
      }
    } catch (_) {
      // 刷新失败（网络错误等），30 秒后重试
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(seconds: 30), _doRefresh);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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
