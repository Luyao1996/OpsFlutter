import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';
import '../providers/terminal_dock_provider.dart';
import '../utils/platform_utils.dart';

class TerminalWindowBridge {
  static bool _initializedMainHandler = false;

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
            if (id != null) notifier.removeMinimized(id);
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
  }) async {
    if (!isDesktopPlatform) return null;

    final payload = jsonEncode({
      'terminalId': terminalId,
      'initialTab': initialTab,
      'hideNativeChrome': true,
      if (terminalSnapshot != null) 'terminal': terminalSnapshot.toJson(),
    });

    final controller = await DesktopMultiWindow.createWindow(payload);
    controller
      ..setTitle(
          terminalSnapshot != null ? '终端详情 - ${terminalSnapshot.name}' : '终端详情')
      ..center()
      ..show();

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
  }

  static Future<void> sendToMain(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (!isDesktopPlatform) return;
    await DesktopMultiWindow.invokeMethod(0, method, args);
  }
}
