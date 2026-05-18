import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'core/logging/logging_binary_messenger.dart';
import 'core/logging/webrtc_crash_logger.dart';
import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/network/window_runtime.dart';
import 'core/theme/app_theme.dart';
import 'app/router.dart';
import 'features/monitor/presentation/terminal_detail_window_app.dart';
import 'features/update/domain/update_check_result.dart';
import 'features/update/presentation/update_dialog.dart';
import 'features/update/providers.dart';
import 'features/update/update_navigator_key.dart';
import 'shared/providers/app_providers.dart';
import 'shared/services/window_control.dart';

Future<void> _writeCrashLog(String error, String stack) async {
  try {
    if (kIsWeb) return;
    Directory logDir;
    if (Platform.isAndroid || Platform.isIOS) {
      final base = await getApplicationDocumentsDirectory();
      logDir = Directory('${base.path}${Platform.pathSeparator}crash_logs');
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent;
      logDir = Directory('${exeDir.path}${Platform.pathSeparator}crash_logs');
    }
    if (!logDir.existsSync()) logDir.createSync(recursive: true);
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final file = File('${logDir.path}${Platform.pathSeparator}dart_crash_$ts.log');
    final content =
        'Time: $now\nPlatform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\nNumberOfProcessors: ${Platform.numberOfProcessors}\n\nError:\n$error\n\nStack Trace:\n$stack\n';
    await file.writeAsString(content);
  } catch (_) {}
}

void main(List<String> args) async {
  runZonedGuarded(() async {
    LoggingWidgetsFlutterBinding.ensureInitialized();
    await WebRtcCrashLogger.I.init();

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      WebRtcCrashLogger.I.log(
        'ERROR',
        'flutter',
        'onError',
        '-',
        'exception=${details.exceptionAsString()} stack=${details.stack?.toString().split('\n').take(10).join(' | ') ?? 'no stack'}',
      );
      WebRtcCrashLogger.I.flush();
      _writeCrashLog(
        details.exceptionAsString(),
        details.stack?.toString() ?? 'no stack',
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      WebRtcCrashLogger.I.log(
        'ERROR',
        'flutter',
        'platformError',
        '-',
        'error=$error stack=${stack.toString().split('\n').take(10).join(' | ')}',
      );
      WebRtcCrashLogger.I.flush();
      _writeCrashLog(error.toString(), stack.toString());
      return true;
    };

  // 初始化存储
  await TokenStore.init();

  // 初始化 SharedPreferences holder（供 isPreviewProvider 等同步访问）
  await SharedPreferencesHolder.ensureInitialized();

  // 设置 401 回调
  ApiClient.onUnauthorized = () {
    // 路由跳转在 router 的 redirect 中处理（clearAuth 已在 ApiClient 拦截器中执行）
  };

  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = int.tryParse(args.length > 1 ? args[1] : '') ?? 0;
    // 标记当前进程为子窗口，让 taskWsProvider 注入 TaskWsProxy 而非真实客户端
    WindowRuntime.bindSubWindow(windowId);
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
  }, (error, stack) {
    WebRtcCrashLogger.I.log(
      'ERROR',
      'flutter',
      'zoneGuarded',
      '-',
      'error=$error stack=${stack.toString().split('\n').take(10).join(' | ')}',
    );
    WebRtcCrashLogger.I.flush();
    _writeCrashLog(error.toString(), stack.toString());
  });
}

class NetbarOpsApp extends ConsumerStatefulWidget {
  const NetbarOpsApp({super.key});

  @override
  ConsumerState<NetbarOpsApp> createState() => _NetbarOpsAppState();
}

class _NetbarOpsAppState extends ConsumerState<NetbarOpsApp> {
  static bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    // Debug 模式跳过启动自动检查：flutter run 时本地 build=1，会被服务端
    // minSupportedBuild 误判为强制更新，干扰开发体验。手动「检查更新」按钮不受影响。
    if (kDebugMode) {
      WebRtcCrashLogger.I
          .log('INFO', 'update', 'startupCheck', '-', 'debug build, skip');
      return;
    }
    // 用户主动通过"安装此版本"固定到了某个版本 → 启动不再自动弹更新对话框。
    // 手动「检查更新」按钮仍可正常使用。
    if (await ref.read(updateServiceProvider).isPinnedToCurrentBuild()) {
      WebRtcCrashLogger.I.log(
          'INFO', 'update', 'startupCheck', '-', 'pinned to current build, skip');
      return;
    }
    // 等一下让首屏稳定，避免和登录页/路由跳转抢焦点
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    try {
      final result = await ref.read(updateServiceProvider).check();
      // 检查结果中携带 isCurrentPreview，更新到 provider 让 UI 同步显示 PREVIEW 标签
      if (mounted &&
          result.status != UpdateStatus.skipped &&
          ref.read(isPreviewProvider) != result.isCurrentPreview) {
        ref.read(isPreviewProvider.notifier).state = result.isCurrentPreview;
      }
      if (!mounted || !result.hasUpdate) return;
      final ctx = updateNavigatorKey.currentContext;
      if (ctx == null) return;
      await showUpdateDialog(ctx, result);
    } catch (e, st) {
      WebRtcCrashLogger.I.log(
        'WARN',
        'update',
        'startupCheck',
        '-',
        'error=$e stack=${st.toString().split('\n').take(5).join(' | ')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Netbar Ops Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme.copyWith(
        visualDensity: VisualDensity.adaptivePlatformDensity,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      // i18n delegates：flutter_quill 11.x 强制要求；同时让 Material 内置 widget
      // (剪切/复制/粘贴菜单等) 跟随中文 locale。
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en'),
      ],
      routerConfig: router,
    );
  }
}
