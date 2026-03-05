import 'dart:async';
import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import 'channel_models.dart' show ChannelFile, FileInfo;

// 重新导出 ChannelFile 以保持兼容
export 'channel_models.dart' show ChannelFile, FileInfo;

/// 资源区域类型
enum ResourceZone {
  headquarters('HEADQUARTERS'), // 总部资源
  branch('BRANCH'), // 分公司资源
  public_('PUBLIC'); // 公共资源（本网吧）

  final String value;
  const ResourceZone(this.value);
}

/// 网吧视图选项
class MerchantOption {
  final int id;
  final String name;
  final int terminalCount;
  final List<String> groupNames;

  MerchantOption({
    required this.id,
    required this.name,
    required this.terminalCount,
    required this.groupNames,
  });

  factory MerchantOption.fromJson(Map<String, dynamic> json) {
    final groups = json['groups'] as List? ?? [];
    final groupNames = groups
        .map((g) => (g as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    return MerchantOption(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      terminalCount: json['terminal_count'] ?? 0,
      groupNames: groupNames,
    );
  }
}

/// 文件列表响应（包含文件和网吧列表）
class FileListResponse {
  final List<Resource> files;
  final List<MerchantOption> merchants;

  FileListResponse({
    required this.files,
    required this.merchants,
  });
}

/// 资源模型 - 兼容旧代码，映射到 ChannelFile
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
  final int? uploaderId; // 上传者ID
  final int? groupId; // 分组ID（0=总公司，>0=网吧）
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
    this.uploaderId,
    this.groupId,
    required this.isGlobal,
    this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    // 适配后端 GroupFile 格式
    final file = json['file'] as Map<String, dynamic>?;
    final user = json['user'] as Map<String, dynamic>?;
    final groupId = json['group_id'];

    return Resource(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['full_path'] ?? json['path'] ?? '',
      type: file?['extension'] ?? json['type'] ?? 'unknown',
      isDirectory: json['is_folder'] == true || json['is_folder'] == 1 || json['is_directory'] == true,
      parentId: json['parent_id'],
      size: file?['size'] ?? json['size'] ?? 0,
      zone: groupId == 0 ? 'HEADQUARTERS' : (groupId != null ? 'BRANCH' : (json['zone'] ?? 'PUBLIC')),
      uploader: user?['nickname'] ?? json['uploader'],
      uploaderId: user?['id'] ?? json['user_id'],
      groupId: groupId,
      isGlobal: groupId == 0 || json['is_global'] == true,
      content: json['content'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// 从 ChannelFile 转换
  factory Resource.fromChannelFile(ChannelFile file) {
    return Resource(
      id: file.id,
      name: file.name,
      path: file.path,
      type: file.type,
      isDirectory: file.isDirectory,
      parentId: file.parentId,
      size: file.size,
      zone: file.zone,
      uploader: file.uploader,
      uploaderId: file.uploaderId,
      groupId: file.groupId,
      isGlobal: file.isGlobal,
      content: file.content,
      createdAt: DateTime.tryParse(file.createdAt) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(file.updatedAt) ?? DateTime.now(),
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

/// 资源 API - 适配后端 /api/file/*
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
    if (parentId != null) params['parent_id'] = parentId;
    if (netbarId != null && netbarId != 0) params['merchant_id'] = netbarId;

    final response = await _client.get('/file/view', queryParameters: params);
    final data = response.data;

    // 后端返回 {files: [...], merchants: [...]}
    List<dynamic> list = [];
    if (data is Map<String, dynamic> && data.containsKey('files')) {
      list = data['files'] as List? ?? [];
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => Resource.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取资源列表和网吧列表
  Future<FileListResponse> getAllWithMerchants({
    int? parentId,
    int? merchantId,
  }) async {
    final params = <String, dynamic>{};
    if (parentId != null) params['parent_id'] = parentId;
    if (merchantId != null && merchantId != 0) params['merchant_id'] = merchantId;

    final response = await _client.get('/file/view', queryParameters: params);
    final data = response.data;

    List<Resource> files = [];
    List<MerchantOption> merchants = [];

    if (data is Map<String, dynamic>) {
      // 解析文件列表
      final fileList = data['files'] as List? ?? [];
      files = fileList.map((e) => Resource.fromJson(e as Map<String, dynamic>)).toList();

      // 解析网吧列表
      final merchantList = data['merchants'] as List? ?? [];
      merchants = merchantList.map((e) => MerchantOption.fromJson(e as Map<String, dynamic>)).toList();
    }

    return FileListResponse(files: files, merchants: merchants);
  }

  /// 获取单个资源
  Future<Resource> getById(int id) async {
    final response = await _client.get('/file/attribute', queryParameters: {
      'group_file_id': id,
    });
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('userFile')) {
      return Resource.fromJson(data['userFile']);
    }
    return Resource.fromJson(data ?? {});
  }

  /// 获取资源内容（文本文件）- 后端可能不支持
  Future<String> getContent(int id) async {
    throw UnimplementedError('后端不支持获取文件内容');
  }

  /// 下载二进制内容
  Future<List<int>> downloadBytes(
    int id, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final response = await _client.dio.get<List<int>>(
      '/file/down',
      queryParameters: {'group_file_id': id},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
    );
    return response.data ?? const [];
  }

  /// 限量下载二进制内容（最多 maxBytes 字节）
  /// 使用流式下载，超过限制时自动停止，避免大文件占用内存
  Future<List<int>> downloadBytesLimited(int id, int maxBytes) async {
    final cancelToken = CancelToken();
    final List<int> buffer = [];

    try {
      final response = await _client.dio.get<ResponseBody>(
        '/file/down',
        queryParameters: {'group_file_id': id},
        options: Options(responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );

      final stream = response.data?.stream;
      if (stream == null) return const [];

      await for (final chunk in stream) {
        buffer.addAll(chunk);
        // 超过限制时停止下载
        if (buffer.length > maxBytes) {
          cancelToken.cancel('文件过大，停止下载');
          break;
        }
      }
    } on DioException catch (e) {
      // 如果是我们主动取消的，不抛异常
      if (e.type == DioExceptionType.cancel) {
        // 正常返回已下载的部分
      } else {
        rethrow;
      }
    }

    return buffer;
  }

  /// 下载文件到本地路径 (流式下载)
  Future<void> downloadToFile(
    int id,
    String savePath, {
    ProgressCallback? onReceiveProgress,
  }) async {
    await _client.dio.download(
      '/file/down',
      savePath,
      queryParameters: {'group_file_id': id},
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 获取下载链接
  String getDownloadUrl(int id) {
    return '${_client.dio.options.baseUrl}/file/down?group_file_id=$id';
  }

  /// 创建文件夹 - 后端可能不直接支持
  Future<Resource> create({
    required String name,
    required String type,
    required bool isDirectory,
    int? parentId,
    required String zone,
    int? netbarId,
    String? content,
  }) async {
    throw UnimplementedError('后端不支持直接创建资源记录，请使用上传接口');
  }

  /// 更新资源（重命名）
  Future<Resource> update(
    int id, {
    String? name,
    int? parentId,
    String? content,
  }) async {
    if (name != null) {
      await _client.post('/file/rename', data: {
        'group_file_id': id,
        'filename': name,
      });
    }
    // 返回更新后的资源（后端可能不返回，构造一个临时对象）
    return Resource(
      id: id,
      name: name ?? '',
      path: '',
      type: '',
      isDirectory: false,
      size: 0,
      zone: 'PUBLIC',
      isGlobal: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// 删除资源
  Future<void> delete(int id) async {
    await _client.post('/file/destroy', data: {
      'group_file_id': id,
    });
  }

  /// 复制资源 - 后端不支持
  Future<Resource> copy(
    int id,
    int? targetParentId, {
    int? netbarId,
    String? zone,
  }) async {
    throw UnimplementedError('后端不支持复制资源');
  }

  /// 移动资源
  Future<void> move(int id, int? targetParentId) async {
    final data = <String, dynamic>{
      'group_file_id': id,
    };
    if (targetParentId != null) {
      data['dest_group_file_id'] = targetParentId;
    }
    await _client.post('/file/move', data: FormData.fromMap(data));
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
      if (parentId != null) 'folder_id': parentId,
      if (relativePath != null) 'folder': relativePath,
    });

    final response = await _client.dio.post(
      '/file/upload',
      data: formData,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );

    // 后端返回格式可能不同
    return response.data;
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

  /// 隐藏资源
  Future<void> hide(int id) async {
    await _client.post('/file/hide', data: {'group_file_id': id});
  }

  /// 取消隐藏资源
  Future<void> unhide(int id) async {
    await _client.post('/file/unhide', data: {'group_file_id': id});
  }

  /// 解压文件
  Future<void> extract(int id) async {
    await _client.post('/file/extract', data: {'group_file_id': id});
  }

  /// 共享文件
  Future<void> share(int id) async {
    await _client.post('/file/share', data: {'group_file_id': id});
  }

  /// 取消共享
  Future<void> unshare(int id) async {
    await _client.post('/file/unshare', data: {'group_file_id': id});
  }

  /// 获取共享文件列表（公共文件区）
  /// 根目录调用 /file/shared，子目录调用 /file/view?parent_id=xxx
  Future<List<Resource>> getSharedFiles({int? parentId}) async {
    if (parentId != null) {
      // 子目录：用 /file/view
      final response = await _client.get('/file/view', queryParameters: {
        'parent_id': parentId,
      });
      final data = response.data;
      List<dynamic> list = [];
      if (data is Map<String, dynamic> && data.containsKey('files')) {
        list = data['files'] as List? ?? [];
      } else if (data is List) {
        list = data;
      }
      return list.map((e) => Resource.fromJson(e as Map<String, dynamic>)).toList();
    }

    // 根目录：用 /file/shared
    final response = await _client.get('/file/shared');
    final data = response.data;

    // 后端返回 { paginator: { data: [...] } }
    List<dynamic> list = [];
    if (data is Map<String, dynamic>) {
      if (data.containsKey('paginator')) {
        final paginator = data['paginator'] as Map<String, dynamic>?;
        list = paginator?['data'] as List? ?? [];
      } else if (data.containsKey('files')) {
        list = data['files'] as List? ?? [];
      }
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => _parseSharedFile(e as Map<String, dynamic>)).toList();
  }

  /// 解析共享文件格式
  Resource _parseSharedFile(Map<String, dynamic> json) {
    // 共享文件格式: { id, group_file_id, user_id, group_file: {...}, user: {...} }
    final groupFile = json['group_file'] as Map<String, dynamic>? ?? {};
    final user = json['user'] as Map<String, dynamic>?;

    return Resource(
      id: json['group_file_id'] ?? json['id'] ?? 0,
      name: groupFile['name'] ?? json['name'] ?? '',
      path: '',
      type: '',
      isDirectory: groupFile['is_folder'] == true || groupFile['is_folder'] == 1,
      parentId: null,
      size: 0,
      zone: 'SHARED',
      uploader: user?['nickname'],
      isGlobal: true,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// 搜索资源 - 后端可能不支持
  Future<List<Resource>> search({
    required String keyword,
    String? zone,
    int? netbarId,
    int? parentId,
  }) async {
    // 后端没有专门的搜索接口，使用列表接口带搜索参数
    return getAll(
      zone: zone,
      netbarId: netbarId,
      parentId: parentId,
      search: keyword,
    );
  }
}
