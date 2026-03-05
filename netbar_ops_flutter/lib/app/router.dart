import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/channel/presentation/channel_management_page.dart' as channel;
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/monitor/presentation/monitor_page.dart';
import '../features/netbar/presentation/netbar_list_page.dart';
import '../features/resource/presentation/resource_management_page.dart';
import '../features/user/presentation/user_management_page.dart';
import '../features/logs/presentation/system_logs_page.dart';
import '../features/desktop/presentation/desktop_management_page.dart'; // Import DesktopManagementPage
import '../shared/widgets/main_layout.dart';
import '../features/monitor/presentation/terminal_detail_page.dart';
import '../features/channel/presentation/channel_monitor_page.dart';
import '../shared/providers/app_providers.dart';

/// 路由配置
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(_routerRefreshListenableProvider);
  return GoRouter(
    refreshListenable: refreshListenable,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isLoggedIn = ref.read(authNotifierProvider).isLoggedIn;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }
      if (isLoggedIn && isLoginRoute) {
        return '/dashboard';
      }
      return null;
    },
    routes: [
      // 登录页面
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),
      // 主壳层路由
      ShellRoute(
        builder: (context, state, child) => MainLayout(child: child),
        routes: [
          GoRoute(
            path: '/monitor',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const MonitorPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const DashboardPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/netbar-list',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const NetbarListPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/channel-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: channel.ChannelManagementPage(
                initialModule: state.uri.queryParameters['tab'] == 'startup' ? channel.ModuleTab.startup : null,
                initialEditStartupItemId: int.tryParse(state.uri.queryParameters['edit_startup_item_id'] ?? ''),
                initialZone: state.uri.queryParameters['zone'],
              ),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/desktop-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const DesktopManagementPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/user-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const UserManagementPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/channel-monitor',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ChannelMonitorPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/system-logs',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const SystemLogsPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/resource-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ResourceManagementPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
        ],
      ),
      // 终端详情页（独立窗口）
      GoRoute(
        path: '/terminal/:id',
        pageBuilder: (context, state) {
          final id = int.parse(state.pathParameters['id'] ?? '0');
          final screenshot = state.extra as Uint8List?;
          return CustomTransitionPage(
            key: state.pageKey,
            child: TerminalDetailPage(terminalId: id, initialScreenshot: screenshot),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          );
        },
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('页面不存在: ${state.matchedLocation}')),
    ),
  );
});

final _routerRefreshListenableProvider =
    Provider<_RouterRefreshListenable>((ref) {
  final notifier = _RouterRefreshListenable();
  final sub = ref.listen<AuthState>(authNotifierProvider, (_, __) {
    notifier.notifyListeners();
  });
  ref.onDispose(() {
    sub.close();
    notifier.dispose();
  });
  return notifier;
});

class _RouterRefreshListenable extends ChangeNotifier {
  _RouterRefreshListenable();
}
