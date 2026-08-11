import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../storage/token_store.dart';
import 'api_cache_storage.dart';

/// 一条接口响应缓存。
class CachedApiEntry {
  /// 后端 `{code,message,data}` 剥壳后的 data 原文（未经 model 转换）。
  ///
  /// 只缓存原始 JSON 而不缓存 model：全项目 fromJson 有 221 处、toJson 仅 23 处，
  /// 大量模型没有 toJson，按 model 缓存等于要给几十个类补序列化。
  final dynamic data;

  /// 落盘时刻，用于过期判定与 UI 上的「数据更新于 …」。
  final DateTime savedAt;

  const CachedApiEntry({required this.data, required this.savedAt});
}

/// 接口响应缓存仓库（单例）。
///
/// 写入由 [ApiCacheInterceptor] 在成功响应后触发，读取在网络失败回落
/// 或离线短路时触发。业务代码无需感知。
class ApiCacheStore {
  static final ApiCacheStore instance = ApiCacheStore._();
  ApiCacheStore._();

  /// 缓存格式版本。字段结构变更时 +1，旧条目会被视为无效自动丢弃。
  static const int _schemaVersion = 1;

  /// 缓存保留时长。
  ///
  /// 最初定的 3 天，但那会直接违背「离线要能看到我看过的数据」这个目标：
  /// 隔个周末没在线打开过某个页面，缓存就被清掉，断网时照样是错误页。
  /// 实测缓存体量极小（7 条约 65KB），拿磁盘换可用性完全划算，放宽到 30 天，
  /// 并由 [maxTotalBytes] 兜住极端情况。
  static const Duration maxAge = Duration(days: 30);

  /// 缓存目录总量上限，超出时从最旧的开始删。
  static const int maxTotalBytes = 50 * 1024 * 1024;

  /// 单条响应上限 1MB：游戏库等接口可达 MB 级，全量落盘不划算。
  static const int maxEntryChars = 1024 * 1024;

  /// 内存 LRU 容量（条）。
  static const int _memoryCapacity = 64;

  /// LinkedHashMap 保序，配合 remove + 重新插入实现 LRU。
  final Map<String, CachedApiEntry> _memory = <String, CachedApiEntry>{};

  bool _ready = false;

  /// 在 main() 中调用一次。失败不抛，缓存层整体降级为「无缓存」。
  Future<void> init() async {
    if (_ready) return;
    await initCacheStorage();
    _ready = true;
    // 换账号 / 登出时清空，防止下一个人看到上一个人的数据。
    // 由缓存层反向注册钩子，保持 storage → cache 的单向依赖。
    TokenStore.onAfterClearAuth = clear;
    unawaited(pruneCacheStorage(maxAge, maxTotalBytes: maxTotalBytes));
  }

  /// 缓存归属账号。
  ///
  /// 用用户 id 而不是 token：同一账号重新登录后 token 会变，
  /// 用 token 做归属会让缓存整体失效，失去离线兜底的意义。
  String get _owner => (TokenStore.getUser()?['id'] ?? 'anon').toString();

  /// 缓存键：账号 + 方法 + 路径 + 排序后的 query。
  /// query 排序保证同一请求在参数顺序不同时命中同一条缓存。
  String keyFor(String method, String path, Map<String, dynamic>? query) {
    final parts = <String>[];
    if (query != null && query.isNotEmpty) {
      final keys = query.keys.toList()..sort();
      for (final k in keys) {
        parts.add('$k=${query[k]}');
      }
    }
    final raw = '$_owner|${method.toUpperCase()}|$path|${parts.join('&')}';
    return sha1.convert(utf8.encode(raw)).toString();
  }

  bool _expired(DateTime savedAt) =>
      DateTime.now().difference(savedAt) > maxAge;

  Future<CachedApiEntry?> read(String key) async {
    final mem = _memory[key];
    if (mem != null) {
      if (_expired(mem.savedAt)) {
        _memory.remove(key);
        unawaited(deleteCacheEntry(key));
        return null;
      }
      // 命中即提升为最近使用
      _memory.remove(key);
      _memory[key] = mem;
      return mem;
    }

    if (!_ready) return null;
    final raw = await readCacheEntry(key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['v'] != _schemaVersion) {
        unawaited(deleteCacheEntry(key));
        return null;
      }
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        (decoded['savedAt'] as num).toInt(),
      );
      if (_expired(savedAt)) {
        unawaited(deleteCacheEntry(key));
        return null;
      }
      final entry = CachedApiEntry(data: decoded['data'], savedAt: savedAt);
      _putMemory(key, entry);
      return entry;
    } catch (e) {
      // 并发写可能留下半截文件，直接丢弃
      debugPrint('[ApiCache] 缓存解析失败，丢弃 key=$key: $e');
      unawaited(deleteCacheEntry(key));
      return null;
    }
  }

  /// 写缓存。同步返回，落盘异步进行，不阻塞响应返回给调用方。
  ///
  /// [label] 仅用于日志（一般传请求 path）：跳过缓存的原因必须可见，
  /// 否则线上出现「这个页面离线怎么没数据」时无从查起。
  void write(String key, dynamic data, {String label = ''}) {
    if (!_ready) {
      debugPrint('[ApiCache] 存储未就绪，未缓存 $label');
      return;
    }
    if (data == null) return;
    final String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (_) {
      // 二进制下载等非 JSON 响应不缓存
      debugPrint('[ApiCache] 响应无法序列化，未缓存 $label');
      return;
    }
    if (encoded.length > maxEntryChars) {
      debugPrint('[ApiCache] 响应过大未缓存 $label '
          '(${encoded.length ~/ 1024}KB > ${maxEntryChars ~/ 1024}KB)');
      return;
    }

    final entry = CachedApiEntry(data: data, savedAt: DateTime.now());
    _putMemory(key, entry);
    // encoded 已是合法 JSON，直接拼接避免二次编码
    final payload =
        '{"v":$_schemaVersion,"savedAt":${entry.savedAt.millisecondsSinceEpoch},"data":$encoded}';
    unawaited(writeCacheEntry(key, payload));
  }

  void _putMemory(String key, CachedApiEntry entry) {
    _memory.remove(key);
    _memory[key] = entry;
    while (_memory.length > _memoryCapacity) {
      _memory.remove(_memory.keys.first);
    }
  }

  /// 清空全部缓存（换账号 / 登出）。
  Future<void> clear() async {
    _memory.clear();
    await clearCacheStorage();
  }
}
