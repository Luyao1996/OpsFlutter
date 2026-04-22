import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_helper.dart';
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
    _dio = createDio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      // Accept all HTTP status codes so we can handle them in _unwrap
      validateStatus: (_) => true,
    ));

    // Token 注入拦截器（日志由 createDio 统一挂载的 HttpLogInterceptor 处理）
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = TokenStore.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
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

/// 按 netbarId 隔离的 RouterApi。
/// 每个网吧对应独立实例；切网吧后旧 family 没有订阅者会 autoDispose，previous 不跨网吧保留。
final routerApiProvider =
    Provider.autoDispose.family<RouterApi?, int?>((ref, netbarId) {
  if (netbarId == null) return null;
  final netbar = ref.watch(currentNetbarProvider);
  // 严格校验：family key 必须与当前 state 对齐，否则返回 null，
  // 防止极端竞态下"旧 key 拿到新网吧数据"的串台。
  if (netbar.id != netbarId) return null;
  final domain = netbar.subdomainFull;
  if (domain == null || domain.isEmpty) return null;
  return RouterApi(subdomainFull: domain);
});

/// 按 netbarId 隔离的路由器列表。
final routersProvider =
    FutureProvider.autoDispose.family<List<RouterInfo>, int?>(
  (ref, netbarId) async {
    final api = ref.watch(routerApiProvider(netbarId));
    if (api == null) return const [];
    return api.getAll();
  },
);

/// 按 netbarId 隔离的脚本类型列表。
final scriptTypesProvider =
    FutureProvider.autoDispose.family<List<String>, int?>(
  (ref, netbarId) async {
    final api = ref.watch(routerApiProvider(netbarId));
    if (api == null) return const [];
    return api.getScriptTypes();
  },
);

// ── Helpers ──

String formatRate(int bytesPerSec) {
  if (bytesPerSec < 1024) return '${bytesPerSec} B/s';
  if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}
