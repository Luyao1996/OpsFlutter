import 'package:dio/dio.dart';
import 'http_log_interceptor.dart';

/// 创建带统一日志拦截器的 Dio 实例。
/// 项目中所有 Dio 实例都应通过此函数创建，
/// grep `Dio(` 即可发现是否有遗漏。
Dio createDio([BaseOptions? options]) {
  final dio = Dio(options ?? BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));
  // 若调用方传入了自定义 BaseOptions 但未设置超时，补上默认值
  if (options != null) {
    dio.options.connectTimeout ??= const Duration(seconds: 5);
    dio.options.receiveTimeout ??= const Duration(seconds: 5);
  }
  dio.interceptors.add(HttpLogInterceptor());
  return dio;
}
