import 'dart:async';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'http_log_interceptor.dart';

/// API 错误
class ApiError implements Exception {
  final int? code;
  final String message;
  final dynamic raw;

  ApiError({this.code, required this.message, this.raw});

  @override
  String toString() => message;
}

/// API 客户端
class ApiClient {
  static ApiClient? _instance;
  late Dio _dio;

  // 用于401时跳转登录的回调
  static Function? onUnauthorized;

  // Token 刷新并发锁：多个请求同时 401 时只刷新一次
  Completer<bool>? _refreshCompleter;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: Duration(milliseconds: AppConfig.receiveTimeout),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // 请求拦截器 - 添加 token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = TokenStore.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // 后端返回 {code, message, data} 格式，需要解包
          if (response.data is Map<String, dynamic>) {
            final map = response.data as Map<String, dynamic>;
            final code = map['code'];
            final message = map['message'];
            final data = map['data'];

            // 如果没有 code 字段，说明不是标准 API 响应格式，直接传递
            // 这种情况常见于网吧终端接口直接返回数据（如文件列表）
            if (code == null) {
              return handler.next(response);
            }

            // 处理响应体中的 401 未授权
            if (code == 401) {
              final ignoreUnauthorized = response.requestOptions.extra['ignoreUnauthorized'] == true;
              if (!ignoreUnauthorized) {
                // 尝试刷新 Token 并重放请求
                final refreshed = await _tryRefreshToken();
                if (refreshed) {
                  // 刷新成功，用新 token 重放原请求
                  final opts = response.requestOptions;
                  opts.headers['Authorization'] = 'Bearer ${TokenStore.getToken()}';
                  final retryResponse = await _dio.fetch(opts);
                  return handler.resolve(retryResponse);
                }
                // 刷新失败，登出
                onUnauthorized?.call();
                TokenStore.clearAuth();
              }
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  error: ApiError(code: code, message: message ?? '未授权，请重新登录', raw: map),
                  type: DioExceptionType.badResponse,
                ),
              );
            }

            if (code == 0) {
              // 成功时，将response.data替换为实际data
              response.data = data;
              return handler.next(response);
            } else {
              // 失败时抛出ApiError
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  error: ApiError(code: code, message: message ?? '请求失败', raw: map),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
          }
          return handler.next(response);
        },
        onError: (error, handler) async {
          final ignoreUnauthorized = error.requestOptions.extra['ignoreUnauthorized'] == true;
          if (!ignoreUnauthorized && error.response?.statusCode == 401) {
            // 尝试刷新 Token 并重放请求
            final refreshed = await _tryRefreshToken();
            if (refreshed) {
              final opts = error.requestOptions;
              opts.headers['Authorization'] = 'Bearer ${TokenStore.getToken()}';
              try {
                final retryResponse = await _dio.fetch(opts);
                return handler.resolve(retryResponse);
              } on DioException catch (e) {
                return handler.next(e);
              }
            }
            onUnauthorized?.call();
            TokenStore.clearAuth();
          }
          return handler.next(error);
        },
      ),
    );

    // 统一日志拦截器（放在业务拦截器之后，能看到完整 headers）
    _dio.interceptors.add(HttpLogInterceptor());
  }

  static ApiClient get instance {
    _instance ??= ApiClient._internal();
    return _instance!;
  }

  Dio get dio => _dio;

  /// GET 请求
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// POST 请求
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// PUT 请求
  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// DELETE 请求
  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// 尝试刷新 Token（带并发锁，多个 401 只刷新一次）
  /// 直接用独立 Dio 实例调刷新接口，避免经过拦截器造成死循环
  Future<bool> _tryRefreshToken() async {
    // 如果已有刷新请求在进行，等待其结果
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final token = TokenStore.getToken();
      if (token == null) {
        _refreshCompleter!.complete(false);
        return false;
      }
      // 用独立 Dio 实例，不经过拦截器
      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
      final response = await refreshDio.post(
        '/passport/refresh',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final innerData = data['data'] ?? data;
        final accessToken = innerData['access_token'] ?? '';
        if (accessToken.toString().isNotEmpty) {
          await TokenStore.setToken(accessToken);
          final expireIn = innerData['expire_in'] as int?;
          final createIn = innerData['create_in'] as int?;
          if (expireIn != null && expireIn > 0) {
            final baseMs = (createIn != null && createIn > 0)
                ? createIn * 1000
                : DateTime.now().millisecondsSinceEpoch;
            await TokenStore.setTokenExpireAt(baseMs + expireIn * 1000);
          }
          _refreshCompleter!.complete(true);
          return true;
        }
      }
      _refreshCompleter!.complete(false);
      return false;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// 处理错误
  ApiError _handleError(DioException e) {
    String message = '网络请求失败';
    if (e.response?.data is Map) {
      message = e.response?.data['error'] ?? e.response?.data['message'] ?? message;
    } else if (e.message != null) {
      message = e.message!;
    }
    return ApiError(
      code: e.response?.statusCode,
      message: message,
      raw: e,
    );
  }
}
