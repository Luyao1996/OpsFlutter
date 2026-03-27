import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/monitor/data/terminal_api.dart';
import '../providers/terminal_dock_provider.dart';
import '../utils/platform_utils.dart';

class TerminalWindowBridge {
  static bool _initializedMainHandler = false;
  // Track open windows: terminalId -> windowId
  static final Map<int, int> _openWindows = {};

  static void initMainWindowHandler(ProviderContainer container) {
    if (!isDesktopPlatform || _initializedMainHandler) return;
    _initializedMainHandler = true;

    DesktopMultiWindow.setMethodHandler(
      (MethodCall call, int fromWindowId) async {
        final notifier = container.read(terminalDockProvider.notifier);
        final args =
            Map<String, dynamic>.from(call.arguments as Map? ?? const {});

        switch (call.method) {
          case 'terminal_minimize':
            notifier.addMinimized(TerminalDockItem.fromMessage(args));
            break;
          case 'terminal_close':
            final id = args['terminalId'] as int?;
            if (id != null) {
              notifier.removeMinimized(id);
              _openWindows.remove(id);
            }
            break;
          case 'terminal_tab_changed':
            final id = args['terminalId'] as int?;
            final tab = args['lastTab'] as String?;
            if (id != null && tab != null) notifier.setLastTab(id, tab);
            break;
        }
      },
    );
  }

  static Future<int?> openTerminalWindow({
    required int terminalId,
    required String initialTab,
    Terminal? terminalSnapshot,
    Uint8List? screenshotBytes,
  }) async {
    if (!isDesktopPlatform) return null;

    // Check if window already open for this terminal
    final existingWid = _openWindows[terminalId];
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
      _openWindows.remove(terminalId);
    }

    // 截图通过临时文件传递（命令行参数有长度限制，无法直接传 base64）
    String? screenshotTempPath;
    if (screenshotBytes != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/terminal_screenshot_$terminalId.png');
        await file.writeAsBytes(screenshotBytes);
        screenshotTempPath = file.path;
      } catch (_) {}
    }

    final payload = jsonEncode({
      'terminalId': terminalId,
      'initialTab': initialTab,
      'hideNativeChrome': true,
      if (terminalSnapshot != null) 'terminal': terminalSnapshot.toJson(),
      if (screenshotTempPath != null) 'screenshotPath': screenshotTempPath,
    });

    final controller = await DesktopMultiWindow.createWindow(payload);
    controller
      ..setTitle(
          terminalSnapshot != null ? '终端详情 - ${terminalSnapshot.name}' : '终端详情')
      ..center()
      ..show();

    _openWindows[terminalId] = controller.windowId;
    return controller.windowId;
  }

  static Future<void> restoreFromDock(
    WidgetRef ref,
    TerminalDockItem item,
  ) async {
    // Prefer restoring the existing hidden window to avoid rebuilding state.
    final wid = item.windowId;
    if (wid != null) {
      try {
        final ids = await DesktopMultiWindow.getAllSubWindowIds();
        if (ids.contains(wid)) {
          final controller = WindowController.fromWindowId(wid);
          await controller.show();
          ref.read(terminalDockProvider.notifier).removeMinimized(item.terminalId);
          return;
        }
      } catch (_) {
        // Fallback to create new window.
      }
    }

    await openTerminalWindow(
      terminalId: item.terminalId,
      initialTab: item.lastTab,
      terminalSnapshot: item.terminal,
    );
    ref.read(terminalDockProvider.notifier).removeMinimized(item.terminalId);
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
  }

  static Future<void> sendToMain(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (!isDesktopPlatform) return;
    await DesktopMultiWindow.invokeMethod(0, method, args);
  }
}
