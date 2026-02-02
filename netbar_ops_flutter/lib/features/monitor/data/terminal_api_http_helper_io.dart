// 原生 HTTP 请求辅助函数 - 非 Web 平台实现（dart:io）
// 使用 Socket 直接发送原始 HTTP 请求，完全控制每个字节
import 'dart:convert';
import 'dart:io';
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

/// 使用 Socket 直接发送 HTTP GET 请求
/// 完全绕过所有 HTTP 库，手动构造 HTTP 报文
Future<NativeHttpResponse?> nativeHttpGet({
  required String url,
  required String host,
  required int port,
  required String path,
  Map<String, String>? headers,
}) async {
  debugPrint('[RawSocket] ========== Socket 直接发送 GET 请求 ==========');
  debugPrint('[RawSocket] Host: $host:$port');
  debugPrint('[RawSocket] Path: $path');

  Socket? socket;
  try {
    // 1. DNS 解析获取 IP
    final addresses = await InternetAddress.lookup(host.toLowerCase());
    if (addresses.isEmpty) {
      debugPrint('[RawSocket] DNS 解析失败: 无可用地址');
      return null;
    }
    final ip = addresses.first.address;
    debugPrint('[RawSocket] DNS 解析: $host -> $ip');

    // 2. 建立 TCP 连接
    debugPrint('[RawSocket] 连接到 $ip:$port...');
    socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 30));
    debugPrint('[RawSocket] TCP 连接成功');

    // 3. 构造原始 HTTP 请求报文（完全手动控制，保留 Host 大小写）
    final requestLines = <String>[
      'GET $path HTTP/1.1',
      'Host: $host:$port',  // 关键：保留原始大小写
      'User-Agent: Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept: application/json, text/plain, */*',
      'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8',
      'Accept-Encoding: identity',  // 不压缩，方便调试
      'Connection: close',
    ];

    // 添加自定义 headers
    headers?.forEach((key, value) {
      requestLines.add('$key: $value');
    });

    // 添加空行表示 headers 结束
    requestLines.add('');
    requestLines.add('');

    final requestText = requestLines.join('\r\n');
    debugPrint('[RawSocket] ===== 发送的原始 HTTP 请求 =====');
    debugPrint(requestText);
    debugPrint('[RawSocket] ================================');

    // 4. 发送请求
    socket.write(requestText);
    await socket.flush();

    // 5. 读取响应
    final responseBytes = <int>[];
    await for (final chunk in socket) {
      responseBytes.addAll(chunk);
    }

    final responseText = utf8.decode(responseBytes);
    debugPrint('[RawSocket] ===== 收到的原始 HTTP 响应 =====');
    if (responseText.length < 1000) {
      debugPrint(responseText);
    } else {
      debugPrint('${responseText.substring(0, 1000)}...(truncated)');
    }
    debugPrint('[RawSocket] ================================');

    // 6. 解析响应
    final headerEndIndex = responseText.indexOf('\r\n\r\n');
    if (headerEndIndex == -1) {
      debugPrint('[RawSocket] 无法解析响应: 找不到 header 结束标记');
      return null;
    }

    final headerPart = responseText.substring(0, headerEndIndex);
    final bodyPart = responseText.substring(headerEndIndex + 4);

    // 解析状态行
    final statusLineEnd = headerPart.indexOf('\r\n');
    final statusLine = headerPart.substring(0, statusLineEnd);
    final statusMatch = RegExp(r'HTTP/\d\.\d\s+(\d+)').firstMatch(statusLine);
    final statusCode = statusMatch != null ? int.parse(statusMatch.group(1)!) : 0;

    debugPrint('[RawSocket] 状态码: $statusCode');

    // 解析 headers
    final responseHeaders = <String, String>{};
    final headerLines = headerPart.substring(statusLineEnd + 2).split('\r\n');
    for (final line in headerLines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final name = line.substring(0, colonIndex).trim().toLowerCase();
        final value = line.substring(colonIndex + 1).trim();
        responseHeaders[name] = value;
      }
    }

    return NativeHttpResponse(
      statusCode: statusCode,
      headers: responseHeaders,
      body: bodyPart,
    );
  } catch (e, stack) {
    debugPrint('[RawSocket] 请求失败: $e');
    debugPrint('[RawSocket] Stack: $stack');
    return null;
  } finally {
    socket?.destroy();
  }
}

/// 使用 Socket 直接发送 HTTP POST 请求
Future<NativeHttpResponse?> nativeHttpPost({
  required String url,
  required String host,
  required int port,
  required String path,
  Map<String, String>? headers,
  String? body,
}) async {
  debugPrint('[RawSocket] ========== Socket 直接发送 POST 请求 ==========');
  debugPrint('[RawSocket] Host: $host:$port');
  debugPrint('[RawSocket] Path: $path');

  Socket? socket;
  try {
    // 1. DNS 解析获取 IP
    final addresses = await InternetAddress.lookup(host.toLowerCase());
    if (addresses.isEmpty) {
      debugPrint('[RawSocket] DNS 解析失败: 无可用地址');
      return null;
    }
    final ip = addresses.first.address;
    debugPrint('[RawSocket] DNS 解析: $host -> $ip');

    // 2. 建立 TCP 连接
    socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 30));
    debugPrint('[RawSocket] TCP 连接成功');

    // 3. 计算请求体长度
    final bodyBytes = body != null ? utf8.encode(body) : <int>[];

    // 4. 构造原始 HTTP 请求报文
    final requestLines = <String>[
      'POST $path HTTP/1.1',
      'Host: $host:$port',  // 关键：保留原始大小写
      'User-Agent: Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept: application/json, text/plain, */*',
      'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8',
      'Content-Type: application/json',
      'Content-Length: ${bodyBytes.length}',
      'Accept-Encoding: identity',
      'Connection: close',
    ];

    // 添加自定义 headers
    headers?.forEach((key, value) {
      requestLines.add('$key: $value');
    });

    // 添加空行表示 headers 结束
    requestLines.add('');
    requestLines.add('');

    final headerText = requestLines.join('\r\n');

    // 5. 发送请求
    socket.write(headerText);
    if (bodyBytes.isNotEmpty) {
      socket.add(bodyBytes);
    }
    await socket.flush();

    // 6. 读取响应
    final responseBytes = <int>[];
    await for (final chunk in socket) {
      responseBytes.addAll(chunk);
    }

    final responseText = utf8.decode(responseBytes);

    // 7. 解析响应
    final headerEndIndex = responseText.indexOf('\r\n\r\n');
    if (headerEndIndex == -1) {
      debugPrint('[RawSocket] 无法解析响应: 找不到 header 结束标记');
      return null;
    }

    final headerPart = responseText.substring(0, headerEndIndex);
    final bodyPart = responseText.substring(headerEndIndex + 4);

    // 解析状态行
    final statusLineEnd = headerPart.indexOf('\r\n');
    final statusLine = headerPart.substring(0, statusLineEnd);
    final statusMatch = RegExp(r'HTTP/\d\.\d\s+(\d+)').firstMatch(statusLine);
    final statusCode = statusMatch != null ? int.parse(statusMatch.group(1)!) : 0;

    debugPrint('[RawSocket] 状态码: $statusCode');
    debugPrint('[RawSocket] 响应体长度: ${bodyPart.length}');

    // 解析 headers
    final responseHeaders = <String, String>{};
    final headerLines = headerPart.substring(statusLineEnd + 2).split('\r\n');
    for (final line in headerLines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final name = line.substring(0, colonIndex).trim().toLowerCase();
        final value = line.substring(colonIndex + 1).trim();
        responseHeaders[name] = value;
      }
    }

    return NativeHttpResponse(
      statusCode: statusCode,
      headers: responseHeaders,
      body: bodyPart,
    );
  } catch (e, stack) {
    debugPrint('[RawSocket] POST 请求失败: $e');
    debugPrint('[RawSocket] Stack: $stack');
    return null;
  } finally {
    socket?.destroy();
  }
}
