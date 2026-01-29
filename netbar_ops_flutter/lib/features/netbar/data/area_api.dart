import '../../../core/network/api_client.dart';

/// 行政区域模型（后端支持）
class District {
  final int id;
  final String name;
  final int? parentId;

  District({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory District.fromJson(Map<String, dynamic> json) {
    return District(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      parentId: json['parent_id'],
    );
  }
}

/// 行政区域 API - 适配后端 /api/district
class DistrictApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取子区域列表
  Future<List<District>> getChildren({int parentId = 0}) async {
    final response = await _client.get('/district/filter', queryParameters: {
      'parent_id': parentId,
    });

    final data = response.data;
    if (data is List) {
      return data.map((e) => District.fromJson(e as Map<String, dynamic>)).toList();
    }
    return [];
  }

  /// 获取省份列表
  Future<List<District>> getProvinces() => getChildren(parentId: 0);

  /// 获取城市列表
  Future<List<District>> getCities(int provinceId) => getChildren(parentId: provinceId);

  /// 获取区县列表
  Future<List<District>> getDistricts(int cityId) => getChildren(parentId: cityId);
}

/// 网吧区域模型（后端未实现，保留兼容）
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

/// 网吧区域 API（后端未实现，调用会报错）
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
