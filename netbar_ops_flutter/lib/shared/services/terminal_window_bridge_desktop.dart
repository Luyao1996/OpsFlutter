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
  // Track open windows: uniqueKey (netbarId_terminalId) -> windowId
  static final Map<String, int> _openWindows = {};
  static ProviderContainer? _container;

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
            break;
          case 'terminal_tab_changed':
            final id = args['terminalId'] as int?;
            final netbarId = args['netbarId'] as int? ?? 0;
            final tab = args['lastTab'] as String?;
            if (id != null && tab != null) {
              notifier.setLastTab('${netbarId}_$id', tab);
            }
            break;
        }
      },
    );
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
    controller
      ..setTitle(
          _buildWindowTitle(terminalSnapshot, netbarName, groupName))
      ..center()
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
