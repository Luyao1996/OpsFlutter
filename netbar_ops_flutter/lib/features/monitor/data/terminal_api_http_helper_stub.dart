// 原生 HTTP 请求辅助函数 - Web 平台 stub 实现
import 'package:flutter/foundation.dart';

/// HTTP 响应结果
class NativeHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  NativeHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

/// 使用原生 HttpClient 发送 GET 请求（Web 平台不支持）
Future<NativeHttpResponse?> nativeHttpGet({
  required String url,
  required String host,
  required int port,
  required String path,
  Map<String, String>? headers,
}) async {
  debugPrint('[NativeHttp] Web平台不支持原生HTTP请求');
  return null;
}

/// 使用原生 HttpClient 发送 POST 请求（Web 平台不支持）
Future<NativeHttpResponse?> nativeHttpPost({
  required String url,
  required String host,
  required int port,
  required String path,
  Map<String, String>? headers,
  String? body,
}) async {
  debugPrint('[NativeHttp] Web平台不支持原生HTTP请求');
  return null;
}
