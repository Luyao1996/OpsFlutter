import 'dart:convert';

import 'package:dio/dio.dart';

/// iTunes Lookup API 返回的 App Store 版本信息（仅取需要的字段）。
class AppStoreInfo {
  /// App Store 上架的版本号（CFBundleShortVersionString，如 "1.0.1"），用于比较。
  final String version;

  /// App Store 完整网页直链（apps.apple.com/...），跳转首选。
  final String trackViewUrl;

  /// 数字型 App Store ID，用于拼 fallback 链接。
  final int? trackId;

  /// 本次版本更新说明（可空）。
  final String releaseNotes;

  /// 该版本要求的最低 iOS 系统版本（可空）。
  final String minimumOsVersion;

  AppStoreInfo({
    required this.version,
    required this.trackViewUrl,
    this.trackId,
    this.releaseNotes = '',
    this.minimumOsVersion = '',
  });
}

/// 查 App Store 上某 app 的最新版本（Apple iTunes Lookup API，免鉴权）。
///
/// 仅 iOS 使用：iOS app 不能自己下载安装（Apple 2.5.2），只能查版本号后跳转 App Store。
/// 查询失败 / 查不到 / 超时 / 限流(403) 一律返回 null，由调用方静默处理。
class AppStoreLookupApi {
  final Dio _dio;

  AppStoreLookupApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 8),
            ));

  /// [bundleId] iOS 的 CFBundleIdentifier；[country] 必须与上架区一致（本项目固定 cn）。
  Future<AppStoreInfo?> lookup(String bundleId, {String country = 'cn'}) async {
    try {
      final resp = await _dio.get(
        'https://itunes.apple.com/lookup',
        queryParameters: {
          'bundleId': bundleId,
          'country': country,
          // 客户端 cache buster：绕 CDN/客户端缓存（对 Apple 服务端缓存延迟无效）
          't': DateTime.now().millisecondsSinceEpoch,
        },
      );

      // iTunes 返回的 Content-Type 常为 text/javascript，dio 可能给出 String，需手动解析
      final data = resp.data;
      Map<String, dynamic>? json;
      if (data is Map<String, dynamic>) {
        json = data;
      } else if (data is String && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) json = decoded;
      }
      if (json == null) return null;

      final count = (json['resultCount'] as num?)?.toInt() ?? 0;
      final results = json['results'];
      // resultCount==0 / 空数组：该 country 区查不到（如未上该区），按"跳过"处理
      if (count <= 0 || results is! List || results.isEmpty) return null;

      final first = results.first;
      if (first is! Map<String, dynamic>) return null;

      final version = (first['version'] ?? '').toString().trim();
      if (version.isEmpty) return null;

      return AppStoreInfo(
        version: version,
        trackViewUrl: (first['trackViewUrl'] ?? '').toString(),
        trackId: (first['trackId'] as num?)?.toInt(),
        releaseNotes: (first['releaseNotes'] ?? '').toString(),
        minimumOsVersion: (first['minimumOsVersion'] ?? '').toString(),
      );
    } catch (_) {
      // 网络异常 / 403 限流 / 解析失败：静默跳过
      return null;
    }
  }
}
