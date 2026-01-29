import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/token_store.dart';
import 'desktop_model.dart';

/// 桌面布局API
class DesktopApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取布局列表
  Future<List<DesktopLayout>> getLayouts({
    int? netbarId,
    int? groupId,
    String? resolution,
  }) async {
    final params = <String, dynamic>{};
    if (netbarId != null) params['merchant_id'] = netbarId;
    if (groupId != null) params['group_id'] = groupId;
    if (resolution != null) params['resolution'] = resolution;

    final res = await _client.get('/layout', queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data is Map<String, dynamic> && data.containsKey('layouts')) {
      list = data['layouts'] as List? ?? [];
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => DesktopLayout.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 创建布局
  Future<DesktopLayout?> createLayout(DesktopLayout layout, {Uint8List? backgroundFile}) async {
    return _saveLayout(layout, url: '/layout', backgroundFile: backgroundFile);
  }

  /// 更新布局
  Future<DesktopLayout?> updateLayout(DesktopLayout layout, {Uint8List? backgroundFile}) async {
    if (layout.id == null) {
      return createLayout(layout, backgroundFile: backgroundFile);
    }
    return _saveLayout(layout, url: '/layout/${layout.id}', backgroundFile: backgroundFile);
  }

  /// 保存布局 - 支持上传背景图片
  Future<DesktopLayout?> _saveLayout(DesktopLayout layout, {required String url, Uint8List? backgroundFile}) async {
    dynamic data;

    if (backgroundFile != null) {
      // 有背景图片时使用 FormData
      data = FormData.fromMap({
        'resolution': layout.resolution,
        'configuration': layout.configurationJson,
        'file': MultipartFile.fromBytes(backgroundFile, filename: 'background.png'),
        if (layout.groupId != null) 'group_id': layout.groupId.toString(),
        if (layout.netbarId != null) 'merchant_id': layout.netbarId.toString(),
        if (layout.forceUpdate) 'force_update': '1',
      });
    } else {
      // 无背景图片时使用 JSON
      data = <String, dynamic>{
        'resolution': layout.resolution,
        'configuration': layout.configurationJson,
        if (layout.groupId != null) 'group_id': layout.groupId,
        if (layout.netbarId != null) 'merchant_id': layout.netbarId.toString(),
        if (layout.forceUpdate) 'force_update': 1,
      };
    }

    final res = await _client.post(url, data: data);
    if (res.data is Map<String, dynamic>) {
      return DesktopLayout.fromJson(res.data as Map<String, dynamic>);
    }
    return null;
  }

  /// 删除布局
  Future<void> deleteLayout(int id) async {
    await _client.delete('/layout/$id');
  }

  /// 强制更新桌面
  Future<void> forceUpdateDesktop({required int netbarId}) async {
    await _client.post('/socket/layout', data: {'merchant_id': netbarId});
  }

  /// 获取背景图片URL
  String getBackgroundUrl(String? fileUrl) {
    if (fileUrl == null || fileUrl.isEmpty) return '';
    if (fileUrl.startsWith('http://') || fileUrl.startsWith('https://')) {
      return fileUrl;
    }
    // 去掉 baseUrl 末尾的斜杠
    var base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    // 处理 fileUrl，如果以 /api 开头且 baseUrl 已包含 /api，则去掉重复的 /api
    var path = fileUrl;
    if (base.endsWith('/api') && path.startsWith('/api/')) {
      path = path.substring(4); // 去掉 "/api"
    }
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return '$base$path';
  }

  /// 获取带认证的请求头
  static Map<String, String> getAuthHeaders() {
    final token = TokenStore.getToken();
    if (token == null) return {};
    return {'Authorization': 'Bearer $token'};
  }
}

/// 图标API
class IconApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取图标列表
  Future<List<DesktopIcon>> getIcons({
    int? groupId,
    int? netbarId,
  }) async {
    final params = <String, dynamic>{};
    if (groupId != null) params['group_id'] = groupId;
    if (netbarId != null) params['merchant_id'] = netbarId;

    final res = await _client.get('/icon', queryParameters: params);
    final data = res.data;

    List<dynamic> list = [];
    if (data is Map<String, dynamic> && data.containsKey('icons')) {
      list = data['icons'] as List? ?? [];
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => _parseIconFromApi(e as Map<String, dynamic>)).toList();
  }

  /// 解析API返回的图标数据
  DesktopIcon _parseIconFromApi(Map<String, dynamic> json) {
    final type = IconTypeExtension.fromInt(json['type'] as int?);
    final filesArr = json['files'] as List? ?? [];
    final files = filesArr
        .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // 获取图标URL
    final fileId = json['file_id']?.toString();
    String? iconUrl;
    if (files.isNotEmpty && fileId != null) {
      final matched = files.firstWhere(
        (f) => f.id == fileId,
        orElse: () => files.first,
      );
      iconUrl = matched.url;
    }
    iconUrl ??= json['url']?.toString() ?? json['file_url']?.toString();

    // 调试：打印图标信息
    final iconName = json['name']?.toString() ?? '未知';
    debugPrint('图标名称：$iconName，图片地址：$iconUrl，file_id：$fileId，files数量：${files.length}');
    if (files.isNotEmpty) {
      for (var i = 0; i < files.length; i++) {
        debugPrint('  files[$i]: id=${files[i].id}, url=${files[i].url}');
      }
    }

    return DesktopIcon(
      id: json['id']?.toString() ?? '',
      label: json['name']?.toString() ?? '',
      iconUrl: iconUrl,
      positions: {},
      config: DesktopIconConfig(
        type: type,
        path: json['path']?.toString() ?? '',
        parameter: json['parameter']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        iconUrl: iconUrl,
        groupFileId: json['group_file_id']?.toString(),
        fileId: fileId,
        files: files,
        hash: json['hash']?.toString(),
      ),
    );
  }

  /// 创建/更新图标
  Future<Map<String, dynamic>?> saveIcon({
    String? id,
    required String groupFileId,
    String? fileId,
    Uint8List? iconFile,
    String? iconFileName,
    required IconType type,
    required String name,
    required String parameter,
    int? groupId,
    int? netbarId,
  }) async {
    final formData = FormData.fromMap({
      'group_file_id': groupFileId,
      if (fileId != null && fileId.isNotEmpty) 'file_id': fileId,
      if (iconFile != null)
        'file': MultipartFile.fromBytes(iconFile, filename: iconFileName ?? 'icon.png'),
      'type': type.intValue.toString(),
      'name': name,
      'parameter': parameter,
      if (groupId != null) 'group_id': groupId.toString(),
      if (netbarId != null) 'merchant_id': netbarId.toString(),
    });

    final url = id != null ? '/icon/$id' : '/icon';
    final res = await _client.post(url, data: formData);
    return res.data as Map<String, dynamic>?;
  }

  /// 删除图标
  Future<void> deleteIcon(String id) async {
    await _client.delete('/icon/$id');
  }

  /// 删除图标文件
  Future<void> deleteIconFile(String groupFileId, String fileId) async {
    await _client.delete('/icon/$groupFileId/$fileId');
  }

  /// 根据group_file_id获取图标
  Future<String?> getFileIcon(String groupFileId) async {
    final res = await _client.get('/file/icon', queryParameters: {
      'group_file_id': groupFileId,
    });
    final data = res.data;
    if (data is Map<String, dynamic>) {
      return data['icon']?.toString();
    }
    return null;
  }
}

/// 远程截图API
class ScreenshotApi {
  /// 请求远程截图
  Future<ScreenshotResult> requestScreenshot({
    required String domain,
    required String seatId,
  }) async {
    if (domain.isEmpty) {
      return ScreenshotResult.error('缺少网吧域名');
    }
    if (seatId.isEmpty) {
      return ScreenshotResult.error('缺少机号');
    }

    // 规范化域名
    String normalizedDomain = domain.trim();
    if (!normalizedDomain.startsWith('http://') &&
        !normalizedDomain.startsWith('https://')) {
      // 如果包含非标准端口，使用 HTTP；否则使用 HTTPS
      if (normalizedDomain.contains(':') && !normalizedDomain.contains(':443')) {
        normalizedDomain = 'http://$normalizedDomain';
      } else {
        normalizedDomain = 'https://$normalizedDomain';
      }
    }
    normalizedDomain = normalizedDomain.replaceAll(RegExp(r'/$'), '');

    final url = '$normalizedDomain/api/task?seat=${Uri.encodeComponent(seatId)}';
    final token = TokenStore.getToken();

    try {
      final dio = Dio();
      final response = await dio.post(
        url,
        data: {'fun': 'Screenshot', 'data': {}},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          responseType: ResponseType.bytes,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode != 200) {
        return ScreenshotResult.error('请求失败: ${response.statusCode}');
      }

      final contentType = response.headers.value('content-type') ?? '';

      // 如果是JSON响应
      if (contentType.contains('application/json')) {
        final jsonStr = String.fromCharCodes(response.data as List<int>);
        final json = await Future.value(_parseJson(jsonStr));
        if (json == null) {
          return ScreenshotResult.error('解析响应失败');
        }
        if (json['code'] == 1) {
          return ScreenshotResult.error(json['message'] ?? '截图失败');
        }

        final payload = json['data'] ?? json['result'] ?? json;
        final base64 = payload['base64'] ??
            payload['image_base64'] ??
            payload['img_base64'] ??
            payload['image'] ??
            payload['img'];
        final imageUrl = payload['url'] ??
            payload['file_url'] ??
            payload['fileUrl'] ??
            payload['image_url'];
        final width = payload['width'] ?? payload['w'];
        final height = payload['height'] ?? payload['h'];

        if (base64 != null) {
          return ScreenshotResult.base64(
            base64.toString(),
            width: width as int?,
            height: height as int?,
          );
        }
        if (imageUrl != null) {
          return ScreenshotResult.url(
            _resolveUrl(normalizedDomain, imageUrl.toString()),
            width: width as int?,
            height: height as int?,
          );
        }

        return ScreenshotResult.error('截图任务已触发，但接口未返回图片数据');
      }

      // 二进制图片流
      return ScreenshotResult.bytes(Uint8List.fromList(response.data as List<int>));
    } catch (e) {
      return ScreenshotResult.error('截图请求异常: $e');
    }
  }

  Map<String, dynamic>? _parseJson(String str) {
    try {
      return Map<String, dynamic>.from(
        (str.isNotEmpty) ? _decodeJson(str) : {},
      );
    } catch (_) {
      return null;
    }
  }

  dynamic _decodeJson(String str) {
    // ignore: avoid_dynamic_calls
    return (str.isNotEmpty) ? Uri.decodeComponent(str).trim().isNotEmpty
        ? _tryDecode(str)
        : null : null;
  }

  dynamic _tryDecode(String str) {
    try {
      return jsonDecode(str);
    } catch (_) {
      return null;
    }
  }

  String _resolveUrl(String domain, String candidate) {
    if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
      return candidate;
    }
    if (candidate.startsWith('/')) {
      return '$domain$candidate';
    }
    return '$domain/$candidate';
  }
}

/// 截图结果
class ScreenshotResult {
  final ScreenshotResultType type;
  final Uint8List? bytes;
  final String? base64Data;
  final String? url;
  final String? error;
  final int? width;
  final int? height;

  ScreenshotResult._({
    required this.type,
    this.bytes,
    this.base64Data,
    this.url,
    this.error,
    this.width,
    this.height,
  });

  factory ScreenshotResult.bytes(Uint8List data) {
    return ScreenshotResult._(type: ScreenshotResultType.bytes, bytes: data);
  }

  factory ScreenshotResult.base64(String data, {int? width, int? height}) {
    return ScreenshotResult._(
      type: ScreenshotResultType.base64,
      base64Data: data,
      width: width,
      height: height,
    );
  }

  factory ScreenshotResult.url(String url, {int? width, int? height}) {
    return ScreenshotResult._(
      type: ScreenshotResultType.url,
      url: url,
      width: width,
      height: height,
    );
  }

  factory ScreenshotResult.error(String message) {
    return ScreenshotResult._(type: ScreenshotResultType.error, error: message);
  }

  bool get isSuccess => type != ScreenshotResultType.error;
}

enum ScreenshotResultType { bytes, base64, url, error }

/// 文件API - 使用 http://net.hudd.cc:888/api/file/view 接口
class FileApi {
  static const String _baseUrl = 'http://net.hudd.cc:888/api/file/view';

  /// 处理响应，检查 code 是否为 401
  List<dynamic> _parseResponse(dynamic data) {
    if (data is Map<String, dynamic>) {
      final code = data['code'];

      // 处理 401 未授权
      if (code == 401) {
        TokenStore.clearAuth();
        ApiClient.onUnauthorized?.call();
        return [];
      }

      // 响应格式: { "code": 0, "data": { "files": [...] } }
      final innerData = data['data'];
      if (innerData is Map<String, dynamic>) {
        return innerData['files'] as List? ?? [];
      } else if (innerData is List) {
        return innerData;
      } else {
        return data['files'] as List? ?? data['list'] as List? ?? [];
      }
    } else if (data is List) {
      return data;
    }
    return [];
  }

  /// 获取文件列表
  Future<List<ServerFile>> getFiles({
    int? parentId,
    String? keyword,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (parentId != null) params['parent_id'] = parentId;
      if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;

      final token = TokenStore.getToken();
      final dio = Dio();
      final res = await dio.get(
        _baseUrl,
        queryParameters: params,
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      final list = _parseResponse(res.data);
      return list.map((e) => ServerFile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('获取文件列表失败: $e');
      return [];
    }
  }

  /// 根据ID获取文件
  Future<ServerFile?> getFileById(int id) async {
    try {
      final token = TokenStore.getToken();
      final dio = Dio();
      final res = await dio.get(
        _baseUrl,
        queryParameters: {'id': id},
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );

      final list = _parseResponse(res.data);
      if (list.isNotEmpty) {
        return ServerFile.fromJson(list.first as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      debugPrint('获取文件失败: $e');
      return null;
    }
  }
}

/// 服务器文件
class ServerFile {
  final int id;
  final String name;
  final String? path;
  final String? fullPath;
  final bool isFolder;
  final bool isHide;
  final bool isStartup;
  final String? size;
  final String? version;
  final String? modified;
  final int? groupId;
  final String? groupName;
  final int? parentId;
  final int? userId;
  final String? userName;

  ServerFile({
    required this.id,
    required this.name,
    this.path,
    this.fullPath,
    this.isFolder = false,
    this.isHide = false,
    this.isStartup = false,
    this.size,
    this.version,
    this.modified,
    this.groupId,
    this.groupName,
    this.parentId,
    this.userId,
    this.userName,
  });

  factory ServerFile.fromJson(Map<String, dynamic> json) {
    // 解析嵌套的 group 对象
    String? groupName;
    int? groupId = json['group_id'] as int?;
    if (json['group'] is Map<String, dynamic>) {
      final group = json['group'] as Map<String, dynamic>;
      groupName = group['name']?.toString();
      groupId ??= group['id'] as int?;
    }

    // 解析嵌套的 user 对象
    String? userName;
    int? userId = json['user_id'] as int?;
    if (json['user'] is Map<String, dynamic>) {
      final user = json['user'] as Map<String, dynamic>;
      userName = user['nickname']?.toString() ?? user['name']?.toString();
      userId ??= user['id'] as int?;
    }

    return ServerFile(
      id: json['id'] as int? ?? 0,
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString(),
      fullPath: json['full_path']?.toString(),
      isFolder: json['is_folder'] == true || json['is_folder'] == 1,
      isHide: json['is_hide'] == true || json['is_hide'] == 1,
      isStartup: json['is_startup'] == true || json['is_startup'] == 1,
      size: json['size']?.toString(),
      version: json['version']?.toString(),
      modified: json['modified']?.toString() ?? json['updated_at']?.toString(),
      groupId: groupId,
      groupName: groupName,
      parentId: json['parent_id'] as int?,
      userId: userId,
      userName: userName,
    );
  }
}

