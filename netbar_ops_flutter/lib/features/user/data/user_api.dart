import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'user_mock_data.dart';

final userApiProvider = Provider((ref) => UserApi());
final groupApiProvider = Provider((ref) => GroupApi());

class GroupApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<UserGroup>> getAll({String? search}) async {
    final response = await _client.get('/groups', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final list = response.data as List? ?? [];
    return list.map((e) => UserGroup.fromJson(e)).toList();
  }

  Future<UserGroup> create({required String name, int? parentId}) async {
    final response = await _client.post('/groups', data: {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return UserGroup.fromJson(response.data);
  }

  Future<UserGroup> update(int id, {String? name, int? parentId}) async {
    final response = await _client.put('/groups/$id', data: {
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return UserGroup.fromJson(response.data);
  }

  Future<void> delete(int id) async {
    await _client.delete('/groups/$id');
  }
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

  Future<User> create({
    required String username,
    required String password,
    String? name,
    String? role,
    String? email,
    String? phone,
    int? groupId,
  }) async {
    final response = await _client.post('/users', data: {
      'username': username,
      'password': password,
      if (name != null) 'name': name,
      if (role != null) 'role': role,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (groupId != null) 'group_id': groupId,
    });
    return User.fromJson(response.data);
  }

  Future<User> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/users/$id', data: data);
    return User.fromJson(response.data);
  }

  Future<void> delete(int id) async {
    await _client.delete('/users/$id');
  }
}
