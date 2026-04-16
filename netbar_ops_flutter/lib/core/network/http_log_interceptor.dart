import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'slow_request_file_logger.dart';

/// 统一 HTTP 日志拦截器
/// - ≤1s：debug 控制台输出摘要
/// - >1s：写入本地文件完整报文（release 模式也生效）
class HttpLogInterceptor extends Interceptor {
  /// 慢请求阈值（毫秒）
  static const int _slowThresholdMs = 1000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_httpLog_startTime'] = DateTime.now().millisecondsSinceEpoch;
    options.extra['_httpLog_startDateTime'] = DateTime.now().toIso8601String();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    try {
      _logResult(
        requestOptions: response.requestOptions,
        statusCode: response.statusCode,
        responseHeaders: response.headers.map,
        responseBody: response.data,
        isError: false,
      );
    } catch (e) {
      debugPrint('[HttpLogInterceptor] onResponse log error: $e');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    try {
      _logResult(
        requestOptions: err.requestOptions,
        statusCode: err.response?.statusCode,
        responseHeaders: err.response?.headers.map,
        responseBody: err.response?.data,
        isError: true,
        errorType: err.type.name,
        errorMessage: err.message,
      );
    } catch (e) {
      debugPrint('[HttpLogInterceptor] onError log error: $e');
    }
    handler.next(err);
  }

  void _logResult({
    required RequestOptions requestOptions,
    int? statusCode,
    Map<String, List<String>>? responseHeaders,
    dynamic responseBody,
    required bool isError,
    String? errorType,
    String? errorMessage,
  }) {
    final startMs =
        requestOptions.extra['_httpLog_startTime'] as int? ?? 0;
    final startDateTime =
        requestOptions.extra['_httpLog_startDateTime'] as String? ?? '';
    final now = DateTime.now();
    final elapsed = startMs > 0 ? now.millisecondsSinceEpoch - startMs : 0;
    final method = requestOptions.method;
    final uri = requestOptions.uri.toString();
    final status = statusCode ?? 0;
    final tag = isError ? 'ERR' : 'OK';

    // 控制台摘要（仅 debug 模式）
    debugPrint('[HTTP][$tag] $status $method $uri ${elapsed}ms (startMs=$startMs)');

    // 超过阈值 → 写入文件（release 也生效）
    if (elapsed >= _slowThresholdMs) {
      debugPrint('[HTTP] 慢请求, 正在写入文件日志...');
      _writeSlowLog(
        method: method,
        uri: uri,
        startDateTime: startDateTime,
        endDateTime: now.toIso8601String(),
        elapsedMs: elapsed,
        requestHeaders: requestOptions.headers,
        requestBody: _formatRequestBody(requestOptions.data),
        statusCode: status,
        responseHeaders: responseHeaders,
        responseBody: _formatResponseBody(responseBody, requestOptions),
        isError: isError,
        errorType: errorType,
        errorMessage: errorMessage,
      );
    }
  }

  void _writeSlowLog({
    required String method,
    required String uri,
    required String startDateTime,
    required String endDateTime,
    required int elapsedMs,
    required Map<String, dynamic> requestHeaders,
    required String requestBody,
    required int statusCode,
    Map<String, List<String>>? responseHeaders,
    required String responseBody,
    required bool isError,
    String? errorType,
    String? errorMessage,
  }) {
    final buf = StringBuffer();
    buf.writeln('===== SLOW REQUEST [$startDateTime] =====');
    buf.writeln('请求发起: $startDateTime');
    buf.writeln('请求结束: $endDateTime');
    buf.writeln('耗时: ${elapsedMs}ms');
    buf.writeln('方法: $method');
    buf.writeln('URL: $uri');
    buf.writeln('请求Headers: ${_maskHeaders(requestHeaders)}');
    buf.writeln('请求Body: $requestBody');
    buf.writeln('--- 响应 ---');
    buf.writeln('状态码: $statusCode');
    if (isError) {
      buf.writeln('错误类型: $errorType');
      buf.writeln('错误消息: $errorMessage');
    }
    if (responseHeaders != null) {
      buf.writeln('响应Headers: $responseHeaders');
    }
    buf.writeln('响应Body: $responseBody');
    buf.writeln('==========================================');

    // 异步写文件，捕获异常防止静默失败
    SlowRequestFileLogger.instance.log(buf.toString()).catchError((e) {
      debugPrint('[HttpLogInterceptor] 写入慢请求日志失败: $e');
    });
  }

  /// 格式化请求 body，处理 FormData 和其他特殊类型
  String _formatRequestBody(dynamic data) {
    if (data == null) return '[null]';
    try {
      if (data is FormData) {
        final fields = data.fields.map((e) => '${e.key}=${e.value}').join(', ');
        final files =
            data.files.map((e) => '${e.key}=[file: ${e.value.filename}, ${e.value.length}bytes]').join(', ');
        return '[FormData: fields={$fields}, files={$files}]';
      }
      return data.toString();
    } catch (e) {
      return '[格式化失败: $e]';
    }
  }

  /// 格式化响应 body，处理二进制数据
  String _formatResponseBody(dynamic data, RequestOptions options) {
    if (data == null) return '[null]';
    try {
      if (options.responseType == ResponseType.bytes || data is List<int>) {
        final len = data is List ? data.length : 0;
        return '[binary $len bytes]';
      }
      final str = data.toString();
      // 截断过长的响应（文件记录限 10KB）
      if (str.length > 10240) {
        return '${str.substring(0, 10240)}\n... [truncated, total ${str.length} chars]';
      }
      return str;
    } catch (e) {
      return '[格式化失败: $e]';
    }
  }

  /// 脱敏 headers：Authorization 只保留前 10 位
  Map<String, dynamic> _maskHeaders(Map<String, dynamic> headers) {
    try {
      final masked = Map<String, dynamic>.from(headers);
      for (final key in ['Authorization', 'authorization']) {
        if (masked.containsKey(key)) {
          final val = masked[key]?.toString() ?? '';
          if (val.length > 10) {
            masked[key] = '${val.substring(0, 10)}***';
          }
        }
      }
      return masked;
    } catch (e) {
      return {'_error': '脱敏失败: $e'};
    }
  }
}
