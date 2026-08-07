import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 原生端缓存目录：`<appSupport>/api_cache/`，与慢请求日志的 http_logs 同级。
Directory? _dir;
Completer<void>? _initing;

Future<void> initCacheStorage() async {
  if (_dir != null) return;
  final pending = _initing;
  if (pending != null) return pending.future;

  final completer = Completer<void>();
  _initing = completer;
  try {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}${Platform.pathSeparator}api_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _dir = dir;
    debugPrint('[ApiCache] 缓存目录: ${dir.path}');
  } catch (e) {
    // 不抛：缓存不可用时整条链路降级为「无缓存」，不能拖垮请求。
    // _dir 保持 null，下次调用会重试。
    debugPrint('[ApiCache] 缓存目录初始化失败: $e');
  } finally {
    _initing = null;
    completer.complete();
  }
  return completer.future;
}

File? _fileOf(String key) {
  final dir = _dir;
  if (dir == null) return null;
  return File('${dir.path}${Platform.pathSeparator}$key.json');
}

Future<String?> readCacheEntry(String key) async {
  try {
    final f = _fileOf(key);
    if (f == null || !await f.exists()) return null;
    return await f.readAsString();
  } catch (e) {
    debugPrint('[ApiCache] 读取失败 key=$key: $e');
    return null;
  }
}

Future<void> writeCacheEntry(String key, String content) async {
  try {
    final f = _fileOf(key);
    if (f == null) return;
    await f.writeAsString(content, flush: false);
  } catch (e) {
    debugPrint('[ApiCache] 写入失败 key=$key: $e');
  }
}

Future<void> deleteCacheEntry(String key) async {
  try {
    final f = _fileOf(key);
    if (f != null && await f.exists()) await f.delete();
  } catch (_) {}
}

/// 清理过期缓存。按文件 mtime 判断，省去逐条解析 JSON 的开销。
Future<void> pruneCacheStorage(Duration maxAge) async {
  final dir = _dir;
  if (dir == null) return;
  try {
    final now = DateTime.now();
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          await entity.delete();
          removed++;
        }
      } catch (_) {}
    }
    if (removed > 0) debugPrint('[ApiCache] 清理过期缓存 $removed 条');
  } catch (e) {
    debugPrint('[ApiCache] 清理失败: $e');
  }
}

/// 清空全部缓存（换账号 / 登出时调用，防止跨账号串数据）。
Future<void> clearCacheStorage() async {
  final dir = _dir;
  if (dir == null) return;
  try {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    debugPrint('[ApiCache] 已清空全部缓存');
  } catch (e) {
    debugPrint('[ApiCache] 清空失败: $e');
  }
}
