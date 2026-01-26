import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'user_mock_data.dart';

final userApiProvider = Provider((ref) => UserApi());
final netbarUserGroupApiProvider = Provider((ref) => NetbarUserGroupApi());

class NetbarUserGroupApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<UserGroup>> getAll(int netbarId, {String? search}) async {
    final response = await _client.get('/netbars/$netbarId/groups', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final list = response.data as List? ?? [];
    return list.map((e) => UserGroup.fromJson(e)).toList();
  }

  Future<UserGroup> create(int netbarId, {required String name, int? parentId}) async {
    final response = await _client.post('/netbars/$netbarId/groups', data: {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return UserGroup.fromJson(response.data);
  }

  Future<UserGroup> update(int netbarId, int id, {String? name, int? parentId}) async {
    final response = await _client.put('/netbars/$netbarId/groups/$id', data: {
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return UserGroup.fromJson(response.data);
  }

  Future<void> delete(int netbarId, int id) async {
    await _client.delete('/netbars/$netbarId/groups/$id');
  }

  Future<List<User>> getGroupUsers(int netbarId, int groupId) async {
    final response = await _client.get('/netbars/$netbarId/groups/$groupId/users');
    final list = response.data as List? ?? [];
    return list.map((e) => User.fromJson(e)).toList();
  }

  Future<void> addUserToGroup(int netbarId, int groupId, int userId) async {
    await _client.post('/netbars/$netbarId/groups/$groupId/users', data: {'user_id': userId});
  }

  Future<void> removeUserFromGroup(int netbarId, int groupId, int userId) async {
    await _client.delete('/netbars/$netbarId/groups/$groupId/users/$userId');
  }

  Future<List<User>> getNetbarUsers(int netbarId, {String? search}) async {
    final response = await _client.get('/netbars/$netbarId/users', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final list = response.data as List? ?? [];
    return list.map((e) => User.fromJson(e)).toList();
  }
}

class CreateUserResult {
  final User user;
  final String initialPassword;

  CreateUserResult({required this.user, required this.initialPassword});
}

class UserApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<User>> getList({String? search, String? role}) async {
    final params = <String, dynamic>{};
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (role != null && role.isNotEmpty) params['role'] = role;

    final response = await _client.get('/users', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => User.fromJson(e)).toList();
  }

  Future<CreateUserResult> create({
    required String username,
    required String password,
    String? name,
    String? role,
    String? email,
    String? phone,
    int? groupId,
    int? netbarId,
    int? netbarGroupId,
  }) async {
    final response = await _client.post('/users', data: {
      'username': username,
      'password': password,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (groupId != null) 'group_id': groupId,
      if (netbarId != null) 'netbar_id': netbarId,
      if (netbarGroupId != null) 'netbar_group_id': netbarGroupId,
    });
    final data = response.data as Map<String, dynamic>? ?? <String, dynamic>{};
    return CreateUserResult(
      user: User.fromJson((data['user'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{}),
      initialPassword: (data['initial_password'] ?? '').toString(),
    );
  }

  Future<User> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/users/$id', data: data);
    return User.fromJson(response.data);
  }

  Future<String> resetPassword(int id) async {
    final response = await _client.post('/users/$id/reset-password');
    final data = response.data as Map<String, dynamic>? ?? <String, dynamic>{};
    return (data['new_password'] ?? '').toString();
  }

  Future<void> delete(int id) async {
    await _client.delete('/users/$id');
  }
}
