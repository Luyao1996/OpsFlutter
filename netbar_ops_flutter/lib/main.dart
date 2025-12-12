import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'app/router.dart';
import 'features/monitor/presentation/terminal_detail_window_app.dart';
import 'shared/services/window_control.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化存储
  await TokenStore.init();

  // 设置 401 回调
  ApiClient.onUnauthorized = () {
    // 路由跳转在 router 的 redirect 中处理（clearAuth 已在 ApiClient 拦截器中执行）
  };

  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = int.tryParse(args.length > 1 ? args[1] : '') ?? 0;
    final payload = args.length > 2 ? args[2] : '{}';
    final data = jsonDecode(payload) as Map<String, dynamic>;
    final terminalId = data['terminalId'] as int? ?? 0;
    final initialTab = data['initialTab'] as String? ?? '远程控制';

    await WindowControl.initTerminalDetailWindowChrome();

    runApp(
      ProviderScope(
        child: TerminalDetailWindowApp(
          terminalId: terminalId,
          windowId: windowId,
          initialTab: initialTab,
        ),
      ),
    );
    return;
  }

  runApp(const ProviderScope(child: NetbarOpsApp()));
}

class NetbarOpsApp extends ConsumerWidget {
  const NetbarOpsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Netbar Ops Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.iosBlue,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.iosBg,
        fontFamily: null, // 使用系统字体
      ),
      routerConfig: router,
    );
  }
}
