import 'package:dio/dio.dart';

import 'server_clock.dart';

/// 用响应的 `Date` 头持续校准服务端时钟偏移。
///
/// 挂在日志拦截器之后、缓存拦截器之前：缓存短路的「假响应」不会走到这里
/// （它在缓存拦截器的 onRequest 阶段就 resolve 了），所以不会拿一个旧时间去校准。
class ServerClockInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _sync(response.headers.value('date'));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 4xx/5xx 同样带 Date 头，一样可以用来校准
    _sync(err.response?.headers.value('date'));
    handler.next(err);
  }

  void _sync(String? raw) {
    if (raw == null || raw.isEmpty) return;
    final t = parseHttpDate(raw);
    if (t != null) ServerClock.instance.syncFrom(t);
  }
}
