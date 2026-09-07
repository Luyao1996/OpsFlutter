import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/dio_helper.dart';
import '../../../core/storage/token_store.dart';
import '../../../shared/providers/app_providers.dart';

// ── Models ──

/// 设备类型取值（与后端 `/config/global/router_types` 下发的 deviceType 字段对齐，
/// 见 toolboxPage RouterCard.vue:68-70）。缺省一律按路由器处理。
const String kDeviceTypeRouter = '路由器';
const String kDeviceTypeSwitch = '交换机';

/// 网页管理（腾讯网吧特权 / 网吧特权服务平台这类）：不是内网设备，是公网站点。
/// 它既不走 frp 隧道，打开方式也与路由器/交换机完全不同，见
/// monitor_page._openRouterInBrowser。
const String kDeviceTypeWeb = '网页管理';

class RouterInfo {
  final String id;
  final String name;
  final String host;
  final String type;
  final String user;
  final String pass;

  /// 二次密码：只有「网页管理」这类平台才有这道验证，选填。
  /// 后端字段名就叫 pass2（toolboxPage useRouters.js:112 同名提交）。
  final String pass2;
  final bool enabled;
  final String proxyUrl;
  final bool isIp;

  /// 设备类型：路由器 / 交换机 / 网页管理。
  ///
  /// 后端 `/routers` 的记录不一定带这个字段（保存时也没往上传），所以列表拿到手后
  /// 还要按脚本类型名去类型表里反查补齐，见 [resolveDeviceType] 与 [routersProvider]。
  final String deviceType;

  const RouterInfo({
    required this.id,
    required this.name,
    required this.host,
    this.type = '',
    this.user = '',
    this.pass = '',
    this.pass2 = '',
    this.enabled = true,
    this.proxyUrl = '',
    this.isIp = false,
    this.deviceType = kDeviceTypeRouter,
  });

  factory RouterInfo.fromJson(Map<String, dynamic> json) {
    return RouterInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      user: json['user']?.toString() ?? '',
      pass: json['pass']?.toString() ?? '',
      pass2: json['pass2']?.toString() ?? '',
      enabled: json['enabled'] == true,
      // 兼容两种命名：后端历史上把字段从驼峰 proxyUrl 改成蛇形 proxy_url，
      // 优先取驼峰兜底蛇形（与 toolboxPage RemoteWakePage.vue:333 一致）。
      proxyUrl: (json['proxyUrl'] ?? json['proxy_url'])?.toString() ?? '',
      isIp: json['isIp'] == true,
      // 记录自带就用自带的（兼容驼峰/蛇形两种写法），缺失留空由 resolveDeviceType 反查
      deviceType:
          (json['deviceType'] ?? json['device_type'])?.toString().trim() ?? '',
    );
  }

  RouterInfo copyWith({String? deviceType}) => RouterInfo(
        id: id,
        name: name,
        host: host,
        type: type,
        user: user,
        pass: pass,
        pass2: pass2,
        enabled: enabled,
        proxyUrl: proxyUrl,
        isIp: isIp,
        deviceType: deviceType ?? this.deviceType,
      );

  bool get isWebManage => deviceType == kDeviceTypeWeb;
  bool get isSwitch => deviceType == kDeviceTypeSwitch;
}

/// 脚本类型表的一项（`/config/global/router_types` 下发）。
class ScriptType {
  final String name;
  final String deviceType;

  /// 该类型的默认地址（后端字段名是 host）。新增时选中类型会自动填进地址栏。
  final String defaultHost;

  const ScriptType({
    required this.name,
    this.deviceType = kDeviceTypeRouter,
    this.defaultHost = '',
  });

  factory ScriptType.fromJson(dynamic raw) {
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final device =
          (map['deviceType'] ?? map['device_type'])?.toString().trim() ?? '';
      return ScriptType(
        // 必须 trim：后端配置里 " 腾讯网吧特权 " 前后带空格，不裁掉的话下拉里会多出
        // 两段空白，存进记录后跟别处的同名比较也会对不上
        name: (map['name'] ?? '').toString().trim(),
        deviceType: device.isEmpty ? kDeviceTypeRouter : device,
        // 默认地址：后端下发的字段名是 host，另外两种写法留作兼容
        defaultHost:
            (map['host'] ?? map['defaultHost'] ?? map['default_host'])?.toString().trim() ?? '',
      );
    }
    return ScriptType(name: raw?.toString().trim() ?? '');
  }

  /// 下拉里的展示文案：`名称(设备类型)`，与 toolboxPage RouterFormDialog.vue:27 一致
  String get label => '$name($deviceType)';
}

/// 设备类型兜底：优先记录自带，其次按脚本类型名去类型表反查，最后落回「路由器」。
///
/// 名字比较一律先 trim —— 后端配置里是 " 腾讯网吧特权 " 带空格，而历史记录里存的
/// 可能是不带空格的版本，不裁掉就匹配不上、又会掉回「路由器」
/// （对齐 toolboxPage useRouters.js:20-38）。
String resolveDeviceType(RouterInfo r, List<ScriptType> types) {
  if (r.deviceType.isNotEmpty) return r.deviceType;
  final key = r.type.trim();
  for (final t in types) {
    if (t.name.trim() == key) return t.deviceType;
  }
  return kDeviceTypeRouter;
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
  final int _merchantId;

  RouterApi({required String subdomainFull, required int merchantId})
      : _merchantId = merchantId {
    // subdomainFull may already contain port (e.g. "xxx.frps.wwls.net")
    // 当前仅供 getTraffic 使用（流量接口尚未中央 HTTP 化，文档《WebSocket 升级
    // 接口改动清单》C 表标 ⚠️ "待后端确认"）。其余 CRUD/getScriptTypes 已迁移
    // 到 ApiClient.instance（中央 HTTP）。getTraffic 中央 HTTP 化后即可删此 _dio。
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

  /// 路由器列表 —— 走中央 HTTP `GET /routers?merchant_id=X`。
  /// 拦截器已剥外壳，res.data 即后端 data 字段值（List）。
  Future<List<RouterInfo>> getAll() async {
    final response = await ApiClient.instance.get(
      '/routers',
      queryParameters: {'merchant_id': _merchantId},
    );
    final data = response.data;
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => RouterInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }

  /// 创建路由器 —— 中央 HTTP，body 必须带 `merchant_id`（按 toolboxPage useRouters.js:101）
  Future<RouterInfo> create(Map<String, dynamic> data) async {
    final response = await ApiClient.instance.post(
      '/routers',
      data: {...data, 'merchant_id': _merchantId},
    );
    final raw = response.data;
    return RouterInfo.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
  }

  /// 更新路由器 —— 中央 HTTP，body **不带** merchant_id
  Future<RouterInfo> update(String id, Map<String, dynamic> data) async {
    final response = await ApiClient.instance.put(
      '/routers/$id',
      data: data,
    );
    final raw = response.data;
    return RouterInfo.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
  }

  /// 删除路由器 —— 中央 HTTP
  Future<void> delete(String id) async {
    await ApiClient.instance.delete('/routers/$id');
  }

  /// 保存路由器备注（toolboxPage useRouters.js:130 saveRemark 对齐）
  Future<void> saveRemark(String id, String remark) async {
    await ApiClient.instance.put(
      '/routers/$id/remark',
      data: {'remark': remark},
    );
  }

  /// 路由器流量 —— **保留 frp 路由器代理**。
  /// toolboxPage 未实现该接口的中央 HTTP 化（useRouters.js 无 traffic 相关逻辑），
  /// 故 Flutter 端继续走 frp 不动。
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

  /// 脚本类型枚举 —— 路径 `/config/global/router_types`（toolboxPage useRouters.js:90）
  ///
  /// 返回结构化的 [ScriptType]（含 deviceType / 默认地址），而不是只取名字：
  /// deviceType 是卡片渲染和打开方式的依据，defaultHost 是新增时的地址自动填充。
  Future<List<ScriptType>> getScriptTypes() async {
    final response = await ApiClient.instance.get('/config/global/router_types');
    final data = response.data;
    if (data is List) {
      return data
          .map(ScriptType.fromJson)
          .where((t) => t.name.isNotEmpty)
          .toList();
    }
    return const [];
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
  return RouterApi(subdomainFull: domain, merchantId: netbarId);
});

/// 按 netbarId 隔离的路由器列表（deviceType 已按类型表回填）。
final routersProvider =
    FutureProvider.autoDispose.family<List<RouterInfo>, int?>(
  (ref, netbarId) async {
    final api = ref.watch(routerApiProvider(netbarId));
    if (api == null) return const [];
    // 类型表与列表并行拉：deviceType 决定卡片图标/配色和点击后的打开方式，卡片一渲染
    // 就要用，不能等编辑弹窗打开才拉（对齐 toolboxPage useRouters.js:46 提前 fetch）。
    // 类型表失败不牵连列表 —— 只是全部落回「路由器」，页面照常可用。
    final typesFuture = ref
        .watch(scriptTypesProvider(netbarId).future)
        .catchError((_) => const <ScriptType>[]);
    final list = await api.getAll();
    final types = await typesFuture;
    return list
        .map((r) => r.copyWith(deviceType: resolveDeviceType(r, types)))
        .toList();
  },
);

/// 按 netbarId 隔离的脚本类型列表。
final scriptTypesProvider =
    FutureProvider.autoDispose.family<List<ScriptType>, int?>(
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
