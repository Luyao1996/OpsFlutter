/// 业务操作审计日志模型 —— 对齐 toolboxPage `GET /operationLog` 响应。
class OperationLog {
  final int id;
  final String time;
  final String event;
  final String action;
  final String operator;
  final String description;
  final String ip;

  const OperationLog({
    required this.id,
    required this.time,
    required this.event,
    required this.action,
    required this.operator,
    required this.description,
    required this.ip,
  });

  factory OperationLog.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    String op = '-';
    if (user is Map) {
      final nick = user['nickname'];
      final uname = user['username'];
      if (nick is String && nick.isNotEmpty) {
        op = nick;
      } else if (uname is String && uname.isNotEmpty) {
        op = uname;
      }
    }

    final eventKey = (json['event'] ?? '').toString();
    final eventName = json['event_name'];
    final action = (eventName is String && eventName.isNotEmpty)
        ? eventName
        : eventKey;

    return OperationLog(
      id: (json['id'] as num?)?.toInt() ?? 0,
      time: (json['created_at'] ?? '').toString(),
      event: eventKey,
      action: action,
      operator: op,
      description: (json['description'] ?? '-').toString(),
      ip: (json['ip_address'] ?? '-').toString(),
    );
  }
}

class OperationLogPage {
  final List<OperationLog> items;
  final int total;
  final Map<String, String> eventMap;

  const OperationLogPage({
    required this.items,
    required this.total,
    required this.eventMap,
  });

  static const empty = OperationLogPage(items: [], total: 0, eventMap: {});
}
