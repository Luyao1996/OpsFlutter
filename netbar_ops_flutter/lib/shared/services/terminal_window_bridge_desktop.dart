import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/task_ws_client.dart';
import '../../features/monitor/data/terminal_api.dart';
import '../providers/terminal_dock_provider.dart';
import '../utils/platform_utils.dart';

class TerminalWindowBridge {
  static bool _initializedMainHandler = false;
  // Track open windows: uniqueKey (netbarId_terminalId) -> windowId
  static final Map<String, int> _openWindows = {};
  static ProviderContainer? _container;

  /// 主窗口为各子窗口托管的 WS 流订阅
  /// reqId（形如 `w<fromWindowId>-...`）→ 主窗 TaskWsClient stream 订阅
  static final Map<String, StreamSubscription<dynamic>> _hostStreams = {};

  static void initMainWindowHandler(ProviderContainer container) {
    if (!isDesktopPlatform || _initializedMainHandler) return;
    _initializedMainHandler = true;
    _container = container;

    DesktopMultiWindow.setMethodHandler(
      (MethodCall call, int fromWindowId) async {
        final notifier = container.read(terminalDockProvider.notifier);
        final args =
            Map<String, dynamic>.from(call.arguments as Map? ?? const {});

        switch (call.method) {
          case 'terminal_minimize':
            final item = TerminalDockItem.fromMessage(args);
            notifier.addMinimized(item);
            break;
          case 'terminal_close':
            final id = args['terminalId'] as int?;
            final netbarId = args['netbarId'] as int? ?? 0;
            if (id != null) {
              final key = '${netbarId}_$id';
              notifier.remove(key);
              _openWindows.remove(key);
            }
            // 清理该子窗口名下托管的所有 ws stream，避免僵尸订阅
            await _cleanupHostStreams(fromWindowId);
            break;
          case 'terminal_tab_changed':
            final id = args['terminalId'] as int?;
            final netbarId = args['netbarId'] as int? ?? 0;
            final tab = args['lastTab'] as String?;
            if (id != null && tab != null) {
              notifier.setLastTab('${netbarId}_$id', tab);
            }
            break;
          case 'ws/ensureConnected':
            return await _wsEnsureConnected();
          case 'ws/request':
            return await _wsRequest(args);
          case 'ws/streamOpen':
            return _wsStreamOpen(args, fromWindowId);
          case 'ws/streamCancel':
            return await _wsStreamCancel(args);
          case 'ws/holdingOpen':
            return _wsHoldingOpen(args, fromWindowId);
          case 'ws/holdingCancel':
            return await _wsStreamCancel(args);
          case 'ws/fireAndForget':
            return await _wsFireAndForget(args);
          case 'ws/getState':
            return {'state': TaskWsClient.instance.currentState.name};
          case 'ws/requestRawEvent':
            return await _wsRequestRawEvent(args);
        }
      },
    );

    // WS 状态变化广播到所有当前存在的子窗口
    TaskWsClient.instance.state.listen((s) async {
      try {
        final ids = await DesktopMultiWindow.getAllSubWindowIds();
        for (final id in ids) {
          try {
            await DesktopMultiWindow.invokeMethod(
                id, 'ws/state', {'state': s.name});
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  // ---------- 主窗口侧 ws/* IPC handler ----------

  static Future<Map<String, dynamic>> _wsEnsureConnected() async {
    try {
      await TaskWsClient.instance.ensureConnected();
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _wsRequest(
      Map<String, dynamic> args) async {
    try {
      final fun = args['fun'] as String;
      final seat = args['seat'] as String;
      final merchantId = args['merchantId'] as int;
      final data = args['data'] is Map
          ? Map<String, dynamic>.from(args['data'] as Map)
          : <String, dynamic>{};
      final timeoutMs = (args['timeoutMs'] as int?) ?? 15000;
      final result = await TaskWsClient.instance.request(
        fun: fun,
        seat: seat,
        merchantId: merchantId,
        data: data,
        timeout: Duration(milliseconds: timeoutMs),
      );
      return {'ok': true, 'data': result};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _wsRequestRawEvent(
      Map<String, dynamic> args) async {
    try {
      final event = args['event'] as String;
      final fields = args['customFields'] is Map
          ? Map<String, dynamic>.from(args['customFields'] as Map)
          : <String, dynamic>{};
      final timeoutMs = (args['timeoutMs'] as int?) ?? 15000;
      final result = await TaskWsClient.instance.requestRawEvent(
        event: event,
        customFields: fields,
        timeout: Duration(milliseconds: timeoutMs),
      );
      return {'ok': true, 'data': result};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  static Map<String, dynamic> _wsStreamOpen(
      Map<String, dynamic> args, int fromWindowId) {
    try {
      final reqId = args['reqId'] as String;
      final fun = args['fun'] as String;
      final seat = args['seat'] as String;
      final merchantId = args['merchantId'] as int;
      final data = args['data'] is Map
          ? Map<String, dynamic>.from(args['data'] as Map)
          : <String, dynamic>{};
      final sessionId = args['sessionId'] as String?;

      final stream = TaskWsClient.instance.requestStream(
        fun: fun,
        seat: seat,
        merchantId: merchantId,
        data: data,
        sessionId: sessionId,
      );
      _hostStreams[reqId] = stream.listen(
        (chunk) {
          DesktopMultiWindow.invokeMethod(
              fromWindowId,
              'ws/streamChunk',
              {'reqId': reqId, 'data': chunk}).catchError((Object _) {});
        },
        onError: (Object e) {
          DesktopMultiWindow.invokeMethod(fromWindowId, 'ws/streamEnd',
              {'reqId': reqId, 'ok': false, 'msg': e.toString()})
              .catchError((Object _) {});
          _hostStreams.remove(reqId);
        },
        onDone: () {
          DesktopMultiWindow.invokeMethod(fromWindowId, 'ws/streamEnd',
              {'reqId': reqId, 'ok': true}).catchError((Object _) {});
          _hostStreams.remove(reqId);
        },
      );
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  /// 子窗口持续订阅（holding）：桥接到主窗 subscribeHolding。
  /// 心跳定时器/重连重放由主窗口托管，回推复用 ws/streamChunk；
  /// 取消复用 _wsStreamCancel（cancel 主窗流 → 触发 client._cancelHolding）。
  static Map<String, dynamic> _wsHoldingOpen(
      Map<String, dynamic> args, int fromWindowId) {
    try {
      final reqId = args['reqId'] as String;
      final event = args['event'] as String;
      final merchantId = args['merchantId'] as int;
      final data = args['data'] is Map
          ? Map<String, dynamic>.from(args['data'] as Map)
          : <String, dynamic>{};
      final kind = (args['kind'] as String?) ?? 'holdon';
      final heartbeatMs = (args['heartbeatMs'] as int?) ?? 60000;
      final cancelEvent = args['cancelEvent'] as String?;

      final stream = TaskWsClient.instance.subscribeHolding(
        event: event,
        merchantId: merchantId,
        data: data,
        kind: kind,
        heartbeat: Duration(milliseconds: heartbeatMs),
        cancelEvent: cancelEvent,
      );
      _hostStreams[reqId] = stream.listen(
        (chunk) {
          DesktopMultiWindow.invokeMethod(fromWindowId, 'ws/streamChunk',
              {'reqId': reqId, 'data': chunk}).catchError((Object _) {});
        },
        onError: (Object e) {
          DesktopMultiWindow.invokeMethod(fromWindowId, 'ws/streamEnd',
                  {'reqId': reqId, 'ok': false, 'msg': e.toString()})
              .catchError((Object _) {});
          _hostStreams.remove(reqId);
        },
        onDone: () {
          DesktopMultiWindow.invokeMethod(fromWindowId, 'ws/streamEnd',
              {'reqId': reqId, 'ok': true}).catchError((Object _) {});
          _hostStreams.remove(reqId);
        },
      );
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _wsStreamCancel(
      Map<String, dynamic> args) async {
    final reqId = args['reqId'] as String?;
    if (reqId != null) {
      final sub = _hostStreams.remove(reqId);
      try {
        await sub?.cancel();
      } catch (_) {}
    }
    return {'ok': true};
  }

  static Future<Map<String, dynamic>> _wsFireAndForget(
      Map<String, dynamic> args) async {
    try {
      final fun = args['fun'] as String;
      final seat = args['seat'] as String;
      final merchantId = args['merchantId'] as int;
      final data = args['data'] is Map
          ? Map<String, dynamic>.from(args['data'] as Map)
          : <String, dynamic>{};
      final sessionId = args['sessionId'] as String?;
      await TaskWsClient.instance.fireAndForget(
        fun: fun,
        seat: seat,
        merchantId: merchantId,
        data: data,
        sessionId: sessionId,
      );
      return {'ok': true};
    } catch (e) {
      return {'ok': false, 'msg': e.toString()};
    }
  }

  /// 清理 fromWindowId 名下托管的所有流（reqId 形如 `w<fromWindowId>-...`）
  static Future<void> _cleanupHostStreams(int fromWindowId) async {
    final prefix = 'w$fromWindowId-';
    final stale = _hostStreams.entries
        .where((e) => e.key.startsWith(prefix))
        .toList();
    for (final e in stale) {
      try {
        await e.value.cancel();
      } catch (_) {}
      _hostStreams.remove(e.key);
    }
  }

  static Future<int?> openTerminalWindow({
    required int terminalId,
    required int netbarId,
    required String initialTab,
    Terminal? terminalSnapshot,
    Uint8List? screenshotBytes,
    String? netbarName,
    String? groupName,
    String? subdomainFull,
  }) async {
    if (!isDesktopPlatform) return null;

    final uniqueKey = '${netbarId}_$terminalId';

    // Check if window already open for this terminal in this netbar
    final existingWid = _openWindows[uniqueKey];
    if (existingWid != null) {
      try {
        final ids = await DesktopMultiWindow.getAllSubWindowIds();
        if (ids.contains(existingWid)) {
          // Window still exists, bring to front
          final controller = WindowController.fromWindowId(existingWid);
          await controller.show();
          return existingWid;
        }
      } catch (_) {}
      // Window no longer exists, clean up
      _openWindows.remove(uniqueKey);
    }

    // 截图通过临时文件传递（命令行参数有长度限制，无法直接传 base64）
    String? screenshotTempPath;
    if (screenshotBytes != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/terminal_screenshot_${netbarId}_$terminalId.png');
        await file.writeAsBytes(screenshotBytes);
        screenshotTempPath = file.path;
      } catch (_) {}
    }

    final payload = jsonEncode({
      'terminalId': terminalId,
      'netbarId': netbarId,
      'initialTab': initialTab,
      'hideNativeChrome': true,
      if (terminalSnapshot != null) 'terminal': terminalSnapshot.toJson(),
      if (screenshotTempPath != null) 'screenshotPath': screenshotTempPath,
      if (netbarName != null) 'netbarName': netbarName,
      if (groupName != null) 'groupName': groupName,
      if (subdomainFull != null) 'subdomainFull': subdomainFull,
    });

    final controller = await DesktopMultiWindow.createWindow(payload);
    // 终端详情窗口 = 主窗口的 80%，并居中于主窗口。
    // 注意单位差异：window_manager.getBounds() 返回逻辑像素，而
    // desktop_multi_window 的 setFrame 经 MoveWindow 直接当物理像素使用（无 Scale），
    // 故 left/top/width/height 需 × devicePixelRatio 把逻辑像素换算为物理像素。
    final dpr = PlatformDispatcher.instance.views.first.devicePixelRatio;
    final mb = await windowManager.getBounds();
    final w = mb.width * 0.8, h = mb.height * 0.8;
    final left = mb.left + (mb.width - w) / 2;
    final top = mb.top + (mb.height - h) / 2;
    controller
      ..setTitle(
          _buildWindowTitle(terminalSnapshot, netbarName, groupName))
      ..setFrame(Rect.fromLTWH(left * dpr, top * dpr, w * dpr, h * dpr))
      ..show();

    _openWindows[uniqueKey] = controller.windowId;

    // Sync to dock provider
    if (_container != null && terminalSnapshot != null) {
      _container!.read(terminalDockProvider.notifier).addOpened(
            TerminalDockItem(
              terminalId: terminalId,
              netbarId: netbarId,
              terminal: terminalSnapshot,
              lastTab: initialTab,
              windowId: controller.windowId,
              screenshotBytes: screenshotBytes,
              netbarName: netbarName,
              groupName: groupName,
            ),
          );
    }

    return controller.windowId;
  }

  static String _buildWindowTitle(Terminal? terminal, String? netbarName, String? groupName) {
    final parts = <String>['终端详情'];
    if (netbarName != null && netbarName.isNotEmpty) parts.add(netbarName);
    if (groupName != null && groupName.isNotEmpty) parts.add(groupName);
    if (terminal != null) parts.add(terminal.name);
    return parts.join(' - ');
  }

  static Future<void> restoreFromDock(
    WidgetRef ref,
    TerminalDockItem item,
  ) async {
    final uniqueKey = item.uniqueKey;
    final notifier = ref.read(terminalDockProvider.notifier);
    // Prefer restoring the existing hidden window to avoid rebuilding state.
    final wid = item.windowId;
    if (wid != null) {
      try {
        final ids = await DesktopMultiWindow.getAllSubWindowIds();
        if (ids.contains(wid)) {
          final controller = WindowController.fromWindowId(wid);
          await controller.show();
          notifier.markOpened(uniqueKey);
          return;
        }
      } catch (_) {
        // Fallback to create new window.
      }
    }

    // openTerminalWindow will call addOpened internally
    await openTerminalWindow(
      terminalId: item.terminalId,
      netbarId: item.netbarId,
      initialTab: item.lastTab,
      terminalSnapshot: item.terminal,
      netbarName: item.netbarName,
      groupName: item.groupName,
    );
  }

  /// Bring an open terminal window to front
  static Future<void> focusWindow(TerminalDockItem item) async {
    final wid = item.windowId;
    if (wid == null) return;
    try {
      final ids = await DesktopMultiWindow.getAllSubWindowIds();
      if (ids.contains(wid)) {
        final controller = WindowController.fromWindowId(wid);
        await controller.show();
      }
    } catch (_) {}
  }

  static Future<void> closeWindowById(int windowId) async {
    if (!isDesktopPlatform) return;
    final controller = WindowController.fromWindowId(windowId);
    await controller.close();
  }

  static Future<void> hideWindowById(int windowId) async {
    if (!isDesktopPlatform) return;
    final controller = WindowController.fromWindowId(windowId);
    await controller.hide();
  }

  static Future<void> closeAllSubWindows() async {
    if (!isDesktopPlatform) return;
    try {
      final ids = await DesktopMultiWindow.getAllSubWindowIds();
      for (final id in ids) {
        try {
          await closeWindowById(id);
        } catch (_) {}
      }
    } catch (_) {}
    _openWindows.clear();
    _container?.read(terminalDockProvider.notifier).clearAll();
  }

  static Future<void> sendToMain(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (!isDesktopPlatform) return;
    await DesktopMultiWindow.invokeMethod(0, method, args);
  }
}
