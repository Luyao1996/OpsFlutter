// DNS 解析辅助函数 - Web 平台 stub 实现
import 'package:flutter/foundation.dart';

/// 执行 DNS 解析并打印结果（Web 平台不支持）
Future<void> performDnsLookup(String host) async {
  debugPrint('[DNS Helper] Web平台不支持DNS解析');
}

/// 执行 DNS 解析并返回第一个 IPv4 地址（Web 平台返回 null）
Future<String?> resolveDns(String host) async {
  debugPrint('[DNS Helper] Web平台不支持DNS解析，将使用域名');
  return null;
}
