import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// 操作日志上报 —— 走中央 HTTP `POST /operationLog/add`。
///
/// 路径与 toolboxPage `merchant.js:41` 对齐：
///   `POST /operationLog/add`（写入）；`GET /operationLog`（拉列表，本类不涉及）。
///
/// 设计原则：调用方 fire-and-forget。失败仅打印 debug 日志，
/// 永远不阻塞、不抛异常到主流程。参考 toolboxPage `useRemoteAwaken.js:124,156,180`
/// 与 `XtermCmdDialog.vue:1265,1298`。
class OperationLogApi {
  final ApiClient _client = ApiClient.instance;

  /// 上报一条操作日志。
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
