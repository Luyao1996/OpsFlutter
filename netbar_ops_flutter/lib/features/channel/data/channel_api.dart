import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'channel_models.dart';

final channelApiProvider = Provider((ref) => ChannelApi());

class ChannelApi {
  final ApiClient _client = ApiClient.instance;

  // --- Channels ---

  Future<List<Channel>> getList({String? search}) async {
    final response = await _client.get(
      '/channels',
      queryParameters: search != null && search.isNotEmpty ? {'search': search} : null,
    );
    final list = response.data as List? ?? [];
    return list.map((e) => Channel.fromJson(e)).toList();
  }

  Future<Channel> create(Map<String, dynamic> data) async {
    final response = await _client.post('/channels', data: data);
    return Channel.fromJson(response.data);
  }

  Future<Channel> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/channels/$id', data: data);
    return Channel.fromJson(response.data);
  }

  Future<void> delete(int id) async {
    await _client.delete('/channels/$id');
  }

  // --- Resources (Files) ---

  Future<List<ChannelFile>> getResources({
    String? zone,
    int? parentId,
    String? search,
    String? type,
    int? netbarId,
  }) async {
    final params = <String, dynamic>{};
    if (zone != null) params['zone'] = zone;
    if (parentId != null) params['parent_id'] = parentId;
    if (search != null) params['search'] = search;
    if (type != null) params['type'] = type;
    if (netbarId != null) params['netbar_id'] = netbarId;

    final response = await _client.get('/resources', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => ChannelFile.fromJson(e)).toList();
  }

  Future<ChannelFile> createResource(Map<String, dynamic> data) async {
    final response = await _client.post('/resources', data: data);
    return ChannelFile.fromJson(response.data);
  }

  Future<ChannelFile> updateResource(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/resources/$id', data: data);
    return ChannelFile.fromJson(response.data);
  }

  Future<void> deleteResource(int id) async {
    await _client.delete('/resources/$id');
  }

  Future<ChannelFile> uploadResource({
    required File file,
    String? zone,
    int? parentId,
    String? relativePath,
    int? netbarId,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (zone != null) 'zone': zone,
      if (parentId != null) 'parent_id': parentId,
      if (relativePath != null) 'relative_path': relativePath,
      if (netbarId != null) 'netbar_id': netbarId,
    });

    final response = await _client.post('/resources/upload', data: formData);
    return ChannelFile.fromJson(response.data);
  }

  Future<void> copyResource(int id, int? targetParentId) async {
    await _client.post('/resources/$id/copy', data: {'target_parent_id': targetParentId});
  }

  Future<void> moveResource(int id, int? targetParentId) async {
    await _client.put('/resources/$id/move', data: {'target_parent_id': targetParentId});
  }

  // --- Startup Items ---

  Future<List<StartupItem>> getStartupItems({
    String? zone,
    int? netbarId,
  }) async {
    final params = <String, dynamic>{};
    if (zone != null) params['zone'] = zone;
    if (netbarId != null) params['netbar_id'] = netbarId;

    final response = await _client.get('/startup-items', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => StartupItem.fromJson(e)).toList();
  }

  Future<StartupItem> createStartupItem(Map<String, dynamic> data) async {
    final response = await _client.post('/startup-items', data: data);
    return StartupItem.fromJson(response.data);
  }

  Future<StartupItem> updateStartupItem(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/startup-items/$id', data: data);
    return StartupItem.fromJson(response.data);
  }

  Future<void> deleteStartupItem(int id) async {
    await _client.delete('/startup-items/$id');
  }
}
