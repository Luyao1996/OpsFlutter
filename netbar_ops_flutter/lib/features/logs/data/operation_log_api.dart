import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import 'operation_log_models.dart';

/// 操作日志 API —— 走中央 HTTP，对齐 toolboxPage：
///   `GET  /operationLog`     拉列表（[getLogs]，会抛异常供 UI 处理）
///   `POST /operationLog/add` 业务点上报（[add]，fire-and-forget，永不抛异常）
///
/// 上报设计原则：调用方 fire-and-forget。失败仅打印 debug 日志，
/// 永远不阻塞、不抛异常到主流程。参考 toolboxPage `useRemoteAwaken.js:124,156,180`
/// 与 `XtermCmdDialog.vue:1265,1298`。
class OperationLogApi {
  final ApiClient _client = ApiClient.instance;

  static final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// 查询操作日志列表。
  /// 字段命名/响应结构对齐 toolboxPage `views/LogPage.vue:283-326`：
  ///   响应 `{paginator:{data,total|to}, eventMap}`
  Future<OperationLogPage> getLogs({
    String? event,
    DateTime? startTime,
    DateTime? endTime,
    String? keyword,
    String? user,
    int page = 1,
    int size = 20,
  }) async {
    final params = <String, dynamic>{
      if (event != null && event.isNotEmpty) 'event': event,
      if (startTime != null) 'start_time': _fmt.format(startTime),
      if (endTime != null) 'end_time': _fmt.format(endTime),
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      if (user != null && user.isNotEmpty) 'user': user,
      'page': page,
      'size': size,
    };

    final resp = await _client.get('/operationLog', queryParameters: params);
    final data = resp.data;
    if (data is! Map<String, dynamic>) return OperationLogPage.empty;

    final paginator = data['paginator'];
    if (paginator is! Map<String, dynamic>) return OperationLogPage.empty;

    final items = <OperationLog>[];
    final rawList = paginator['data'];
    if (rawList is List) {
      for (final e in rawList) {
        if (e is Map<String, dynamic>) {
          items.add(OperationLog.fromJson(e));
        }
      }
    }

    final totalRaw = paginator['total'] ?? paginator['to'] ?? 0;
    final total = totalRaw is num ? totalRaw.toInt() : 0;

    final eventMap = <String, String>{};
    final rawMap = data['eventMap'];
    if (rawMap is Map) {
      rawMap.forEach((k, v) => eventMap[k.toString()] = v.toString());
    }

    return OperationLogPage(items: items, total: total, eventMap: eventMap);
  }

  /// 上报一条操作日志（fire-and-forget，不抛异常）。
  /// [event] 事件类型，如 `remote.connect`、`remote.disconnect`、`remote.awaken`、
  ///         `command.connect`、`command.disconnect`。
  /// [description] 人类可读描述，如 `远程连接 PC001`。
  Future<void> add({
    required String event,
    required String description,
  }) async {
    try {
      await _client.post(
        '/operationLog/add',
        data: {
          'event': event,
          'description': description,
        },
      );
    } catch (e) {
      debugPrint('[OperationLog] 上报失败（已忽略）: event=$event err=$e');
    }
  }
}

final operationLogApiProvider = Provider<OperationLogApi>((_) => OperationLogApi());
