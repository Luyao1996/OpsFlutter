import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web 端无文件系统，降级到 SharedPreferences（底层是 localStorage）。
const String _prefix = 'api_cache:';

/// localStorage 总容量通常只有 5MB，单条上限比原生端收得更紧。
const int _webMaxEntryChars = 200 * 1024;

SharedPreferences? _prefs;

Future<void> initCacheStorage() async {
  if (_prefs != null) return;
  try {
    _prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('[ApiCache] SharedPreferences 初始化失败: $e');
  }
}

Future<String?> readCacheEntry(String key) async {
  try {
    return _prefs?.getString('$_prefix$key');
  } catch (e) {
    return null;
  }
}

Future<void> writeCacheEntry(String key, String content) async {
  if (content.length > _webMaxEntryChars) return;
  try {
    await _prefs?.setString('$_prefix$key', content);
  } catch (e) {
    debugPrint('[ApiCache] 写入失败 key=$key: $e');
  }
}

Future<void> deleteCacheEntry(String key) async {
  try {
    await _prefs?.remove('$_prefix$key');
  } catch (_) {}
}

/// Web 端没有文件 mtime，只能解析条目里的 savedAt 判断过期。
///
/// [maxTotalBytes] 在 Web 端忽略：localStorage 自身就有 5MB 硬上限，
/// 加上写入侧的单条 200KB 限制已经足够兜底，不值得再遍历统计一遍。
Future<void> pruneCacheStorage(Duration maxAge, {int? maxTotalBytes}) async {
  final prefs = _prefs;
  if (prefs == null) return;
  try {
    final now = DateTime.now().millisecondsSinceEpoch;
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      try {
        final raw = prefs.getString(k);
        if (raw == null) continue;
        final map = jsonDecode(raw);
        final savedAt = map is Map ? (map['savedAt'] as num?)?.toInt() : null;
        if (savedAt == null || now - savedAt > maxAge.inMilliseconds) {
          await prefs.remove(k);
        }
      } catch (_) {
        await prefs.remove(k);
      }
    }
  } catch (e) {
    debugPrint('[ApiCache] 清理失败: $e');
  }
}

Future<void> clearCacheStorage() async {
  final prefs = _prefs;
  if (prefs == null) return;
  try {
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    debugPrint('[ApiCache] 已清空全部缓存');
  } catch (e) {
    debugPrint('[ApiCache] 清空失败: $e');
  }
}
