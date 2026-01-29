/// 应用配置
class AppConfig {
  // API 基础URL，可通过 --dart-define BASE_URL=... 覆盖
  // 后端实际路径前缀为 /api（非 /api/v1）
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://net.hudd.cc:888/api',
  );

  // 应用名称
  static const String appName = 'Netbar Ops Pro';

  // 版本号
  static const String version = '2.5.0';

  // 请求超时时间（毫秒）
  static const int connectTimeout = 10000;
  static const int receiveTimeout = 10000;
}
