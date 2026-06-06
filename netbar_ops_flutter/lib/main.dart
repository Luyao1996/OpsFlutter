import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'core/logging/exit_reason_reporter.dart';
import 'core/logging/logging_binary_messenger.dart';
import 'core/logging/webrtc_crash_logger.dart';
import 'core/storage/token_store.dart';
import 'core/network/api_client.dart';
import 'core/network/window_runtime.dart';
import 'core/theme/app_theme.dart';
import 'app/router.dart';
import 'features/monitor/presentation/terminal_detail_window_app.dart';
import 'features/update/domain/update_check_result.dart';
import 'features/update/presentation/app_store_update_dialog.dart';
import 'features/update/presentation/update_dialog.dart';
import 'features/update/providers.dart';
import 'features/update/update_navigator_key.dart';
import 'shared/providers/app_providers.dart';
import 'shared/services/window_control.dart';
import 'shared/utils/platform_utils.dart';

/// 崩溃日志目录，启动时缓存。崩溃路径上不能 await（移动端 path_provider 是异步的），
/// 所以提前缓存，崩溃时同步写盘。
Directory? _crashLogDir;

/// 启动早期调用：解析并缓存 crash_logs 目录，确保崩溃时可同步写盘。
Future<void> _initCrashLogDir() async {
  try {
    if (kIsWeb) return;
    Directory base;
    if (Platform.isAndroid || Platform.isIOS) {
      base = await getApplicationDocumentsDirectory();
    } else {
      base = File(Platform.resolvedExecutable).parent;
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}crash_logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _crashLogDir = dir;
  } catch (_) {}
}

/// 同步写崩溃日志。崩溃处理器中调用——必须同步落盘（flush:true），
/// 否则进程退出时异步写入可能丢失。
/// [prefix] 区分崩溃来源：dart_crash（主线程）/ isolate_crash（isolate）。
void _writeCrashLog(String error, String stack, {String prefix = 'dart_crash'}) {
  try {
    if (kIsWeb) return;
    Directory? logDir = _crashLogDir;
    // 缓存未就绪（极早期崩溃）时，桌面端可同步推导兜底；移动端无法同步取目录则放弃文件。
    if (logDir == null && !(Platform.isAndroid || Platform.isIOS)) {
      final exeDir = File(Platform.resolvedExecutable).parent;
      logDir = Directory('${exeDir.path}${Platform.pathSeparator}crash_logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
    }
    if (logDir == null) return;
    final now = DateTime.now();
    final ts =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final file = File('${logDir.path}${Platform.pathSeparator}${prefix}_$ts.log');
    final content =
        'Time: $now\nPlatform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\nNumberOfProcessors: ${Platform.numberOfProcessors}\n\nError:\n$error\n\nStack Trace:\n$stack\n';
    file.writeAsStringSync(content, flush: true);
  } catch (_) {}
}

void main(List<String> args) async {
  runZonedGuarded(() async {
    LoggingWidgetsFlutterBinding.ensureInitialized();
    // 全局 ErrorWidget 兜底：任意 widget build 抛异常时显示友好框，
    // 而非 Flutter 默认的红屏(debug)/灰白框(release)，避免整页不可用。
    ErrorWidget.builder =
        (FlutterErrorDetails details) => const _GlobalErrorFallback();
    await WebRtcCrashLogger.I.init();
    await _initCrashLogDir();

    // L2: 当前 isolate 未捕获错误的全局兜底（zone 接不住的也能记录）。
    Isolate.current.addErrorListener(RawReceivePort((dynamic pair) {
      try {
        final list = pair as List<dynamic>;
        final error = list.isNotEmpty ? '${list[0]}' : 'unknown';
        final stack = list.length > 1 ? '${list[1] ?? 'no stack'}' : 'no stack';
        WebRtcCrashLogger.I.log(
          'ERROR',
          'isolate',
          'unhandled',
          '-',
          'error=$error stack=${stack.split('\n').take(10).join(' | ')}',
        );
        WebRtcCrashLogger.I.flush();
        _writeCrashLog(error, stack, prefix: 'isolate_crash');
      } catch (_) {}
    }).sendPort);

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

  // L4: 查询并记录上次 Android 进程异常退出原因（OOM/被杀/native 崩溃等）。
  unawaited(recordExitReasons());

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

  // 桌面端：主窗口占主显示器可用区域的 80%（逻辑像素，已排除任务栏）。
  // native 窗口创建即隐藏，仅 Flutter 首帧回调才 Show，故在 runApp 前设好
  // 尺寸即可，Show 时尺寸已正确，无需改 native，亦无闪烁。
  if (isDesktopPlatform) {
    await windowManager.ensureInitialized();
    final display = await screenRetriever.getPrimaryDisplay();
    final visible = display.visibleSize ?? display.size;
    await windowManager.setSize(
      Size(visible.width * 0.8, visible.height * 0.8),
    );
    await windowManager.center();
    // 不调用 windowManager.show()：交给 native 首帧回调，确保无闪烁。
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

/// 全局 ErrorWidget 兜底视图：不依赖 Material/DefaultTextStyle 上下文，
/// 任何 widget build 崩溃时都能安全渲染一个友好提示（自带 Directionality 与显式样式）。
class _GlobalErrorFallback extends StatelessWidget {
  const _GlobalErrorFallback();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFF7F8FA),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFB0B7C3)),
            SizedBox(height: 12),
            Text(
              '页面加载出错，请稍后重试',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF4B5563),
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    // iOS：独立走 App Store 版本检查（不碰 manifest/下载/安装，守 Apple 2.5.2）。
    // 软提示 + 节流：同版本一天最多弹一次、可"跳过此版本"；无网/查不到一律静默。
    if (Platform.isIOS) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      try {
        final svc = ref.read(updateServiceProvider);
        final r = await svc.checkAppStore();
        if (!mounted || !r.hasUpdate) return;
        if (!await svc.shouldPromptAppStore(r.storeVersion)) return;
        if (!mounted) return;
        final ctx = updateNavigatorKey.currentContext;
        if (ctx == null) return;
        await svc.markAppStorePrompted(r.storeVersion);
        await showAppStoreUpdateDialog(
          ctx,
          r,
          onSkip: () => svc.skipAppStoreVersion(r.storeVersion),
        );
      } catch (e) {
        WebRtcCrashLogger.I.log(
            'WARN', 'update', 'startupCheck', '-', 'ios appstore error=$e');
      }
      return;
    }
    // 用户主动通过"安装此版本"固定到了某个版本 → 启动不再自动弹更新对话框。
    // 手动「检查更新」按钮仍可正常使用。
    final pinned =
        await ref.read(updateServiceProvider).isPinnedToCurrentBuild();
    // 把真实锁定状态同步给 UI（isPinnedToCurrentBuild 内部会在本地 build 已变时
    // 清掉 pin 并返回 false，这里据此纠正 provider 初始值）。
    if (mounted) ref.read(isPinnedProvider.notifier).state = pinned;
    if (pinned) {
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
