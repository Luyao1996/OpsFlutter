import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';

/// 离线生成 2FA 码的本地审计队列。
///
/// 在线路径由服务端记 `unlock.manual` 事件（终端详情「日志管理」Tab 可查）；
/// 走本地计算时这条审计链是断的 —— 服务端根本不知道有人生成过码。这里先把
/// 记录压在本地，等联网后补传到同一个事件流里，尽量把链补回来。
///
/// **不记录码本身**：那是一次性凭证，落盘等于二次泄露。只记「谁、什么时候、
/// 为哪台终端」生成过。
///
/// 已知局限：桌面端终端详情可以开独立子窗口，各窗口的 SharedPreferences 有各自
/// 的内存副本，并发写会互相覆盖导致个别记录丢失。审计属尽力而为的补充手段，
/// 没有按强一致去设计。
class Offline2faAudit {
  const Offline2faAudit._();

  static const String _key = 'offline_2fa_pending';

  /// 队列上限。超出后丢最旧的，避免长期离线把存储撑爆。
  static const int _maxEntries = 200;

  static final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  static List<Map<String, dynamic>> _load() {
    final raw = TokenStore.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    await TokenStore.setString(_key, jsonEncode(list));
  }

  /// 待补传条数，供 UI 提示。
  static int pendingCount() => _load().length;

  /// 记一条离线生成记录。
  static Future<void> record({
    required int terminalId,
    required String terminalName,
    required DateTime at,
  }) async {
    final list = _load();
    list.add({
      'terminal_id': terminalId,
      'terminal_name': terminalName,
      'at': at.millisecondsSinceEpoch,
    });
    while (list.length > _maxEntries) {
      list.removeAt(0);
    }
    await _save(list);
    debugPrint('[Offline2FA] 已记录离线生成，待补传 ${list.length} 条');
  }

  /// 联网后补传。每条成功即出队，失败的留到下次。
  ///
  /// 不复用 [OperationLogApi.add]：它内部把异常吞掉了（上报失败只 debugPrint），
  /// 调用方无从判断成败，照那样写会把没传上去的记录也一并删掉。
  static Future<void> flush() async {
    final list = _load();
    if (list.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (final e in list) {
      try {
        await ApiClient.instance.post(
          '/operationLog/add',
          data: {
            'event': 'unlock.manual',
            'description': _describe(e),
          },
        );
      } catch (_) {
        remaining.add(e);
      }
    }

    if (remaining.length != list.length) {
      await _save(remaining);
      debugPrint(
        '[Offline2FA] 补传完成 ${list.length - remaining.length} 条，'
        '剩余 ${remaining.length} 条',
      );
    }
  }

  /// 事件名沿用服务端已有的 `unlock.manual`，这样补传的记录能和在线记录并列
  /// 显示、一起被筛选到（后端 eventMap 认得这个名字）。补传时间不等于发生时间，
  /// 所以把真实发生时刻写进描述里，否则审计价值大打折扣。
  static String _describe(Map<String, dynamic> e) {
    final name = (e['terminal_name'] ?? '').toString();
    final atMs = (e['at'] as num?)?.toInt();
    final at = atMs != null
        ? _fmt.format(DateTime.fromMillisecondsSinceEpoch(atMs))
        : '时间未知';
    return '离线生成2FA动态码（客户端本地计算，实际发生于 $at）: $name';
  }
}
