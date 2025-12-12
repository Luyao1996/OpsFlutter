import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';

class TerminalDockItem {
  final int terminalId;
  final Terminal terminal;
  final String lastTab;
  final int? windowId;

  const TerminalDockItem({
    required this.terminalId,
    required this.terminal,
    required this.lastTab,
    this.windowId,
  });

  TerminalDockItem copyWith({
    Terminal? terminal,
    String? lastTab,
    int? windowId,
  }) {
    return TerminalDockItem(
      terminalId: terminalId,
      terminal: terminal ?? this.terminal,
      lastTab: lastTab ?? this.lastTab,
      windowId: windowId ?? this.windowId,
    );
  }

  factory TerminalDockItem.fromMessage(Map<String, dynamic> data) {
    final terminalJson = Map<String, dynamic>.from(data['terminal'] ?? {});
    final terminal = Terminal.fromJson(terminalJson);
    return TerminalDockItem(
      terminalId: data['terminalId'] ?? terminal.id,
      terminal: terminal,
      lastTab: data['lastTab'] ?? '远程控制',
      windowId: data['windowId'],
    );
  }
}

class TerminalDockState {
  final Map<int, TerminalDockItem> minimized;
  final Map<int, String> lastTabs;

  const TerminalDockState({
    this.minimized = const {},
    this.lastTabs = const {},
  });

  TerminalDockState copyWith({
    Map<int, TerminalDockItem>? minimized,
    Map<int, String>? lastTabs,
  }) {
    return TerminalDockState(
      minimized: minimized ?? this.minimized,
      lastTabs: lastTabs ?? this.lastTabs,
    );
  }
}

class TerminalDockNotifier extends StateNotifier<TerminalDockState> {
  TerminalDockNotifier() : super(const TerminalDockState());

  void addMinimized(TerminalDockItem item) {
    final minimized = Map<int, TerminalDockItem>.from(state.minimized);
    minimized[item.terminalId] = item;

    final lastTabs = Map<int, String>.from(state.lastTabs);
    lastTabs[item.terminalId] = item.lastTab;

    state = state.copyWith(minimized: minimized, lastTabs: lastTabs);
  }

  void removeMinimized(int terminalId) {
    final minimized = Map<int, TerminalDockItem>.from(state.minimized);
    minimized.remove(terminalId);
    state = state.copyWith(minimized: minimized);
  }

  void setLastTab(int terminalId, String tab) {
    final lastTabs = Map<int, String>.from(state.lastTabs);
    lastTabs[terminalId] = tab;
    state = state.copyWith(lastTabs: lastTabs);

    if (state.minimized.containsKey(terminalId)) {
      final minimized = Map<int, TerminalDockItem>.from(state.minimized);
      minimized[terminalId] = minimized[terminalId]!.copyWith(lastTab: tab);
      state = state.copyWith(minimized: minimized);
    }
  }

  String lastTabFor(int terminalId) {
    return state.lastTabs[terminalId] ?? '远程控制';
  }

  void clearMinimized() {
    state = state.copyWith(minimized: const {});
  }

  void reset() {
    state = const TerminalDockState();
  }
}

final terminalDockProvider =
    StateNotifierProvider<TerminalDockNotifier, TerminalDockState>(
  (ref) => TerminalDockNotifier(),
);
