import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';

/// 资源区域类型
enum ResourceZone {
  headquarters('HEADQUARTERS'), // 总部资源
  branch('BRANCH'), // 分公司资源
  public_('PUBLIC'); // 公共资源（本网吧）

  final String value;
  const ResourceZone(this.value);
}

/// 资源模型
class Resource {
  final int id;
  final String name;
  final String path;
  final String type;
  final bool isDirectory;
  final int? parentId;
  final int size;
  final String zone;
  final String? uploader;
  final bool isGlobal;
  final String? content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Resource({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.isDirectory,
    this.parentId,
    required this.size,
    required this.zone,
    this.uploader,
    required this.isGlobal,
    this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      type: json['type'] ?? 'unknown',
      isDirectory: json['is_directory'] ?? false,
      parentId: json['parent_id'],
      size: json['size'] ?? 0,
      zone: json['zone'] ?? 'PUBLIC',
      uploader: json['uploader'],
      isGlobal: json['is_global'] ?? false,
      content: json['content'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// 格式化文件大小
  String get formattedSize {
    if (isDirectory) return '-';
    if (size == 0) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB'];
    final i = (size > 0) ? (size.bitLength - 1) ~/ 10 : 0;
    final clampedI = i.clamp(0, sizes.length - 1);
    final value = size / (1 << (clampedI * 10));
    return '${value.toStringAsFixed(1)} ${sizes[clampedI]}';
  }

  /// 格式化更新时间
  String get formattedUpdateTime {
    return '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} '
        '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';
  }
}

/// 资源 API
class ResourceApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取资源列表
  Future<List<Resource>> getAll({
    String? zone,
    int? parentId,
    String? search,
    String? type,
    int? netbarId,
  }) async {
    final params = <String, dynamic>{};
    if (zone != null) params['zone'] = zone;
    if (parentId != null) params['parent_id'] = parentId.toString();
    if (search != null) params['search'] = search;
    if (type != null) params['type'] = type;
    if (netbarId != null) params['netbar_id'] = netbarId.toString();

    final response = await _client.get('/resources', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => Resource.fromJson(e)).toList();
  }

  /// 获取单个资源
  Future<Resource> getById(int id) async {
    final response = await _client.get('/resources/$id');
    return Resource.fromJson(response.data);
  }

  /// 获取资源内容（文本文件）
  Future<String> getContent(int id) async {
    final response = await _client.get(
      '/resources/$id/content',
      options: Options(responseType: ResponseType.plain),
    );
    return response.data.toString();
  }

  /// 下载二进制内容（用于部分上传文件 content 接口不可用时兜底）
  Future<List<int>> downloadBytes(int id, {ProgressCallback? onReceiveProgress}) async {
    final response = await _client.dio.get<List<int>>(
      '/resources/$id/download',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
    );
    return response.data ?? const [];
  }

  /// 下载目录为zip文件
  Future<List<int>> downloadDirectoryZip(int id, {ProgressCallback? onReceiveProgress}) async {
    final response = await _client.dio.get<List<int>>(
      '/resources/$id/download-dir',
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
    );
    return response.data ?? const [];
  }

  /// 部分下载，优先用于大文件预览，依赖服务端对 Range 头的支持
  Future<List<int>> downloadBytesPartial(
    int id, {
    int start = 0,
    int? endExclusive,
  }) async {
    final headers = <String, dynamic>{};
    if (endExclusive != null) {
      headers['Range'] = 'bytes=$start-${endExclusive - 1}';
    } else if (start > 0) {
      headers['Range'] = 'bytes=$start-';
    }

    final response = await _client.dio.get<List<int>>(
      '/resources/$id/download',
      options: Options(
        responseType: ResponseType.bytes,
        headers: headers,
      ),
    );
    return response.data ?? const [];
  }

  /// 流式获取前 N 字节，用于大文件预览（不依赖 Range 支持）
  Future<List<int>> downloadBytesLimited(int id, int limit) async {
    final response = await _client.dio.get<ResponseBody>(
      '/resources/$id/download',
      options: Options(responseType: ResponseType.stream),
    );

    final body = response.data;
    if (body == null) return const [];

    final buffer = <int>[];
    await for (final chunk in body.stream) {
      buffer.addAll(chunk);
      if (buffer.length >= limit) break;
    }

    if (buffer.length > limit) {
      return buffer.sublist(0, limit);
    }
    return buffer;
  }

  /// 下载文件到本地路径 (流式下载)
  Future<void> downloadToFile(int id, String savePath, {ProgressCallback? onReceiveProgress}) async {
    await _client.dio.download(
      '/resources/$id/download',
      savePath,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 获取下载链接 (用于 Web 或外部调用)
  String getDownloadUrl(int id) {
    return '${_client.dio.options.baseUrl}/resources/$id/download';
  }

  /// 创建资源
  Future<Resource> create({
    required String name,
    required String type,
    required bool isDirectory,
    int? parentId,
    required String zone,
    int? netbarId,
    String? content,
  }) async {
    final response = await _client.post('/resources', data: {
      'name': name,
      'type': type,
      'is_directory': isDirectory,
      'parent_id': parentId,
      'zone': zone,
      'netbar_id': netbarId,
      'content': content,
    });
    return Resource.fromJson(response.data);
  }

  /// 更新资源
  Future<Resource> update(int id, {
    String? name,
    int? parentId,
    String? content,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (parentId != null) data['parent_id'] = parentId;
    if (content != null) data['content'] = content;

    final response = await _client.put('/resources/$id', data: data);
    return Resource.fromJson(response.data);
  }

  /// 删除资源
  Future<void> delete(int id) async {
    await _client.delete('/resources/$id');
  }

  /// 复制资源
  Future<Resource> copy(
    int id,
    int? targetParentId, {
    int? netbarId,
    String? zone,
  }) async {
    final response = await _client.post('/resources/$id/copy', data: {
      'target_parent_id': targetParentId,
      if (netbarId != null) 'netbar_id': netbarId,
      if (zone != null) 'zone': zone,
    });
    return Resource.fromJson(response.data);
  }

  /// 移动资源
  Future<Resource> move(
    int id,
    int? targetParentId, {
    int? netbarId,
    String? zone,
  }) async {
    final response = await _client.put('/resources/$id/move', data: {
      'target_parent_id': targetParentId,
      if (netbarId != null) 'netbar_id': netbarId,
      if (zone != null) 'zone': zone,
    });
    return Resource.fromJson(response.data);
  }

  /// 上传文件（multipart）
  Future<dynamic> uploadFile({
    required String name,
    required List<int> bytes,
    String? zone,
    int? parentId,
    int? netbarId,
    String? relativePath,
    bool extractZip = false,
    ProgressCallback? onSendProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: name),
      if (zone != null) 'zone': zone,
      if (parentId != null) 'parent_id': parentId,
      if (netbarId != null) 'netbar_id': netbarId,
      if (relativePath != null) 'relative_path': relativePath,
      if (extractZip) 'extract_zip': 'true',
    });
    final response = await _client.dio.post(
      '/resources/upload',
      data: formData,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    // 如果是解压ZIP，返回的是多个资源
    if (extractZip && response.data is Map && response.data['resources'] != null) {
      return response.data;
    }
    return Resource.fromJson(response.data);
  }

  /// 搜索资源（支持递归搜索子目录）
  Future<List<Resource>> search({
    required String keyword,
    String? zone,
    int? netbarId,
    int? parentId,
  }) async {
    final params = <String, dynamic>{
      'keyword': keyword,
    };
    if (zone != null) params['zone'] = zone;
    if (netbarId != null) params['netbar_id'] = netbarId.toString();
    if (parentId != null) params['parent_id'] = parentId.toString();

    final response = await _client.get('/resources/search', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => Resource.fromJson(e)).toList();
  }
}
