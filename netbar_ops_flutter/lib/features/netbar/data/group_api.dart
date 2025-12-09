import '../../../core/network/api_client.dart';

/// 网吧分组模型
class NetbarGroup {
  final int id;
  final String name;
  final int? parentId;
  final String createdAt;
  final String updatedAt;

  NetbarGroup({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory NetbarGroup.fromJson(Map<String, dynamic> json) {
    return NetbarGroup(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      parentId: json['parent_id'],
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

/// 网吧分组 API
class NetbarGroupApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取所有分组
  Future<List<NetbarGroup>> getAll({String? search}) async {
    final queryParams = <String, dynamic>{};
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }
    
    final response = await _client.get(
      '/netbar-groups',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    
    final List<dynamic> data = response.data is List 
        ? response.data 
        : (response.data['data'] ?? []);
    return data.map((e) => NetbarGroup.fromJson(e)).toList();
  }

  /// 创建分组
  Future<NetbarGroup> create(String name, {int? parentId}) async {
    final response = await _client.post('/netbar-groups', data: {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return NetbarGroup.fromJson(response.data);
  }

  /// 更新分组
  Future<NetbarGroup> update(int id, {String? name, int? parentId}) async {
    final response = await _client.put('/netbar-groups/$id', data: {
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return NetbarGroup.fromJson(response.data);
  }

  /// 删除分组
  Future<void> delete(int id) async {
    await _client.delete('/netbar-groups/$id');
  }
}

