import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'user_mock_data.dart';

// 重新导出 User 和 UserGroup，确保其他文件只需导入 user_api.dart
export 'user_mock_data.dart' show User, UserGroup, UserRole, RoleObject, PermissionObject, roleLabels;

final userApiProvider = Provider((ref) => UserApi());
final groupApiProvider = Provider((ref) => GroupApi());

/// 角色模型
class Role {
  final int id;
  final String name;

  Role({required this.id, required this.name});

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
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

/// 角色+权限列表的统一返回（对应 GET /role 的完整响应）
class RolePermissionResponse {
  final List<Role> roles;
  final List<PermissionObject> permissions;
  RolePermissionResponse({required this.roles, required this.permissions});
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
  Future<User> getById(int id) async {
    final response = await _client.get('/user/$id');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('user')) {
      return User.fromJson(data['user']);
    }
    return User.fromJson(data ?? {});
  }

  /// 创建用户
  Future<void> create({
    required String username,
    required String password,
    required String nickname,
    int? groupId,
    bool isManager = false,
    List<int>? roleIds,
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

  /// 获取角色列表
  Future<List<Role>> getRoleList() async {
    final response = await _client.get('/role');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('roles')) {
      return (data['roles'] as List)
          .map((e) => Role.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// 获取角色和细分权限列表（对应 GET /role，同时返回 roles + permissions）
  Future<RolePermissionResponse> getRoleAndPermissionList() async {
    final response = await _client.get('/role');
    final data = response.data;
    List<Role> roles = [];
    List<PermissionObject> permissions = [];
    if (data is Map<String, dynamic>) {
      if (data.containsKey('roles')) {
        roles = (data['roles'] as List)
            .map((e) => Role.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (data.containsKey('permissions')) {
        permissions = (data['permissions'] as List)
            .map((e) => PermissionObject.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }
    return RolePermissionResponse(roles: roles, permissions: permissions);
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
}
