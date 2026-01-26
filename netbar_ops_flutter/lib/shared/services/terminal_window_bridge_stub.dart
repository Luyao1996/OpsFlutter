import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';
import '../providers/terminal_dock_provider.dart';

class TerminalWindowBridge {
  static void initMainWindowHandler(ProviderContainer container) {}

  static Future<int?> openTerminalWindow({
    required int terminalId,
    required String initialTab,
    Terminal? terminalSnapshot,
  }) async {
    return null;
  }

  static Future<void> restoreFromDock(
    WidgetRef ref,
    TerminalDockItem item,
  ) async {}

  static Future<void> closeWindowById(int windowId) async {}

  static Future<void> hideWindowById(int windowId) async {}

  static Future<void> closeAllSubWindows() async {}

  static Future<void> sendToMain(
    String method,
    Map<String, dynamic> args,
  ) async {}
}
