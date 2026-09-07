import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'game_library_api.dart' show extractApiError;

/// 镜像管理 HTTP API —— game_library 无盘系接口（对齐 web src/api/imageManage.js）
///
/// 与 GameLibraryApi 同一套约定：独立 Dio、无鉴权、https://<subdomain_full> 直连。
/// 三个接口的形态差异（易踩）：
/// - image_info / get_clientcfg：platform 可选，不传则后端遍历无盘白名单，
///   响应按 { "<platform>": {...} } 封装
/// - set_clientcfg：platform 必填（写操作不允许遍历，disk_id/config_id 是平台专属 id）
class ImageManageApi {
  ImageManageApi(this.subdomainFull);

  /// 网吧 subdomain_full，例如 "xxxx.frps.wwls.net"
  final String subdomainFull;

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {'Accept': 'application/json'},
  ));

  String _buildUrl(String path, [Map<String, dynamic>? query]) {
    var url = 'https://$subdomainFull$path';
    if (query != null && query.isNotEmpty) {
      final pairs = <String>[];
      query.forEach((k, v) {
        if (v == null) return;
        final s = v.toString();
        if (s.isEmpty) return;
        pairs.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(s)}');
      });
      if (pairs.isNotEmpty) url += '?${pairs.join('&')}';
    }
    return url;
  }

  /// 读接口错误体可能是 text/plain 的 Go 调用链串，也可能是 JSON —— 原样取原文，
  /// 人话翻译由 UI 层调 humanizeCfgError。
  ///
  /// 唯一的例外是网关错误页：网吧服务端没起来时 frp / nginx 会返回一整页 HTML，
  /// 那不是后端文案，透出去会被原样渲染成一屏尖括号，降级成 `HTTP <status>`
  /// （对齐 toolboxPage api/gameLibrary.js:32-48 的 extractApiError）。
  static String? _dioError(DioException e) {
    final status = e.response?.statusCode ?? 0;
    return extractApiError(e.response?.data, status, fallbackMessage: e.message) ??
        e.message;
  }

  /// GET /game_library/image_info —— 平台镜像列表 + 配置节/配置点树。
  /// platform 省略则遍历无盘白名单；响应体量小（镜像/节树），主线程解析即可
  Future<CfgFetchResult> getImageInfo({String? platform}) async {
    final url = _buildUrl('/game_library/image_info',
        platform != null ? {'platform': platform} : null);
    try {
      final resp = await _dio.get<dynamic>(url);
      final status = resp.statusCode ?? 0;
      final data = resp.data;
      return CfgFetchResult(
        ok: status >= 200 && status < 300,
        status: status,
        data: data is Map ? data.cast<String, dynamic>() : null,
      );
    } on DioException catch (e) {
      return CfgFetchResult(
        ok: false,
        status: e.response?.statusCode ?? 0,
        error: _dioError(e),
      );
    }
  }

  /// GET /game_library/get_clientcfg —— 客户机 4 行镜像槽当前配置。
  /// seat 省略返全表；千台网吧全表响应大，ResponseType.plain + compute 在
  /// worker isolate 解析（仿 GameLibraryApi.getGameLists）
  Future<CfgFetchResult> getClientCfg({String? platform, String? seat}) async {
    final url =
        _buildUrl('/game_library/get_clientcfg', {'platform': platform, 'seat': seat});
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final status = resp.statusCode ?? 0;
      final raw = resp.data;
      final data = (raw == null || raw.isEmpty)
          ? null
          : await compute(_decodeJsonMap, raw);
      return CfgFetchResult(
        ok: status >= 200 && status < 300,
        status: status,
        data: data,
      );
    } on DioException catch (e) {
      return CfgFetchResult(
        ok: false,
        status: e.response?.statusCode ?? 0,
        error: _dioError(e),
      );
    } on FormatException catch (e) {
      // 2xx 但响应不是合法 JSON：按失败处理，避免上层拿到 null 误判成「无客户机」
      return CfgFetchResult(ok: false, status: 0, error: '响应解析失败: ${e.message}');
    }
  }

  /// POST /game_library/set_clientcfg —— 修改指定 seat 的 4 行镜像槽。
  /// platform 必填；body 用 buildSetClientCfgBody 构造（空对象也发）。
  /// 2xx 即成功，不解析响应体；错误体是 text/plain 的 Go 调用链串，原样带回。
  /// 不复用 _opWrite/GameOpResult（评审 M4）：那套解析的是 {results:{gid:...}} 结构，
  /// 与本接口的纯文本错误协议不匹配
  Future<CfgOpResult> setClientCfg({
    required String platform,
    required String seat,
    required Map<String, dynamic> body,
  }) async {
    final url = _buildUrl(
        '/game_library/set_clientcfg', {'platform': platform, 'seat': seat});
    try {
      final resp = await _dio.post<String>(
        url,
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.plain,
        ),
      );
      final status = resp.statusCode ?? 0;
      return CfgOpResult(ok: status >= 200 && status < 300, status: status);
    } on DioException catch (e) {
      return CfgOpResult(
        ok: false,
        status: e.response?.statusCode ?? 0,
        error: _dioError(e),
      );
    }
  }
}

/// compute 入口必须是顶层函数
Map<String, dynamic>? _decodeJsonMap(String raw) {
  final decoded = jsonDecode(raw);
  return decoded is Map ? decoded.cast<String, dynamic>() : null;
}

/// 读接口结果（对齐 web callGameLibApi 的 { ok, status, data, error }）
class CfgFetchResult {
  final bool ok;
  final int status;
  final Map<String, dynamic>? data;
  final String? error;
  const CfgFetchResult({
    required this.ok,
    required this.status,
    this.data,
    this.error,
  });
}

/// set_clientcfg 结果；error 是后端原始串，人话翻译由 UI 层调 humanizeCfgError
class CfgOpResult {
  final bool ok;
  final int status;
  final String? error;
  const CfgOpResult({required this.ok, required this.status, this.error});
}
