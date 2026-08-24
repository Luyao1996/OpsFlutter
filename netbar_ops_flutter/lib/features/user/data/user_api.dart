import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'user_mock_data.dart';

// 重新导出 User 和 UserGroup，确保其他文件只需导入 user_api.dart
export 'user_mock_data.dart'
    show User, UserGroup, UserRole, RoleObject, PermissionObject, roleLabels, kDefaultRoleTagLabels;

final userApiProvider = Provider((ref) => UserApi());
final groupApiProvider = Provider((ref) => GroupApi());

/// 权限组（后端术语 role = 权限组）。
/// 列表接口 GET /role 只给基础字段；详情接口 GET /role/{id} 额外带平铺 permissions。
class RoleGroup {
  final int id;
  final String name;
  final String description;

  /// 系统内置组（is_system == 1）：不可删除，仅可编辑
  final bool isSystem;

  /// 平铺权限点。null = 该来源未下发（列表项），与"空数组=没有权限点"区分
  final List<PermissionObject>? permissions;

  RoleGroup({
    required this.id,
    required this.name,
    this.description = '',
    this.isSystem = false,
    this.permissions,
  });

  factory RoleGroup.fromJson(Map<String, dynamic> json) {
    return RoleGroup(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      isSystem: (int.tryParse((json['is_system'] ?? 0).toString()) ?? 0) == 1,
      permissions: (json['permissions'] as List?)
          ?.whereType<Map>()
          .map((e) => PermissionObject.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// 权限树节点（GET /role/permissions 返回嵌套结构：模块[] → children 权限点[]）
class PermissionNode {
  final int id;
  final String name;
  final List<PermissionNode> children;

  PermissionNode({required this.id, required this.name, this.children = const []});

  factory PermissionNode.fromJson(Map<String, dynamic> json) {
    return PermissionNode(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      children: (json['children'] as List?)
              ?.whereType<Map>()
              .map((e) => PermissionNode.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
    );
  }
}

/// 成员详情返回（GET /user/{id}）：user 之外还带 roleMap（角色标签字典）
class UserDetail {
  final User user;

  /// role_tag 数值 → 文案；接口没给时为空 Map，调用方回退 kDefaultRoleTagLabels
  final Map<int, String> roleTagLabels;

  UserDetail({required this.user, this.roleTagLabels = const {}});
}

/// 双因素认证响应
class TwoFactorAuthResponse {
  final String secret;
  final String qrCode;

  TwoFactorAuthResponse({required this.secret, required this.qrCode});

  factory TwoFactorAuthResponse.fromJson(Map<String, dynamic> json) {
    return TwoFactorAuthResponse(
      secret: json['secret'] ?? '',
      qrCode: json['qrCode'] ?? '',
    );
  }
}

/// 小程序绑定响应
class MiniProgramBindResponse {
  final String pwd;
  final String qrCode;

  MiniProgramBindResponse({required this.pwd, required this.qrCode});

  factory MiniProgramBindResponse.fromJson(Map<String, dynamic> json) {
    return MiniProgramBindResponse(
      pwd: json['pwd'] ?? '',
      qrCode: json['qrCode'] ?? '',
    );
  }
}

/// 会员 API Token（GET /user-api-token/{userId} → data.tokens 元素）
class UserApiToken {
  final int id;
  final String name;
  final String token;
  final bool isEnabled;
  final String createdAt;

  const UserApiToken({
    required this.id,
    required this.name,
    required this.token,
    required this.isEnabled,
    required this.createdAt,
  });

  factory UserApiToken.fromJson(Map<String, dynamic> json) {
    return UserApiToken(
      id: _asInt(json['id']),
      name: (json['name'] ?? '').toString(),
      token: (json['token'] ?? '').toString(),
      isEnabled: _asBool(json['is_enabled']),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  // 后端 is_enabled 可能下发 bool / int / 字符串三种形态，统一收口
  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    return s == '1' || s == 'true';
  }
}

/// 分组 API - 适配后端 /api/group
class GroupApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取分组列表（包含用户）
  Future<List<UserGroup>> getList({String? keyword}) async {
    final params = <String, dynamic>{};
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;

    final response = await _client.get('/group', queryParameters: params);
    final data = response.data;

    if (data is Map<String, dynamic> && data.containsKey('groups')) {
      return (data['groups'] as List)
          .map((e) => UserGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// 获取分组详情
  Future<UserGroup> getById(int id) async {
    final response = await _client.get('/group/$id');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('group')) {
      return UserGroup.fromJson(data['group']);
    }
    return UserGroup.fromJson(data ?? {});
  }

  /// 创建分组
  Future<void> create({required String name}) async {
    final formData = FormData.fromMap({'name': name});
    await _client.post('/group', data: formData);
  }

  /// 更新分组
  Future<void> update(int id, {required String name}) async {
    final formData = FormData.fromMap({'name': name});
    await _client.post('/group/$id', data: formData);
  }

  /// 删除分组
  Future<void> delete(int id) async {
    await _client.delete('/group/$id');
  }
}

/// 用户 API - 适配后端 /api/user
class UserApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取用户详情
  Future<User> getById(int id) async => (await getDetail(id)).user;

  /// 获取用户详情（连同同级返回的 roleMap 角色标签字典一起带出）
  Future<UserDetail> getDetail(int id) async {
    final response = await _client.get('/user/$id');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final userJson = data['user'] is Map ? data['user'] : data;
      final labels = <int, String>{};
      if (data['roleMap'] is Map) {
        (data['roleMap'] as Map).forEach((k, v) {
          final key = int.tryParse(k.toString());
          if (key != null) labels[key] = v.toString();
        });
      }
      return UserDetail(
        user: User.fromJson(Map<String, dynamic>.from(userJson as Map)),
        roleTagLabels: labels,
      );
    }
    return UserDetail(user: User.fromJson({}));
  }

  /// 创建用户
  Future<void> create({
    required String username,
    required String password,
    required String nickname,
    int? groupId,
    bool isManager = false,
    List<int>? roleIds,
    int? roleId,
    int? roleTag,
    List<int>? permissionIds,
    List<int>? merchantIds,
  }) async {
    final formData = FormData();
    formData.fields.add(MapEntry('username', username));
    formData.fields.add(MapEntry('password', password));
    formData.fields.add(MapEntry('nickname', nickname));
    formData.fields.add(MapEntry('is_manager', isManager ? '1' : '0'));
    if (groupId != null) {
      formData.fields.add(MapEntry('group_id', groupId.toString()));
    }
    // 权限组：单选，为空则不提交 role_ids[]（与 web 一致，表示不绑定）
    if (roleId != null) {
      formData.fields.add(MapEntry('role_ids[]', roleId.toString()));
    }
    if (roleTag != null) {
      formData.fields.add(MapEntry('role_tag', roleTag.toString()));
    }
    if (roleIds != null) {
      for (final id in roleIds) {
        formData.fields.add(MapEntry('role_ids[]', id.toString()));
      }
    }
    if (permissionIds != null) {
      for (final id in permissionIds) {
        formData.fields.add(MapEntry('permission_ids[]', id.toString()));
      }
    }
    if (merchantIds != null) {
      for (final id in merchantIds) {
        formData.fields.add(MapEntry('merchant_ids[]', id.toString()));
      }
    }

    await _client.post('/user', data: formData);
  }

  /// 更新用户
  Future<void> update(
    int id, {
    String? username,
    String? password,
    String? nickname,
    int? groupId,
    bool? isManager,
    List<int>? roleIds,
    int? roleId,
    int? roleTag,
    List<int>? permissionIds,
    List<int>? merchantIds,
  }) async {
    final formData = FormData();
    if (username != null) formData.fields.add(MapEntry('username', username));
    if (password != null && password.isNotEmpty) {
      formData.fields.add(MapEntry('password', password));
    }
    if (nickname != null) formData.fields.add(MapEntry('nickname', nickname));
    if (groupId != null) {
      formData.fields.add(MapEntry('group_id', groupId.toString()));
    }
    if (isManager != null) {
      formData.fields.add(MapEntry('is_manager', isManager ? '1' : '0'));
    }
    // 权限组：单选，为空则不提交 role_ids[]（与 web 一致，表示不绑定）
    if (roleId != null) {
      formData.fields.add(MapEntry('role_ids[]', roleId.toString()));
    }
    if (roleTag != null) {
      formData.fields.add(MapEntry('role_tag', roleTag.toString()));
    }
    if (roleIds != null) {
      for (final id in roleIds) {
        formData.fields.add(MapEntry('role_ids[]', id.toString()));
      }
    }
    if (permissionIds != null) {
      for (final id in permissionIds) {
        formData.fields.add(MapEntry('permission_ids[]', id.toString()));
      }
    }
    if (merchantIds != null) {
      for (final id in merchantIds) {
        formData.fields.add(MapEntry('merchant_ids[]', id.toString()));
      }
    }

    await _client.put('/user/$id', data: formData);
  }

  /// 删除用户
  Future<void> delete(int id) async {
    await _client.delete('/user/$id');
  }

  // ===== 权限组（后端 role）=====

  /// 权限组列表 GET /role → data.roles（只有基础字段，permissions 为 null）
  Future<List<RoleGroup>> getRoleList() async {
    final response = await _client.get('/role');
    final data = response.data;
    if (data is Map<String, dynamic> && data['roles'] is List) {
      return (data['roles'] as List)
          .whereType<Map>()
          .map((e) => RoleGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// 权限树 GET /role/permissions → data.permissions[].children[]（编辑权限组时勾选用）
  Future<List<PermissionNode>> getRolePermissionTree() async {
    final response = await _client.get('/role/permissions');
    final data = response.data;
    if (data is Map<String, dynamic> && data['permissions'] is List) {
      return (data['permissions'] as List)
          .whereType<Map>()
          .map((e) => PermissionNode.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// 权限组详情 GET /role/{id} → data.role（基础字段 + 平铺 permissions，带 parent_id）
  Future<RoleGroup> getRoleDetail(int id) async {
    final response = await _client.get('/role/$id');
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final roleJson = data['role'] is Map ? data['role'] : data;
      return RoleGroup.fromJson(Map<String, dynamic>.from(roleJson as Map));
    }
    return RoleGroup(id: id, name: '');
  }

  /// name/description 为空时不提交该字段；permission_ids[] 去重后逐个 append
  FormData _buildRoleFormData({
    required String name,
    String? description,
    List<int>? permissionIds,
  }) {
    final formData = FormData();
    if (name.isNotEmpty) formData.fields.add(MapEntry('name', name));
    if (description != null && description.isNotEmpty) {
      formData.fields.add(MapEntry('description', description));
    }
    for (final id in {...?permissionIds}) {
      formData.fields.add(MapEntry('permission_ids[]', id.toString()));
    }
    return formData;
  }

  /// 新增权限组 POST /role
  Future<void> createRole({
    required String name,
    String? description,
    List<int>? permissionIds,
  }) async {
    await _client.post(
      '/role',
      data: _buildRoleFormData(
          name: name, description: description, permissionIds: permissionIds),
    );
  }

  /// 编辑权限组 POST /role/{id}
  Future<void> updateRole(
    int id, {
    required String name,
    String? description,
    List<int>? permissionIds,
  }) async {
    await _client.post(
      '/role/$id',
      data: _buildRoleFormData(
          name: name, description: description, permissionIds: permissionIds),
    );
  }

  /// 删除权限组 DELETE /role/{id}
  Future<void> deleteRole(int id) async {
    await _client.delete('/role/$id');
  }

  /// 获取双因素认证密钥
  Future<TwoFactorAuthResponse> getTwoFactorAuth(int userId) async {
    final response = await _client.get('/user/twoFactorAuth/$userId');
    return TwoFactorAuthResponse.fromJson(response.data ?? {});
  }

  /// 绑定双因素认证
  Future<void> bindTwoFactorAuth(int userId, {required String code}) async {
    await _client.post('/user/twoFactorAuthCheck/$userId', data: {
      'verification': code,
    });
  }

  /// 绑定小程序
  Future<MiniProgramBindResponse> bindMiniProgram(int userId) async {
    final formData = FormData.fromMap({'user_id': userId});
    final response = await _client.post('/user/bindAccount', data: formData);
    return MiniProgramBindResponse.fromJson(response.data ?? {});
  }

  /// 解绑小程序
  Future<void> unbindMiniProgram(int userId) async {
    final formData = FormData.fromMap({'user_id': userId});
    await _client.post('/user/unbindAccount', data: formData);
  }

  /// 修改Token有效期
  Future<void> setTokenRefreshTtl(int userId, {required int ttlSeconds}) async {
    await _client.post('/user/refreshTtl/$userId', data: {
      'token_refresh_ttl': ttlSeconds,
    });
  }

  /// 查询指定会员的 API Token 列表
  Future<List<UserApiToken>> getUserApiTokens(int userId) async {
    final response = await _client.get('/user-api-token/$userId');
    final data = response.data;
    if (data is Map<String, dynamic> && data['tokens'] is List) {
      return (data['tokens'] as List)
          .whereType<Map>()
          .map((e) => UserApiToken.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  /// 为指定会员创建 API Token（[name] 为空则不带该字段，由后端取默认名）
  Future<void> createUserApiToken(int userId, {String? name}) async {
    final formData = FormData();
    if (name != null && name.isNotEmpty) {
      formData.fields.add(MapEntry('name', name));
    }
    await _client.post('/user-api-token/$userId', data: formData);
  }

  /// 修改 Token 名称或启停状态（只提交传入的字段）
  Future<void> updateUserApiToken(
    int userId,
    int tokenId, {
    String? name,
    bool? isEnabled,
  }) async {
    final formData = FormData();
    if (name != null) formData.fields.add(MapEntry('name', name));
    if (isEnabled != null) {
      formData.fields.add(MapEntry('is_enabled', isEnabled ? '1' : '0'));
    }
    await _client.post('/user-api-token/$userId/$tokenId', data: formData);
  }

  /// 删除指定 Token（删除后使用该 Token 的调用立即失效）
  Future<void> deleteUserApiToken(int userId, int tokenId) async {
    await _client.delete('/user-api-token/$userId/$tokenId');
  }
}
