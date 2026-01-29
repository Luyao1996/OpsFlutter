import '../../../core/network/api_client.dart';

/// 分组用户信息
class GroupUser {
  final int id;
  final int? groupId;
  final String nickname;
  final String? phoneNumber;
  final bool isManager;
  final int? tokenRefreshTtl;
  final bool isBindWx;
  final bool isBind2fa;

  GroupUser({
    required this.id,
    this.groupId,
    required this.nickname,
    this.phoneNumber,
    required this.isManager,
    this.tokenRefreshTtl,
    required this.isBindWx,
    required this.isBind2fa,
  });

  factory GroupUser.fromJson(Map<String, dynamic> json) {
    return GroupUser(
      id: json['id'] ?? 0,
      groupId: json['group_id'],
      nickname: json['nickname'] ?? '',
      phoneNumber: json['phone_number'],
      isManager: json['is_manager'] == true || json['is_manager'] == 1,
      tokenRefreshTtl: json['token_refresh_ttl'],
      isBindWx: json['is_bind_wx'] == true || json['is_bind_wx'] == 1,
      isBind2fa: json['is_bind_2fa'] == true || json['is_bind_2fa'] == 1,
    );
  }
}

/// 区域信息
class District {
  final int id;
  final String name;

  District({required this.id, required this.name});

  factory District.fromJson(Map<String, dynamic> json) {
    return District(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

/// 分组模型 - 适配后端字段
class Group {
  final int id;
  final String name;
  final String? serverPwd;
  final List<GroupUser>? users;
  final List<District>? districts;
  final String? createdAt;
  final String? updatedAt;

  Group({
    required this.id,
    required this.name,
    this.serverPwd,
    this.users,
    this.districts,
    this.createdAt,
    this.updatedAt,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      serverPwd: json['server_pwd'],
      users: (json['users'] as List?)?.map((e) => GroupUser.fromJson(e as Map<String, dynamic>)).toList(),
      districts: (json['districts'] as List?)?.map((e) => District.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'server_pwd': serverPwd,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// 分组列表响应
class GroupListResponse {
  final List<Group> groups;

  GroupListResponse({required this.groups});

  factory GroupListResponse.fromJson(Map<String, dynamic> json) {
    return GroupListResponse(
      groups: (json['groups'] as List?)?.map((e) => Group.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }
}

/// 网吧分组模型 - 保留兼容旧代码
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

  /// 从Group转换
  factory NetbarGroup.fromGroup(Group group) {
    return NetbarGroup(
      id: group.id,
      name: group.name,
      parentId: null,
      createdAt: group.createdAt ?? '',
      updatedAt: group.updatedAt ?? '',
    );
  }
}

/// 分组 API - 适配后端 /api/group
class GroupApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取分组列表（完整响应）
  Future<GroupListResponse> getListFull({String? keyword}) async {
    final params = <String, dynamic>{};
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;

    final response = await _client.get('/group', queryParameters: params);
    return GroupListResponse.fromJson(response.data ?? {});
  }

  /// 获取所有分组
  Future<List<Group>> getAll({String? keyword}) async {
    final fullResponse = await getListFull(keyword: keyword);
    return fullResponse.groups;
  }

  /// 获取分组详情
  Future<Group> getById(int id) async {
    final response = await _client.get('/group/$id');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('group')) {
      return Group.fromJson(data['group']);
    }
    return Group.fromJson(data ?? {});
  }

  /// 创建分组
  Future<void> create({
    required String name,
    List<Map<String, dynamic>>? districts,
  }) async {
    await _client.post('/group', data: {
      'name': name,
      if (districts != null) 'districts': districts,
    });
  }

  /// 更新分组
  Future<void> update(int id, {
    required String name,
    List<Map<String, dynamic>>? districts,
  }) async {
    await _client.put('/group/$id', data: {
      'name': name,
      if (districts != null) 'districts': districts,
    });
  }

  /// 删除分组
  Future<void> delete(int id) async {
    await _client.delete('/group/$id');
  }

  /// 设置分组服务器密码
  Future<void> setPassword(int id, {required String password}) async {
    await _client.post('/group/setPwd/$id', data: {
      'password': password,
    });
  }
}

/// 网吧分组 API - 保留兼容旧代码
class NetbarGroupApi {
  final GroupApi _groupApi = GroupApi();

  /// 获取所有分组
  Future<List<NetbarGroup>> getAll({String? search}) async {
    final groups = await _groupApi.getAll(keyword: search);
    return groups.map((g) => NetbarGroup.fromGroup(g)).toList();
  }

  /// 创建分组
  Future<NetbarGroup> create(String name, {int? parentId}) async {
    await _groupApi.create(name: name);
    // 后端不返回创建的对象，返回一个临时对象
    return NetbarGroup(
      id: 0,
      name: name,
      parentId: parentId,
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  /// 更新分组
  Future<NetbarGroup> update(int id, {String? name, int? parentId}) async {
    if (name != null) {
      await _groupApi.update(id, name: name);
    }
    return NetbarGroup(
      id: id,
      name: name ?? '',
      parentId: parentId,
      createdAt: '',
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  /// 删除分组
  Future<void> delete(int id) async {
    await _groupApi.delete(id);
  }
}
