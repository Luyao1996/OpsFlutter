import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';

class TerminalDockItem {
  final int terminalId;
  final int netbarId;
  final Terminal terminal;
  final String lastTab;
  final int? windowId;
  final Uint8List? screenshotBytes;
  final String? netbarName;
  final String? groupName;

  const TerminalDockItem({
    required this.terminalId,
    required this.netbarId,
    required this.terminal,
    required this.lastTab,
    this.windowId,
    this.screenshotBytes,
    this.netbarName,
    this.groupName,
  });

  /// 复合唯一键：网吧ID_终端ID，避免不同网吧同 ID 终端碰撞
  String get uniqueKey => '${netbarId}_$terminalId';

  TerminalDockItem copyWith({
    Terminal? terminal,
    String? lastTab,
    int? windowId,
    Uint8List? screenshotBytes,
    String? netbarName,
    String? groupName,
  }) {
    return TerminalDockItem(
      terminalId: terminalId,
      netbarId: netbarId,
      terminal: terminal ?? this.terminal,
      lastTab: lastTab ?? this.lastTab,
      windowId: windowId ?? this.windowId,
      screenshotBytes: screenshotBytes ?? this.screenshotBytes,
      netbarName: netbarName ?? this.netbarName,
      groupName: groupName ?? this.groupName,
    );
  }

  factory TerminalDockItem.fromMessage(Map<String, dynamic> data) {
    final terminalJson = Map<String, dynamic>.from(data['terminal'] ?? {});
    final terminal = Terminal.fromJson(terminalJson);
    final screenshotBase64 = data['screenshot'] as String?;
    return TerminalDockItem(
      terminalId: data['terminalId'] ?? terminal.id,
      netbarId: data['netbarId'] ?? 0,
      terminal: terminal,
      lastTab: data['lastTab'] ?? '远程控制',
      windowId: data['windowId'],
      screenshotBytes: screenshotBase64 != null
          ? Uint8List.fromList(base64Decode(screenshotBase64))
          : null,
      netbarName: data['netbarName'],
      groupName: data['groupName'],
    );
  }
}

class TerminalDockState {
  final Map<String, TerminalDockItem> minimized;
  final Map<String, String> lastTabs;

  const TerminalDockState({
    this.minimized = const {},
    this.lastTabs = const {},
  });

  TerminalDockState copyWith({
    Map<String, TerminalDockItem>? minimized,
    Map<String, String>? lastTabs,
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
    final key = item.uniqueKey;
    final minimized = Map<String, TerminalDockItem>.from(state.minimized);
    minimized[key] = item;

    final lastTabs = Map<String, String>.from(state.lastTabs);
    lastTabs[key] = item.lastTab;

    state = state.copyWith(minimized: minimized, lastTabs: lastTabs);
  }

  void removeMinimized(String uniqueKey) {
    final minimized = Map<String, TerminalDockItem>.from(state.minimized);
    minimized.remove(uniqueKey);
    state = state.copyWith(minimized: minimized);
  }

  void setLastTab(String uniqueKey, String tab) {
    final lastTabs = Map<String, String>.from(state.lastTabs);
    lastTabs[uniqueKey] = tab;
    state = state.copyWith(lastTabs: lastTabs);

    if (state.minimized.containsKey(uniqueKey)) {
      final minimized = Map<String, TerminalDockItem>.from(state.minimized);
      minimized[uniqueKey] = minimized[uniqueKey]!.copyWith(lastTab: tab);
      state = state.copyWith(minimized: minimized);
    }
  }

  String lastTabFor(String uniqueKey) {
    return state.lastTabs[uniqueKey] ?? '远程控制';
  }

  void updateScreenshot(String uniqueKey, Uint8List bytes) {
    if (!state.minimized.containsKey(uniqueKey)) return;
    final minimized = Map<String, TerminalDockItem>.from(state.minimized);
    minimized[uniqueKey] = minimized[uniqueKey]!.copyWith(screenshotBytes: bytes);
    state = state.copyWith(minimized: minimized);
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
