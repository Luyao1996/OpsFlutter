import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/terminal_dock_provider.dart';
import 'terminal_window_bridge.dart';

class TerminalDockActions {
  static Future<void> closeAllMinimized(ProviderContainer container) async {
    final state = container.read(terminalDockProvider);
    final notifier = container.read(terminalDockProvider.notifier);
    await _closeAllMinimizedInternal(state, notifier);
  }

  static Future<void> closeAllMinimizedWithRef(WidgetRef ref) async {
    final state = ref.read(terminalDockProvider);
    final notifier = ref.read(terminalDockProvider.notifier);
    await _closeAllMinimizedInternal(state, notifier);
  }

  static Future<void> _closeAllMinimizedInternal(
    TerminalDockState state,
    TerminalDockNotifier notifier,
  ) async {
    final items = state.minimized.values.toList();
    for (final item in items) {
      final wid = item.windowId;
      if (wid != null) {
        try {
          await TerminalWindowBridge.closeWindowById(wid);
        } catch (_) {}
      }
    }
    notifier.clearMinimized();
  }
}

