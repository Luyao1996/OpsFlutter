import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';
import '../providers/terminal_dock_provider.dart';

class TerminalWindowBridge {
  /// 与 desktop 版 API 对齐；非桌面平台无多窗口，永不被触发
  static void Function(int netbarId)? onTerminalsRefreshRequested;

  static void initMainWindowHandler(ProviderContainer container) {}

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
    return null;
  }

  static Future<void> restoreFromDock(
    WidgetRef ref,
    TerminalDockItem item,
  ) async {}

  static Future<void> focusWindow(TerminalDockItem item) async {}

  static Future<void> closeWindowById(int windowId) async {}

  static Future<void> hideWindowById(int windowId) async {}

  static Future<void> closeAllSubWindows() async {}

  static Future<void> sendToMain(
    String method,
    Map<String, dynamic> args,
  ) async {}
}
