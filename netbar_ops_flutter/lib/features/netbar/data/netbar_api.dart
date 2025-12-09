import '../../../core/network/api_client.dart';

/// 网吧模型
class Netbar {
  final int id;
  final String name;
  final String code;
  final String status; // 'online' | 'offline'
  final int terminalCount;
  final String group;
  final String admin;
  final String createTime;
  final String? address;
  final String? contact;
  final String? phone;
  final String? screenshotUrl;
  final NetbarServerMetrics? serverMetrics;
  final List<NetbarAlert>? alerts;
  final NetbarRemoteStatus? remoteStatus;

  Netbar({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    required this.terminalCount,
    required this.group,
    required this.admin,
    required this.createTime,
    this.address,
    this.contact,
    this.phone,
    this.screenshotUrl,
    this.serverMetrics,
    this.alerts,
    this.remoteStatus,
  });

  factory Netbar.fromJson(Map<String, dynamic> json) {
    return Netbar(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? json['token'] ?? '',
      status: json['status'] == 1 || json['status'] == 'online' ? 'online' : 'offline',
      terminalCount: json['total_seats'] ?? json['terminalCount'] ?? 0,
      group: json['group'] ?? '默认分组',
      admin: json['contact'] ?? json['admin'] ?? '-',
      createTime: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal().toString().split(' ')[0]
          : json['createTime'] ?? '-',
      address: json['address'],
      contact: json['contact'],
      phone: json['phone'],
      screenshotUrl: json['screenshotUrl'],
      serverMetrics: json['serverMetrics'] != null
          ? NetbarServerMetrics.fromJson(json['serverMetrics'])
          : null,
      alerts: (json['alerts'] as List<dynamic>?)
          ?.map((e) => NetbarAlert.fromJson(e))
          .toList(),
      remoteStatus: json['remoteStatus'] != null
          ? NetbarRemoteStatus.fromJson(json['remoteStatus'])
          : null,
    );
  }
}

class NetbarServerMetrics {
  final int cpuUsage;
  final int ramUsage;
  final int diskUsage;
  final int networkUp;
  final int networkDown;

  NetbarServerMetrics({
    required this.cpuUsage,
    required this.ramUsage,
    required this.diskUsage,
    required this.networkUp,
    required this.networkDown,
  });

  factory NetbarServerMetrics.fromJson(Map<String, dynamic> json) {
    return NetbarServerMetrics(
      cpuUsage: json['cpuUsage'] ?? 0,
      ramUsage: json['ramUsage'] ?? 0,
      diskUsage: json['diskUsage'] ?? 0,
      networkUp: json['networkUp'] ?? 0,
      networkDown: json['networkDown'] ?? 0,
    );
  }
}

class NetbarAlert {
  final String type;
  final int count;
  final String message;

  NetbarAlert({required this.type, required this.count, required this.message});

  factory NetbarAlert.fromJson(Map<String, dynamic> json) {
    return NetbarAlert(
      type: json['type'] ?? '',
      count: json['count'] ?? 0,
      message: json['message'] ?? '',
    );
  }
}

class NetbarRemoteStatus {
  final bool isActive;
  final String? currentOperator;
  final NetbarLastSession? lastSession;

  NetbarRemoteStatus({required this.isActive, this.currentOperator, this.lastSession});

  factory NetbarRemoteStatus.fromJson(Map<String, dynamic> json) {
    return NetbarRemoteStatus(
      isActive: json['isActive'] ?? false,
      currentOperator: json['currentOperator'],
      lastSession: json['lastSession'] != null
          ? NetbarLastSession.fromJson(json['lastSession'])
          : null,
    );
  }
}

class NetbarLastSession {
  final String time;
  final String operator;
  final String? reason;

  NetbarLastSession({required this.time, required this.operator, this.reason});

  factory NetbarLastSession.fromJson(Map<String, dynamic> json) {
    return NetbarLastSession(
      time: json['time'] ?? '-',
      operator: json['operator'] ?? '-',
      reason: json['reason'],
    );
  }
}

/// 网吧 API
class NetbarApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取网吧列表
  Future<List<Netbar>> getList() async {
    final response = await _client.get('/netbars');
    final List<dynamic> data = response.data is List
        ? response.data
        : (response.data['data'] ?? []);
    return data.map((e) => Netbar.fromJson(e)).toList();
  }

  /// 创建网吧
  Future<Netbar> create(Map<String, dynamic> data) async {
    final response = await _client.post('/netbars', data: data);
    return Netbar.fromJson(response.data);
  }

  /// 更新网吧
  Future<Netbar> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/netbars/$id', data: data);
    return Netbar.fromJson(response.data);
  }

  /// 删除网吧
  Future<void> delete(int id) async {
    await _client.delete('/netbars/$id');
  }
}

