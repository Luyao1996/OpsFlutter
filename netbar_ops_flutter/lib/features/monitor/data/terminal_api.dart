import '../../../core/network/api_client.dart';

/// 终端模型
class Terminal {
  final int id;
  final String name;
  final String code;
  final int netbarId;
  final int? areaId;
  final String ip;
  final String mac;
  final String os;
  final String type; // server, client, console, cashier
  final int status; // 0: 离线, 1: 在线空闲, 2: 使用中
  final double cpuUsage;
  final double ramUsage;
  final double gpuUsage;
  final double diskUsage;
  final String uptime;
  final String? lastOnline;
  final String? lastHeartbeat;
  final String? createdAt;
  final String? updatedAt;

  Terminal({
    required this.id,
    required this.name,
    required this.code,
    required this.netbarId,
    this.areaId,
    required this.ip,
    required this.mac,
    required this.os,
    required this.type,
    required this.status,
    required this.cpuUsage,
    required this.ramUsage,
    required this.gpuUsage,
    required this.diskUsage,
    required this.uptime,
    this.lastOnline,
    this.lastHeartbeat,
    this.createdAt,
    this.updatedAt,
  });

  factory Terminal.fromJson(Map<String, dynamic> json) {
    return Terminal(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      netbarId: json['netbar_id'] ?? 0,
      areaId: json['area_id'],
      ip: json['ip'] ?? '',
      mac: json['mac'] ?? '',
      os: json['os'] ?? '',
      type: json['type'] ?? 'client',
      status: json['status'] ?? 0,
      cpuUsage: (json['cpu_usage'] ?? 0).toDouble(),
      ramUsage: (json['ram_usage'] ?? 0).toDouble(),
      gpuUsage: (json['gpu_usage'] ?? 0).toDouble(),
      diskUsage: (json['disk_usage'] ?? 0).toDouble(),
      uptime: json['uptime'] ?? '0天',
      lastOnline: json['last_online'],
      lastHeartbeat: json['last_heartbeat'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  /// 获取状态字符串
  String get statusString {
    switch (status) {
      case 0:
        return 'offline';
      case 2:
        return 'busy';
      default:
        return 'online';
    }
  }

  /// 是否为关键设备
  bool get isKeyDevice => ['server', 'console', 'cashier'].contains(type);
}

/// Terminal API 服务
class TerminalApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取所有终端
  Future<List<Terminal>> getAll({
    String? search,
    int? netbarId,
    int? status,
    String? type,
  }) async {
    final params = <String, dynamic>{};
    if (search != null) params['search'] = search;
    if (netbarId != null) params['netbar_id'] = netbarId;
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;

    final response = await _client.get('/terminals', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => Terminal.fromJson(e)).toList();
  }

  /// 获取单个终端
  Future<Terminal> getById(int id) async {
    final response = await _client.get('/terminals/$id');
    return Terminal.fromJson(response.data);
  }

  /// 远程操作
  Future<void> remote(int id, String action) async {
    await _client.post('/terminals/$id/remote', data: {'action': action});
  }
}

