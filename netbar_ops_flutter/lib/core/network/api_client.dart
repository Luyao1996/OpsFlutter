import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../storage/token_store.dart';

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
                // 先触发登出状态变更（同步设 isLoggedIn=false → 路由立即跳转登录页）
                // 再异步清理 token/子窗口，避免 clearAuth 阻塞跳转
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
            // 先触发登出（同步），再异步清理
            onUnauthorized?.call();
            TokenStore.clearAuth();
          }
          return handler.next(error);
        },
      ),
    );
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
