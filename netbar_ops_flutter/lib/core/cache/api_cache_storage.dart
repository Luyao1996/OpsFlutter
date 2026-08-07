// 接口响应缓存的底层存储 —— 跨平台条件导入。
// 原生端落文件（<appSupport>/api_cache/），Web 端降级到 SharedPreferences。
//
// 约定：所有函数都不抛异常，失败时静默降级为「无缓存」，
// 缓存层任何故障都不允许影响正常请求链路。

export 'api_cache_storage_stub.dart'
    if (dart.library.io) 'api_cache_storage_io.dart';
