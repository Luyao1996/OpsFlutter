import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import 'channel_models.dart';

final channelApiProvider = Provider((ref) => ChannelApi());

/// 文件列表响应
class FileViewResponse {
  final List<ChannelFile> files;
  final List<MerchantBrief> merchants;

  FileViewResponse({required this.files, required this.merchants});

  factory FileViewResponse.fromJson(Map<String, dynamic> json) {
    return FileViewResponse(
      files: (json['files'] as List?)?.map((e) => ChannelFile.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      merchants: (json['merchants'] as List?)?.map((e) => MerchantBrief.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }
}

/// 启动项分页响应
class StartupPaginatorResponse {
  final List<StartupItem> data;
  final int currentPage;
  final int perPage;
  final int? total;

  StartupPaginatorResponse({
    required this.data,
    required this.currentPage,
    required this.perPage,
    this.total,
  });

  factory StartupPaginatorResponse.fromJson(Map<String, dynamic> json) {
    final paginator = json['paginator'] as Map<String, dynamic>? ?? json;
    return StartupPaginatorResponse(
      data: (paginator['data'] as List?)?.map((e) => StartupItem.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      currentPage: paginator['current_page'] ?? 1,
      perPage: paginator['per_page'] ?? 20,
      total: paginator['total'],
    );
  }
}

class ChannelApi {
  final ApiClient _client = ApiClient.instance;

  // --- Channels (后端可能不支持，会报错) ---

  Future<List<Channel>> getList({String? search}) async {
    final response = await _client.get(
      '/channels',
      queryParameters: search != null && search.isNotEmpty ? {'search': search} : null,
    );
    final list = response.data as List? ?? [];
    return list.map((e) => Channel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Channel> create(Map<String, dynamic> data) async {
    final response = await _client.post('/channels', data: data);
    return Channel.fromJson(response.data ?? {});
  }

  Future<Channel> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/channels/$id', data: data);
    return Channel.fromJson(response.data ?? {});
  }

  Future<void> delete(int id) async {
    await _client.delete('/channels/$id');
  }

  // --- Files (适配后端 /api/file/*) ---

  /// 获取文件列表（完整响应）
  Future<FileViewResponse> getFilesFull({
    int? parentId,
    int? merchantId,
  }) async {
    final params = <String, dynamic>{};
    if (parentId != null) params['parent_id'] = parentId;
    if (merchantId != null) params['merchant_id'] = merchantId;

    final response = await _client.get('/file/view', queryParameters: params);
    return FileViewResponse.fromJson(response.data ?? {});
  }

  /// 获取文件列表（兼容旧代码）
  Future<List<ChannelFile>> getResources({
    String? zone,
    int? parentId,
    String? search,
    String? type,
    int? netbarId,
  }) async {
    final fullResponse = await getFilesFull(
      parentId: parentId,
      merchantId: netbarId,
    );
    return fullResponse.files;
  }

  Future<ChannelFile> createResource(Map<String, dynamic> data) async {
    // 后端没有直接创建文件记录的接口
    throw UnimplementedError('后端不支持直接创建文件记录');
  }

  Future<ChannelFile> updateResource(int id, Map<String, dynamic> data) async {
    // 后端没有直接更新文件记录的接口，只有重命名
    if (data.containsKey('name')) {
      await _client.post('/file/rename', data: {
        'group_file_id': id,
        'filename': data['name'],
      });
    }
    return ChannelFile(
      id: id,
      name: data['name'] ?? '',
      isDirectory: false,
      isShare: false,
      isHide: false,
      createdAt: '',
      updatedAt: DateTime.now().toIso8601String(),
    );
  }

  Future<void> deleteResource(int id) async {
    await _client.post('/file/destroy', data: {
      'group_file_id': id,
    });
  }

  /// 上传文件
  Future<void> uploadResource({
    required File file,
    String? zone,
    int? parentId,
    String? relativePath,
    int? netbarId,
  }) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
      if (parentId != null) 'folder_id': parentId,
      if (relativePath != null) 'folder': relativePath,
    });

    await _client.post('/file/upload', data: formData);
  }

  /// 秒传文件
  Future<void> instantUpload({
    required String hash,
    required String filename,
    String? folder,
    int? folderId,
  }) async {
    await _client.post('/file/instant', data: {
      'hash': hash,
      'filename': filename,
      if (folder != null) 'folder': folder,
      if (folderId != null) 'folder_id': folderId,
    });
  }

  /// 重命名文件
  Future<void> renameFile(int id, String newName) async {
    await _client.post('/file/rename', data: {
      'group_file_id': id,
      'filename': newName,
    });
  }

  /// 隐藏文件
  Future<void> hideFile(int id) async {
    await _client.post('/file/hide', data: {
      'group_file_id': id,
    });
  }

  /// 取消隐藏文件
  Future<void> unhideFile(int id) async {
    await _client.post('/file/unhide', data: {
      'group_file_id': id,
    });
  }

  /// 解压文件
  Future<void> extractFile(int id) async {
    await _client.post('/file/extract', data: {
      'group_file_id': id,
    });
  }

  /// 获取文件属性
  Future<ChannelFile> getFileAttribute(int id) async {
    final response = await _client.get('/file/attribute', queryParameters: {
      'group_file_id': id,
    });
    final data = response.data ?? {};
    if (data.containsKey('userFile')) {
      return ChannelFile.fromJson(data['userFile']);
    }
    return ChannelFile.fromJson(data);
  }

  /// 共享文件
  Future<void> shareFile(int id) async {
    await _client.post('/file/share', data: {
      'group_file_id': id,
    });
  }

  /// 取消共享文件
  Future<void> unshareFile(int id) async {
    await _client.post('/file/unshare', data: {
      'group_file_id': id,
    });
  }

  /// 获取文件下载URL
  String getDownloadUrl(int id) {
    return '${_client.dio.options.baseUrl}/file/down?group_file_id=$id';
  }

  Future<void> copyResource(int id, int? targetParentId) async {
    // 后端没有复制文件的接口
    throw UnimplementedError('后端不支持复制文件');
  }

  Future<void> moveResource(int id, int? targetParentId) async {
    // 后端没有移动文件的接口
    throw UnimplementedError('后端不支持移动文件');
  }

  // --- Startup Items (适配后端 /api/startup) ---

  /// 获取启动项列表（分页响应）
  Future<StartupPaginatorResponse> getStartupItemsFull({
    int? groupFileId,
    String? keyword,
    String? type,
    int? size,
    int? page,
  }) async {
    final params = <String, dynamic>{};
    if (groupFileId != null) params['group_file_id'] = groupFileId;
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (type != null) params['type'] = type;
    if (size != null) params['size'] = size;
    if (page != null) params['page'] = page;

    final response = await _client.get('/startup', queryParameters: params);
    return StartupPaginatorResponse.fromJson(response.data ?? {});
  }

  /// 获取启动项列表（兼容旧代码）
  Future<List<StartupItem>> getStartupItems({
    String? zone,
    int? netbarId,
  }) async {
    final fullResponse = await getStartupItemsFull();
    return fullResponse.data;
  }

  Future<StartupItem> createStartupItem(Map<String, dynamic> data) async {
    // 后端没有直接创建启动项的接口
    throw UnimplementedError('后端不支持直接创建启动项');
  }

  Future<StartupItem> updateStartupItem(int id, Map<String, dynamic> data) async {
    // 后端没有更新启动项的接口
    throw UnimplementedError('后端不支持更新启动项');
  }

  /// 禁用启动项
  Future<void> disableStartupItem(int id, {int? hours}) async {
    await _client.post('/startup/disable/$id', data: {
      if (hours != null) 'hours': hours,
    });
  }

  /// 启用启动项
  Future<void> enableStartupItem(int id) async {
    await _client.post('/startup/enable/$id');
  }

  /// 删除启动项
  Future<void> deleteStartupItem(int id) async {
    await _client.delete('/startup/$id');
  }
}
