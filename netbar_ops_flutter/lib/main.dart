import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'app/router.dart';
import 'features/monitor/presentation/terminal_detail_window_app.dart';
import 'shared/providers/app_providers.dart';
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
    final netbarId = data['netbarId'] as int? ?? 0;
    final netbarName = data['netbarName'] as String?;
    final groupName = data['groupName'] as String?;
    final subdomainFull = data['subdomainFull'] as String?;
    final initialTab = data['initialTab'] as String? ?? '远程控制';
    // 从临时文件读取截图
    Uint8List? initialScreenshot;
    final screenshotPath = data['screenshotPath'] as String?;
    if (screenshotPath != null) {
      try {
        final file = File(screenshotPath);
        if (await file.exists()) {
          initialScreenshot = await file.readAsBytes();
          // 读取后删除临时文件
          file.delete().ignore();
        }
      } catch (_) {}
    }

    await WindowControl.initTerminalDetailWindowChrome();

    final container = ProviderContainer();
    // 初始化子窗口的 currentNetbarProvider，确保终端详情能正确获取网吧信息
    if (netbarId > 0) {
      await container.read(currentNetbarProvider.notifier).setNetbar(
        netbarId,
        netbarName ?? '',
        'online',
        subdomainFull: subdomainFull,
        groupName: groupName,
      );
    }

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: TerminalDetailWindowApp(
          terminalId: terminalId,
          windowId: windowId,
          initialTab: initialTab,
          initialScreenshot: initialScreenshot,
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
      theme: AppTheme.lightTheme.copyWith(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      routerConfig: router,
    );
  }
}
