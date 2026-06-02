import 'dart:async';
import 'dart:io';

import 'api_client.dart';

/// 把任意异常转成面向用户的中文友好文案（不含技术细节）。
///
/// 技术原文请单独放到「详情」里（见 AppErrorView），不要直接甩给用户。
/// 超时/断网在 [ApiError] 源头（api_client _handleError）已中文化，这里再兜底。
String friendlyErrorMessage(Object? error) {
  if (error == null) return '加载失败，请稍后重试';

  if (error is ApiError) {
    final m = error.message.trim();
    // 后端 message 通常是中文；仅当为空或像英文技术串时回退到状态码兜底。
    if (m.isEmpty || _looksTechnical(m)) return _byStatusCode(error.code);
    return m;
  }
  if (error is TimeoutException) return '请求超时，请稍后重试';
  if (error is SocketException) return '网络连接失败，请检查网络后重试';

  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Connection')) {
    return '网络连接失败，请检查网络后重试';
  }
  if (s.contains('TimeoutException') || s.contains('timeout')) {
    return '请求超时，请稍后重试';
  }
  return '加载失败，请稍后重试';
}

/// 判断一段文案是否更像「技术串」而非给用户看的提示：
/// 几乎无中文，且含 Exception/Error/http 等关键字或过长。
bool _looksTechnical(String m) {
  final hasCjk = RegExp(r'[一-龥]').hasMatch(m);
  if (hasCjk) return false;
  final looksException = m.contains('Exception') ||
      m.contains('Error') ||
      m.contains('http') ||
      m.contains('Dio');
  return looksException || m.length > 60;
}

String _byStatusCode(int? code) {
  switch (code) {
    case 400:
      return '请求有误，请稍后重试';
    case 401:
      return '登录已失效，请重新登录';
    case 403:
      return '没有权限访问';
    case 404:
      return '请求的资源不存在';
    case 500:
    case 502:
    case 503:
    case 504:
      return '服务暂时不可用，请稍后重试';
    default:
      return '加载失败，请稍后重试';
  }
}
