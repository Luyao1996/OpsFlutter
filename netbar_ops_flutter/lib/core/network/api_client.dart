import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../cache/api_cache_interceptor.dart';
import '../config/app_config.dart';
import '../security/server_clock_interceptor.dart';
import '../storage/token_store.dart';
import 'http_log_interceptor.dart';
import 'trusted_roots.dart';

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

    // 内置 ISRG Root X1 信任锚点：客户机证书库缺根（老镜像+禁更新的网吧机）
    // 时 HTTPS 业务接口仍可校验通过；系统库正常时行为不变。见 trusted_roots.dart
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: createHttpClientWithBundledRoots,
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
            // token 生命周期完全由后端控制，前端不再续命，直接登出。
            if (code == 401) {
              final ignoreUnauthorized = response.requestOptions.extra['ignoreUnauthorized'] == true;
              if (!ignoreUnauthorized) {
                onUnauthorized?.call();
                // 被动 401 保留离线缓存：token 到期还是同一个人，
                // 抹掉他攒的数据会让重新登录后一断网就一无所有
                TokenStore.clearAuth(keepApiCache: true);
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
              // code/message 做类型守卫：后端若返回字符串型 code（如 Apple 登录
              // 的 APPLE_ID_NOT_BOUND），直接塞 int? 字段会在运行期抛 TypeError
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  error: ApiError(
                    code: code is int ? code : null,
                    message: message is String ? message : '请求失败',
                    raw: map,
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
          }
          return handler.next(response);
        },
        onError: (error, handler) async {
          // HTTP 状态码 401：与 onResponse 行为一致，直接登出，不再尝试续命。
          final ignoreUnauthorized = error.requestOptions.extra['ignoreUnauthorized'] == true;
          if (!ignoreUnauthorized && error.response?.statusCode == 401) {
            onUnauthorized?.call();
            TokenStore.clearAuth(keepApiCache: true);
          }
          return handler.next(error);
        },
      ),
    );

    // 统一日志拦截器（放在业务拦截器之后，能看到完整 headers）
    _dio.interceptors.add(HttpLogInterceptor());

    // 服务端时钟校准（读 Date 头）：必须排在缓存拦截器之前，
    // 否则缓存短路的「假响应」会被当成真实响应拿去校准。
    _dio.interceptors.add(ServerClockInterceptor());

    // 离线缓存拦截器（必须挂在最后一环）：
    // - onResponse 顺序在解包之后，缓存到的是剥壳后的 data，与各 API 的 fromJson 同构；
    // - onError 顺序在 401 处理与日志之后，只兜网络类失败，不干扰既有错误链路。
    _dio.interceptors.add(ApiCacheInterceptor());
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
      // 优先用后端返回的业务错误信息（通常已是中文）
      message = e.response?.data['error'] ?? e.response?.data['message'] ?? message;
    } else {
      // 无响应体：按 Dio 异常类型给中文友好文案，避免把英文技术串透给用户
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          message = '网络连接超时，请稍后重试';
          break;
        case DioExceptionType.connectionError:
          message = '网络连接失败，请检查网络';
          break;
        case DioExceptionType.badCertificate:
          message = '安全证书校验失败';
          break;
        case DioExceptionType.cancel:
          message = '请求已取消';
          break;
        default:
          message = e.message ?? message;
      }
    }
    return ApiError(
      code: e.response?.statusCode,
      message: message,
      raw: e,
    );
  }
}
