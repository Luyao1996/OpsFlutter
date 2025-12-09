import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/token_store.dart';
import '../../features/auth/data/auth_api.dart';
import '../../features/dashboard/data/dashboard_api.dart';
import '../../features/monitor/data/terminal_api.dart';

// API 实例
final authApiProvider = Provider((ref) => AuthApi());
final dashboardApiProvider = Provider((ref) => DashboardApi());
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

/// 认证状态管理
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthApi _authApi;

  AuthNotifier(this._authApi) : super(AuthState(isLoggedIn: TokenStore.isLoggedIn()));

  /// 登录
  Future<void> login(String username, String password) async {
    final response = await _authApi.login(
      LoginRequest(username: username, password: password),
    );
    await TokenStore.setToken(response.token);
    await TokenStore.setUser(response.user.toJson());
    state = AuthState(isLoggedIn: true, user: response.user);
  }

  /// 登出
  Future<void> logout() async {
    try {
      await _authApi.logout();
    } catch (_) {}
    await TokenStore.clearAuth();
    state = AuthState(isLoggedIn: false);
  }

  /// 加载当前用户
  Future<void> loadCurrentUser() async {
    if (!TokenStore.isLoggedIn()) return;
    try {
      final user = await _authApi.getCurrentUser();
      state = AuthState(isLoggedIn: true, user: user);
    } catch (_) {
      await logout();
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authApiProvider));
});

/// 当前网吧状态
class CurrentNetbar {
  final int? id;
  final String? name;
  final String? status;
  final int version; // 用于触发刷新

  CurrentNetbar({this.id, this.name, this.status, this.version = 0});

  CurrentNetbar copyWith({int? id, String? name, String? status, int? version}) {
    return CurrentNetbar(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
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
    );
  }

  /// 设置当前网吧
  Future<void> setNetbar(int id, String name, String status) async {
    final netbar = {'id': id, 'name': name, 'status': status};
    await TokenStore.setCurrentNetbar(netbar);
    state = CurrentNetbar(
      id: id,
      name: name,
      status: status,
      version: state.version + 1,
    );
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

/// Dashboard 统计
final dashboardStatsProvider = FutureProvider.autoDispose<DashboardStats>((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  final api = ref.read(dashboardApiProvider);
  return api.getStats(netbarId: netbar.id);
});

