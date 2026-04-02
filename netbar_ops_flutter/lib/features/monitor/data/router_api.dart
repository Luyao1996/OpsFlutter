import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/storage/token_store.dart';
import '../../../shared/providers/app_providers.dart';

// ── Models ──

class RouterInfo {
  final String id;
  final String name;
  final String host;
  final String type;
  final String user;
  final String pass;
  final bool enabled;
  final String proxyUrl;
  final bool isIp;

  const RouterInfo({
    required this.id,
    required this.name,
    required this.host,
    this.type = '',
    this.user = '',
    this.pass = '',
    this.enabled = true,
    this.proxyUrl = '',
    this.isIp = false,
  });

  factory RouterInfo.fromJson(Map<String, dynamic> json) {
    return RouterInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      user: json['user']?.toString() ?? '',
      pass: json['pass']?.toString() ?? '',
      enabled: json['enabled'] == true,
      proxyUrl: json['proxyUrl']?.toString() ?? '',
      isIp: json['isIp'] == true,
    );
  }
}

class TrafficInterface {
  final String name;
  final String alias;
  final String ip;
  final String mac;
  final int sendRate;
  final int recvRate;
  final int sendBytes;
  final int recvBytes;
  final bool status;
  final String type;
  final int bandwidth;

  const TrafficInterface({
    this.name = '',
    this.alias = '',
    this.ip = '',
    this.mac = '',
    this.sendRate = 0,
    this.recvRate = 0,
    this.sendBytes = 0,
    this.recvBytes = 0,
    this.status = false,
    this.type = '',
    this.bandwidth = 0,
  });

  factory TrafficInterface.fromJson(Map<String, dynamic> json) {
    return TrafficInterface(
      name: json['name']?.toString() ?? '',
      alias: json['alias']?.toString() ?? '',
      ip: json['ip']?.toString() ?? '',
      mac: json['mac']?.toString() ?? '',
      sendRate: (json['sendRate'] as num?)?.toInt() ?? 0,
      recvRate: (json['recvRate'] as num?)?.toInt() ?? 0,
      sendBytes: (json['sendBytes'] as num?)?.toInt() ?? 0,
      recvBytes: (json['recvBytes'] as num?)?.toInt() ?? 0,
      status: json['status'] == true,
      type: json['type']?.toString() ?? '',
      bandwidth: (json['bandwidth'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Aggregated traffic rates for a router, split by WAN/LAN
class RouterTraffic {
  final int wanSendRate;
  final int wanRecvRate;
  final int lanSendRate;
  final int lanRecvRate;

  const RouterTraffic({
    this.wanSendRate = 0,
    this.wanRecvRate = 0,
    this.lanSendRate = 0,
    this.lanRecvRate = 0,
  });

  factory RouterTraffic.fromInterfaces(List<TrafficInterface> interfaces) {
    int wanSend = 0, wanRecv = 0, lanSend = 0, lanRecv = 0;
    for (final iface in interfaces) {
      if (iface.type == 'wan') {
        wanSend += iface.sendRate;
        wanRecv += iface.recvRate;
      } else {
        lanSend += iface.sendRate;
        lanRecv += iface.recvRate;
      }
    }
    return RouterTraffic(
      wanSendRate: wanSend,
      wanRecvRate: wanRecv,
      lanSendRate: lanSend,
      lanRecvRate: lanRecv,
    );
  }
}

// ── API Client ──

class RouterApi {
  late final Dio _dio;

  RouterApi({required String subdomainFull}) {
    // subdomainFull may already contain port (e.g. "xxx.frps.wwls.net")
    final hostOnly = subdomainFull.split(':').first;
    final baseUrl = 'https://router-$hostOnly/api';
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Content-Type': 'application/json'},
      // Accept all HTTP status codes so we can handle them in _unwrap
      validateStatus: (_) => true,
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        options.extra['_startTime'] = DateTime.now().millisecondsSinceEpoch;
        debugPrint('[RouterApi] ========== 请求开始 ==========');
        debugPrint('[RouterApi] ${options.method} ${options.uri}');
        debugPrint('[RouterApi] Headers: ${options.headers}');
        if (options.data != null) {
          debugPrint('[RouterApi] Body: ${options.data}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final start = response.requestOptions.extra['_startTime'] as int? ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - start;
        debugPrint('[RouterApi] ========== 请求成功 ==========');
        debugPrint('[RouterApi] 状态码: ${response.statusCode}');
        debugPrint('[RouterApi] 耗时: ${elapsed}ms');
        final resStr = response.data.toString();
        for (var i = 0; i < resStr.length; i += 800) {
          final end = (i + 800 < resStr.length) ? i + 800 : resStr.length;
          debugPrint('[RouterApi] 响应[${i ~/ 800}]: ${resStr.substring(i, end)}');
        }
        handler.next(response);
      },
      onError: (error, handler) {
        final start = error.requestOptions.extra['_startTime'] as int? ?? 0;
        final elapsed = DateTime.now().millisecondsSinceEpoch - start;
        debugPrint('[RouterApi] ========== 请求失败 ==========');
        debugPrint('[RouterApi] ${error.requestOptions.method} ${error.requestOptions.uri}');
        debugPrint('[RouterApi] 耗时: ${elapsed}ms');
        debugPrint('[RouterApi] 错误类型: ${error.type}');
        debugPrint('[RouterApi] 状态码: ${error.response?.statusCode}');
        debugPrint('[RouterApi] 响应数据: ${error.response?.data}');
        debugPrint('[RouterApi] 错误消息: ${error.message}');
        handler.next(error);
      },
    ));
  }

  /// Unwrap {code, data, msg} response format.
  /// RouterProxy returns code=0 for success.
  T _unwrap<T>(Response response, T Function(dynamic) parser) {
    // Handle non-JSON responses (e.g. frp 404 HTML page)
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw Exception('HTTP ${response.statusCode}: 服务不可用');
    }
    if (response.data is! Map<String, dynamic>) {
      throw Exception('响应格式异常: ${response.data.runtimeType}');
    }
    final map = response.data as Map<String, dynamic>;
    final code = map['code'] as int? ?? -1;
    if (code == 0) {
      return parser(map['data']);
    }
    final error = map['msg'] ?? map['error'] ?? map['message'] ?? '请求失败 (code: $code)';
    throw Exception(error.toString());
  }

  Future<List<RouterInfo>> getAll() async {
    final response = await _dio.get('/routers');
    return _unwrap(response, (data) {
      if (data is List) return data.map((e) => RouterInfo.fromJson(e)).toList();
      return <RouterInfo>[];
    });
  }

  Future<RouterInfo> create(Map<String, dynamic> data) async {
    final response = await _dio.post('/routers', data: data);
    return _unwrap(response, (d) => RouterInfo.fromJson(d));
  }

  Future<RouterInfo> update(String id, Map<String, dynamic> data) async {
    final response = await _dio.put('/routers/$id', data: data);
    return _unwrap(response, (d) => RouterInfo.fromJson(d));
  }

  Future<void> delete(String id) async {
    final response = await _dio.delete('/routers/$id');
    _unwrap(response, (_) => null);
  }

  Future<List<TrafficInterface>> getTraffic(String routerId) async {
    final response = await _dio.get('/traffic/$routerId');
    return _unwrap(response, (data) {
      if (data is Map<String, dynamic>) {
        final interfaces = data['interfaces'];
        if (interfaces is List) {
          return interfaces.map((e) => TrafficInterface.fromJson(e)).toList();
        }
      }
      return <TrafficInterface>[];
    });
  }

  Future<List<String>> getScriptTypes() async {
    final response = await _dio.get('/scripts/types');
    return _unwrap(response, (data) {
      if (data is List) return data.map((e) => e.toString()).toList();
      return <String>[];
    });
  }
}

// ── Providers ──

final routerApiProvider = Provider<RouterApi?>((ref) {
  final netbar = ref.watch(currentNetbarProvider);
  final domain = netbar.subdomainFull;
  if (domain == null || domain.isEmpty) return null;
  return RouterApi(subdomainFull: domain);
});

final routersProvider = FutureProvider<List<RouterInfo>>((ref) async {
  final api = ref.watch(routerApiProvider);
  if (api == null) return [];
  return api.getAll();
});

final scriptTypesProvider = FutureProvider<List<String>>((ref) async {
  final api = ref.watch(routerApiProvider);
  if (api == null) return [];
  return api.getScriptTypes();
});

// ── Helpers ──

String formatRate(int bytesPerSec) {
  if (bytesPerSec < 1024) return '${bytesPerSec} B/s';
  if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}
