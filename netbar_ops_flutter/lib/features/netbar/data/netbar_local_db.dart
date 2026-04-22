import 'dart:convert';

import 'netbar_api.dart';
import 'netbar_pinyin_matcher.dart';
import 'netbar_query.dart';

/// 网吧本地"表"：按 id 存储，全内存，支持 upsert/query/排序/分页/快照序列化。
///
/// 对齐 Web 端 utils/localDb.js 的 alasql 方案，但不引入 SQL 依赖，直接用 Dart 容器。
/// 数据量约数千条，内存占用与查询耗时均可接受。
class NetbarLocalDb {
  final Map<int, Netbar> _rows = {};

  bool get hasData => _rows.isNotEmpty;
  int get count => _rows.length;

  List<Netbar> get all => _rows.values.toList(growable: false);

  void clear() => _rows.clear();

  void upsertAll(List<Netbar> list) {
    for (final item in list) {
      _rows[item.id] = item;
    }
  }

  /// 用整批数据替换表内容（等价于 clear + upsertAll，但只遍历一次）。
  void replaceAll(List<Netbar> list) {
    _rows
      ..clear()
      ..addEntries(list.map((n) => MapEntry(n.id, n)));
  }

  /// 查询：过滤 + 排序 + 分页，返回当前页与总数，以及基于全量的在线统计。
  NetbarQueryResult query(NetbarQueryParams p) {
    Iterable<Netbar> iter = _rows.values;

    if (p.isOnline != null) {
      final want = p.isOnline == 1;
      iter = iter.where((r) => r.isOnline == want);
    }

    if (p.groupId != null) {
      final target = p.groupId!;
      iter = iter.where((r) {
        final groups = r.groups;
        if (groups == null || groups.isEmpty) return false;
        return groups.any((g) => g.id == target);
      });
    }

    if (p.keyword.trim().isNotEmpty) {
      iter = iter.where((r) => NetbarMatcher.match(r, p.keyword));
    }

    final filtered = iter.toList();
    _sort(filtered, p.sort);

    final total = filtered.length;
    final offset = (p.page - 1) * p.pageSize;
    final List<Netbar> rows;
    if (offset >= total || p.pageSize <= 0) {
      rows = const [];
    } else {
      final end = (offset + p.pageSize).clamp(0, total);
      rows = filtered.sublist(offset, end);
    }

    return NetbarQueryResult(rows: rows, total: total, stats: _computeStats());
  }

  OnlineStats _computeStats() {
    int online = 0;
    int offline = 0;
    for (final r in _rows.values) {
      if (r.isOnline) {
        online++;
      } else {
        offline++;
      }
    }
    return OnlineStats(online: online, offline: offline);
  }

  void _sort(List<Netbar> list, NetbarSort sort) {
    switch (sort) {
      case NetbarSort.idAsc:
        list.sort((a, b) => a.id.compareTo(b.id));
        break;
      case NetbarSort.idDesc:
        list.sort((a, b) => b.id.compareTo(a.id));
        break;
      case NetbarSort.terminalAsc:
        list.sort((a, b) => a.terminalCount.compareTo(b.terminalCount));
        break;
      case NetbarSort.terminalDesc:
        list.sort((a, b) => b.terminalCount.compareTo(a.terminalCount));
        break;
      case NetbarSort.statusOnlineFirst:
        list.sort((a, b) {
          if (a.isOnline == b.isOnline) return b.id.compareTo(a.id);
          return a.isOnline ? -1 : 1;
        });
        break;
      case NetbarSort.statusOfflineFirst:
        list.sort((a, b) {
          if (a.isOnline == b.isOnline) return b.id.compareTo(a.id);
          return a.isOnline ? 1 : -1;
        });
        break;
    }
  }

  /// 导出为 JSON 字符串（用于 SharedPreferences 快照）。
  String dumpJson() {
    final list = _rows.values.map((n) => n.toJson()).toList();
    return jsonEncode(list);
  }

  /// 从 JSON 字符串加载（覆盖当前表），返回加载条数；失败返回 0。
  int loadJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List) return 0;
      final parsed = decoded
          .whereType<Map<String, dynamic>>()
          .map(Netbar.fromJson)
          .toList();
      replaceAll(parsed);
      return parsed.length;
    } catch (_) {
      return 0;
    }
  }
}
