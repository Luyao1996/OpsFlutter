import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/token_store.dart';

/// 已打开的网吧标签页
class OpenedNetbarTab {
  final int id;
  final String name;
  final String status;
  final DateTime openedAt;

  OpenedNetbarTab({
    required this.id,
    required this.name,
    required this.status,
    required this.openedAt,
  });

  /// 计算打开时长（分钟）
  int get minutesOpened {
    return DateTime.now().difference(openedAt).inMinutes;
  }

  /// 格式化打开时长
  String get formattedDuration {
    final mins = minutesOpened;
    if (mins < 1) return '刚打开';
    if (mins < 60) return '$mins分';
    final hours = mins ~/ 60;
    return '$hours小时';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'openedAt': openedAt.toIso8601String(),
  };

  factory OpenedNetbarTab.fromJson(Map<String, dynamic> json) {
    return OpenedNetbarTab(
      id: json['id'],
      name: json['name'],
      status: json['status'],
      openedAt: DateTime.parse(json['openedAt']),
    );
  }
}

/// 网吧标签页状态
class NetbarTabsState {
  final List<OpenedNetbarTab> tabs;
  final int? activeTabId;

  NetbarTabsState({
    this.tabs = const [],
    this.activeTabId,
  });

  OpenedNetbarTab? get activeTab {
    if (activeTabId == null) return null;
    try {
      return tabs.firstWhere((t) => t.id == activeTabId);
    } catch (_) {
      return null;
    }
  }

  NetbarTabsState copyWith({
    List<OpenedNetbarTab>? tabs,
    int? activeTabId,
  }) {
    return NetbarTabsState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }
}

/// 网吧标签页管理器
class NetbarTabsNotifier extends StateNotifier<NetbarTabsState> {
  NetbarTabsNotifier() : super(_loadFromStorage());

  static const _storageKey = 'netbar_tabs';

  static NetbarTabsState _loadFromStorage() {
    final data = TokenStore.getString(_storageKey);
    if (data == null) return NetbarTabsState();
    try {
      final json = jsonDecode(data);
      final tabs = (json['tabs'] as List)
          .map((t) => OpenedNetbarTab.fromJson(t))
          .toList();
      return NetbarTabsState(
        tabs: tabs,
        activeTabId: json['activeTabId'],
      );
    } catch (_) {
      return NetbarTabsState();
    }
  }

  Future<void> _saveToStorage() async {
    final data = {
      'tabs': state.tabs.map((t) => t.toJson()).toList(),
      'activeTabId': state.activeTabId,
    };
    await TokenStore.setString(_storageKey, jsonEncode(data));
  }

  /// 打开新标签页（如果已存在则激活）
  Future<void> openTab(int id, String name, String status) async {
    final existingIndex = state.tabs.indexWhere((t) => t.id == id);
    if (existingIndex >= 0) {
      // 已存在，只激活
      state = state.copyWith(activeTabId: id);
    } else {
      // 新建标签页
      final newTab = OpenedNetbarTab(
        id: id,
        name: name,
        status: status,
        openedAt: DateTime.now(),
      );
      state = NetbarTabsState(
        tabs: [...state.tabs, newTab],
        activeTabId: id,
      );
    }
    await _saveToStorage();
  }

  /// 关闭标签页
  Future<void> closeTab(int id) async {
    if (state.tabs.length <= 1) return; // 保留至少一个网吧标签

    final tabs = state.tabs.where((t) => t.id != id).toList();
    if (tabs.length == state.tabs.length) return;

    int? newActiveId = state.activeTabId;
    if (state.activeTabId == id) {
      newActiveId = tabs.isNotEmpty ? tabs.last.id : null;
    }
    state = NetbarTabsState(tabs: tabs, activeTabId: newActiveId);
    await _saveToStorage();
  }

  /// 切换到指定标签页
  Future<void> switchToTab(int id) async {
    if (state.tabs.any((t) => t.id == id)) {
      state = state.copyWith(activeTabId: id);
      await _saveToStorage();
    }
  }

  Future<void> resetAll() async {
    state = NetbarTabsState();
    await _saveToStorage();
  }

  Future<void> replaceAll(NetbarTabsState next) async {
    state = next;
    await _saveToStorage();
  }
}

final netbarTabsProvider = StateNotifierProvider<NetbarTabsNotifier, NetbarTabsState>((ref) {
  return NetbarTabsNotifier();
});
