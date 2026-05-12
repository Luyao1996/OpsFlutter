// DNS 解析辅助函数 - 非 Web 平台实现（dart:io）
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 执行 DNS 解析并打印结果
Future<void> performDnsLookup(String host) async {
  try {
    debugPrint('[DNS Helper] 开始解析: $host');
    final addresses = await InternetAddress.lookup(host);
    debugPrint('[DNS Helper] DNS解析结果 ($host):');
    for (final addr in addresses) {
      debugPrint('[DNS Helper]   - ${addr.address} (${addr.type.name})');
    }
  } catch (e) {
    debugPrint('[DNS Helper] DNS解析失败 ($host): $e');
  }
}

/// 执行 DNS 解析并返回第一个 IPv4 地址
Future<String?> resolveDns(String host) async {
  try {
    debugPrint('[DNS Helper] 解析域名: $host');
    final addresses = await InternetAddress.lookup(host);
    // 优先返回 IPv4 地址
    for (final addr in addresses) {
      if (addr.type == InternetAddressType.IPv4) {
        debugPrint('[DNS Helper] 解析成功: $host -> ${addr.address}');
        return addr.address;
      }
    }
    // 如果没有 IPv4，返回第一个地址
    if (addresses.isNotEmpty) {
      debugPrint('[DNS Helper] 解析成功 (IPv6): $host -> ${addresses.first.address}');
      return addresses.first.address;
    }
    debugPrint('[DNS Helper] 解析失败: 无可用地址');
    return null;
  } catch (e) {
    debugPrint('[DNS Helper] DNS解析异常: $e');
    return null;
  }
}
