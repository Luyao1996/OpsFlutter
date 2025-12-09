import '../../../core/network/api_client.dart';

/// 网吧区域模型
class NetbarArea {
  final int id;
  final int netbarId;
  final String name;
  final String startIp;
  final String endIp;
  final String createdAt;
  final String updatedAt;

  NetbarArea({
    required this.id,
    required this.netbarId,
    required this.name,
    required this.startIp,
    required this.endIp,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NetbarArea.fromJson(Map<String, dynamic> json) {
    return NetbarArea(
      id: json['id'] ?? 0,
      netbarId: json['netbar_id'] ?? 0,
      name: json['name'] ?? '',
      startIp: json['start_ip'] ?? '',
      endIp: json['end_ip'] ?? '',
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

/// 区域 API
class AreaApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取指定网吧的区域
  Future<List<NetbarArea>> getByNetbar(int netbarId) async {
    final response = await _client.get('/areas/netbar/$netbarId');
    final List<dynamic> data = response.data is List 
        ? response.data 
        : (response.data['data'] ?? []);
    return data.map((e) => NetbarArea.fromJson(e)).toList();
  }

  /// 创建区域
  Future<NetbarArea> create(int netbarId, {
    required String name,
    String? startIp,
    String? endIp,
  }) async {
    final response = await _client.post('/areas/netbar/$netbarId', data: {
      'netbar_id': netbarId,
      'name': name,
      if (startIp != null) 'start_ip': startIp,
      if (endIp != null) 'end_ip': endIp,
    });
    return NetbarArea.fromJson(response.data);
  }

  /// 更新区域
  Future<NetbarArea> update(int id, {
    String? name,
    String? startIp,
    String? endIp,
  }) async {
    final response = await _client.put('/areas/$id', data: {
      if (name != null) 'name': name,
      if (startIp != null) 'start_ip': startIp,
      if (endIp != null) 'end_ip': endIp,
    });
    return NetbarArea.fromJson(response.data);
  }

  /// 删除区域
  Future<void> delete(int id) async {
    await _client.delete('/areas/$id');
  }
}

