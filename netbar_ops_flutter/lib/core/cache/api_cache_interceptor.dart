import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_cache_store.dart';
import 'offline_status.dart';

/// 响应 extra 标记：本次数据来自离线缓存。
/// UI 可据此显示「数据更新于 …」，写在 response.extra 与 requestOptions.extra 两处，
/// 调用方从哪边读都拿得到。
const String kFromCacheExtra = '_apiCache_fromCache';

/// 响应 extra 标记：缓存落盘时刻（毫秒时间戳）。
const String kCachedAtExtra = '_apiCache_savedAt';

/// 请求 extra 开关：置 true 时本次请求既不读缓存也不写缓存。
const String kNoCacheExtra = 'noCache';

/// 接口响应缓存拦截器 —— 离线可用能力的唯一入口。
///
/// 挂在 [ApiClient] 拦截器链的最后一环：
/// - onResponse 时前面的解包拦截器已把 `{code,message,data}` 剥成 data，
///   这里缓存到的就是各 `*_api.dart` 里 `fromJson` 直接消费的原文；
/// - onError 时前面的 401 处理与日志已经执行完，这里只兜网络类失败。
///
/// 覆盖面：项目 17 个 `*_api.dart`、60 处 GET 全部走 `ApiClient.instance`，
/// 所以业务侧零改动即可获得离线能力，包括不用 Riverpod、直接 setState 取数的页面。
///
/// 行为约定：
/// - 在线时行为与改造前完全一致（只额外写一份缓存），不读缓存；
/// - 网络类失败时回落缓存，命中则调用方无感知地拿到上次数据；
/// - 离线期间直接短路返回缓存，不再空转等超时，每 [OfflineStatus.probeInterval]
///   放行一个真实请求探活，成功即自动恢复在线。
class ApiCacheInterceptor extends Interceptor {
  /// 不参与缓存的路径：一次性凭证与登出，缓存它们没有意义且有安全风险。
  ///
  /// 时效性凭证必须排除：TOTP 码只有 30 秒有效期（period=30），离线时回落缓存
  /// 会甩给用户一个早已过期的码，复制去解锁必然失败，界面上还看不出它是旧的。
  /// 宁可离线时明确报错，也不能给一个看起来正常的错码。
  static const List<String> _excludedPaths = [
    // 扫码登录二维码 + 会话 pwd。路径以实际请求为准：AuthApi.preLogin() /
    // createQRSession() 打的是 /passport/login/qr（早先这里错写成
    // /passport/prelogin，等于没排除，离线会回落一张早已作废的二维码，
    // 用户扫了永远登不上还看不出是旧的）
    '/passport/login/qr',
    '/passport/token',
    '/passport/logout',
    '/passport/twoFactorCode',
    '/merchant/totp',
    // TOTP 密钥，落盘等于把二次验证的根凭证明文写进磁盘
    '/user/twoFactorAuth',
  ];

  bool _cacheable(RequestOptions options) {
    if (options.method.toUpperCase() != 'GET') return false;
    if (options.extra[kNoCacheExtra] == true) return false;
    // 只缓存 JSON 响应。二进制下载（resource_api 的 /file/down、log_api 的
    // /export/logs 都走 ApiClient.dio + ResponseType.bytes/stream）必须排除：
    // 写入侧 jsonEncode 一个几 MB 的 List<int> 纯属浪费，读取侧还会把
    // jsonDecode 出的 List<dynamic> 喂给 get<List<int>> 直接抛类型错误。
    if (options.responseType != ResponseType.json) return false;
    for (final p in _excludedPaths) {
      if (options.path.contains(p)) return false;
    }
    return true;
  }

  String _keyOf(RequestOptions o) =>
      ApiCacheStore.instance.keyFor(o.method, o.path, o.queryParameters);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_cacheable(options) || !OfflineStatus.instance.isOffline) {
      return handler.next(options);
    }

    // —— 以下均为离线态 ——
    // 轮到探针：放行真实请求去试网络，成功即恢复在线。
    // 不额外造探活接口，避免「探活接口通了但业务接口没通」的错判。
    if (OfflineStatus.instance.takeProbeSlot()) {
      _shortenTimeout(options);
      return handler.next(options);
    }

    final cached = await ApiCacheStore.instance.read(_keyOf(options));
    if (cached == null) {
      // 没有缓存就没有短路的意义（短路只会让页面永远没数据），
      // 放行让它自己去试，同样压缩超时避免空转 5 秒。
      _shortenTimeout(options);
      return handler.next(options);
    }

    debugPrint(
      '[ApiCache] 离线短路 ${options.path}（缓存于 ${cached.savedAt}）',
    );
    // resolve 默认不再走后续拦截器的 onResponse，
    // 日志拦截器因此不会为这条「假响应」记录一次网络请求。
    return handler.resolve(_cachedResponse(options, cached));
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 真实响应到达即证明网络可达（缓存短路的响应不会走到这里）
    OfflineStatus.instance.markOnline();
    if (_cacheable(response.requestOptions)) {
      ApiCacheStore.instance.write(
        _keyOf(response.requestOptions),
        response.data,
        label: response.requestOptions.path,
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_isNetworkError(err)) return handler.next(err);

    OfflineStatus.instance.markOffline();
    if (!_cacheable(err.requestOptions)) return handler.next(err);

    final cached = await ApiCacheStore.instance.read(_keyOf(err.requestOptions));
    if (cached == null) {
      // 这条日志是排查「离线时某页面为什么还是报错」的第一落点
      debugPrint('[ApiCache] 无可用缓存，按原错误返回 ${err.requestOptions.path}');
      return handler.next(err);
    }

    debugPrint(
      '[ApiCache] 网络失败回落缓存 ${err.requestOptions.path}（缓存于 ${cached.savedAt}）',
    );
    return handler.resolve(_cachedResponse(err.requestOptions, cached));
  }

  void _shortenTimeout(RequestOptions options) {
    final probe = OfflineStatus.probeTimeout;
    final connect = options.connectTimeout;
    final receive = options.receiveTimeout;
    // 只压缩，不放宽：文件下载等本就设了更短超时的请求保持原样
    if (connect == null || connect > probe) options.connectTimeout = probe;
    if (receive == null || receive > probe) options.receiveTimeout = probe;
  }

  Response _cachedResponse(RequestOptions options, CachedApiEntry entry) {
    final savedAtMs = entry.savedAt.millisecondsSinceEpoch;
    options.extra[kFromCacheExtra] = true;
    options.extra[kCachedAtExtra] = savedAtMs;
    return Response(
      requestOptions: options,
      data: entry.data,
      statusCode: 200,
      statusMessage: 'OK (offline cache)',
      extra: {
        kFromCacheExtra: true,
        kCachedAtExtra: savedAtMs,
      },
    );
  }

  /// 是否属于「网络不可达」类错误。
  ///
  /// badResponse（含业务错误码、401、5xx）与 cancel 不算断网：
  /// 后端能应答说明网络是通的，走缓存反而会掩盖真实错误。
  ///
  /// 不 import dart:io：Web 端编译不支持，改用类型名字符串判断。
  bool _isNetworkError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return true;
      case DioExceptionType.unknown:
        final s = e.error?.toString() ?? '';
        return s.contains('SocketException') ||
            s.contains('Failed host lookup') ||
            s.contains('Connection refused') ||
            s.contains('Connection closed') ||
            s.contains('Network is unreachable');
      default:
        return false;
    }
  }
}
