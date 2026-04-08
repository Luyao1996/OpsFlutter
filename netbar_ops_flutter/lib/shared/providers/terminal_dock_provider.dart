import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/monitor/data/terminal_api.dart';

enum DockItemStatus { open, minimized }

class TerminalDockItem {
  final int terminalId;
  final int netbarId;
  final Terminal terminal;
  final String lastTab;
  final int? windowId;
  final Uint8List? screenshotBytes;
  final String? netbarName;
  final String? groupName;
  final DockItemStatus status;

  const TerminalDockItem({
    required this.terminalId,
    required this.netbarId,
    required this.terminal,
    required this.lastTab,
    this.windowId,
    this.screenshotBytes,
    this.netbarName,
    this.groupName,
    this.status = DockItemStatus.open,
  });

  /// 复合唯一键：网吧ID_终端ID，避免不同网吧同 ID 终端碰撞
  String get uniqueKey => '${netbarId}_$terminalId';

  bool get isMinimized => status == DockItemStatus.minimized;

  TerminalDockItem copyWith({
    Terminal? terminal,
    String? lastTab,
    int? windowId,
    Uint8List? screenshotBytes,
    String? netbarName,
    String? groupName,
    DockItemStatus? status,
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
      status: status ?? this.status,
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
      status: DockItemStatus.minimized,
    );
  }
}

class TerminalDockState {
  final Map<String, TerminalDockItem> items;
  final Map<String, String> lastTabs;

  const TerminalDockState({
    this.items = const {},
    this.lastTabs = const {},
  });

  /// 向后兼容：只返回最小化的
  Map<String, TerminalDockItem> get minimized => Map.fromEntries(
        items.entries.where((e) => e.value.isMinimized),
      );

  /// 只返回已打开的
  Map<String, TerminalDockItem> get opened => Map.fromEntries(
        items.entries.where((e) => !e.value.isMinimized),
      );

  TerminalDockState copyWith({
    Map<String, TerminalDockItem>? items,
    Map<String, String>? lastTabs,
  }) {
    return TerminalDockState(
      items: items ?? this.items,
      lastTabs: lastTabs ?? this.lastTabs,
    );
  }
}

class TerminalDockNotifier extends StateNotifier<TerminalDockState> {
  TerminalDockNotifier() : super(const TerminalDockState());

  void addOpened(TerminalDockItem item) {
    final key = item.uniqueKey;
    final items = Map<String, TerminalDockItem>.from(state.items);
    items[key] = item.copyWith(status: DockItemStatus.open);

    final lastTabs = Map<String, String>.from(state.lastTabs);
    lastTabs[key] = item.lastTab;

    state = state.copyWith(items: items, lastTabs: lastTabs);
  }

  void addMinimized(TerminalDockItem item) {
    final key = item.uniqueKey;
    final items = Map<String, TerminalDockItem>.from(state.items);
    items[key] = item.copyWith(status: DockItemStatus.minimized);

    final lastTabs = Map<String, String>.from(state.lastTabs);
    lastTabs[key] = item.lastTab;

    state = state.copyWith(items: items, lastTabs: lastTabs);
  }

  void markMinimized(String uniqueKey) {
    if (!state.items.containsKey(uniqueKey)) return;
    final items = Map<String, TerminalDockItem>.from(state.items);
    items[uniqueKey] = items[uniqueKey]!.copyWith(status: DockItemStatus.minimized);
    state = state.copyWith(items: items);
  }

  void markOpened(String uniqueKey) {
    if (!state.items.containsKey(uniqueKey)) return;
    final items = Map<String, TerminalDockItem>.from(state.items);
    items[uniqueKey] = items[uniqueKey]!.copyWith(status: DockItemStatus.open);
    state = state.copyWith(items: items);
  }

  void remove(String uniqueKey) {
    final items = Map<String, TerminalDockItem>.from(state.items);
    items.remove(uniqueKey);
    state = state.copyWith(items: items);
  }

  void removeMinimized(String uniqueKey) {
    remove(uniqueKey);
  }

  void setLastTab(String uniqueKey, String tab) {
    final lastTabs = Map<String, String>.from(state.lastTabs);
    lastTabs[uniqueKey] = tab;
    state = state.copyWith(lastTabs: lastTabs);

    if (state.items.containsKey(uniqueKey)) {
      final items = Map<String, TerminalDockItem>.from(state.items);
      items[uniqueKey] = items[uniqueKey]!.copyWith(lastTab: tab);
      state = state.copyWith(items: items);
    }
  }

  String lastTabFor(String uniqueKey) {
    return state.lastTabs[uniqueKey] ?? '远程控制';
  }

  void updateScreenshot(String uniqueKey, Uint8List bytes) {
    if (!state.items.containsKey(uniqueKey)) return;
    final items = Map<String, TerminalDockItem>.from(state.items);
    items[uniqueKey] = items[uniqueKey]!.copyWith(screenshotBytes: bytes);
    state = state.copyWith(items: items);
  }

  void clearMinimized() {
    final items = Map<String, TerminalDockItem>.from(state.items);
    items.removeWhere((_, v) => v.isMinimized);
    state = state.copyWith(items: items);
  }

  void clearAll() {
    state = state.copyWith(items: const {});
  }

  void reset() {
    state = const TerminalDockState();
  }
}

final terminalDockProvider =
    StateNotifierProvider<TerminalDockNotifier, TerminalDockState>(
  (ref) => TerminalDockNotifier(),
);
