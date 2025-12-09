import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/token_store.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/channel/presentation/channel_management_page.dart';
import '../features/monitor/presentation/monitor_page.dart';
import '../features/resource/presentation/resource_management_page.dart';
import '../shared/widgets/main_layout.dart';

/// 路由配置
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/monitor',
    redirect: (context, state) {
      final isLoggedIn = TokenStore.isLoggedIn();
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }
      if (isLoggedIn && isLoginRoute) {
        return '/monitor';
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
              child: const Scaffold(body: Center(child: Text('Dashboard - 开发中'))),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/netbar-list',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(body: Center(child: Text('网吧列表 - 开发中'))),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/channel-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ChannelManagementPage(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/desktop-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(body: Center(child: Text('桌面管理 - 开发中'))),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/user-management',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(body: Center(child: Text('用户管理 - 开发中'))),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/channel-monitor',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(body: Center(child: Text('监控中心 - 开发中'))),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ),
          GoRoute(
            path: '/system-logs',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const Scaffold(body: Center(child: Text('系统日志 - 开发中'))),
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
          final id = state.pathParameters['id'] ?? '0';
          return CustomTransitionPage(
            key: state.pageKey,
            child: Scaffold(body: Center(child: Text('终端详情 #$id - 开发中'))),
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

