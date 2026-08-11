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

/// 临时文件序号，保证同进程内并发写同一 key 时互不覆盖。
int _tmpSeq = 0;

Future<void> writeCacheEntry(String key, String content) async {
  final dir = _dir;
  if (dir == null) return;
  final target = '${dir.path}${Platform.pathSeparator}$key.json';
  // 先写临时文件再 rename：桌面端子窗口是独立进程，和主窗口共用同一个缓存目录，
  // 就地覆写会让并发写留下半截文件（读侧只能整条丢弃，表现为「偶发读不到缓存」）。
  // flush:true 是必须的 —— 移动端进程随时可能被系统回收，留在页缓存里没落盘的
  // 内容会跟着一起没，那正是「上次明明看过、断网却没有」的成因之一。
  final tmp = File('$target.${pid}_${_tmpSeq++}.tmp');
  try {
    await tmp.writeAsString(content, flush: true);
    try {
      await tmp.rename(target);
    } catch (_) {
      // Windows 上 rename 到已存在的路径可能失败，退回「先删后改名」
      final old = File(target);
      if (await old.exists()) await old.delete();
      await tmp.rename(target);
    }
  } catch (e) {
    debugPrint('[ApiCache] 写入失败 key=$key: $e');
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }
}

Future<void> deleteCacheEntry(String key) async {
  try {
    final f = _fileOf(key);
    if (f != null && await f.exists()) await f.delete();
  } catch (_) {}
}

/// 清理缓存：先按 mtime 删过期的，再按总量上限从最旧的开始删。
/// 用 mtime 而非解析 JSON 里的 savedAt，省去逐条读文件的开销。
Future<void> pruneCacheStorage(Duration maxAge, {int? maxTotalBytes}) async {
  final dir = _dir;
  if (dir == null) return;
  try {
    final now = DateTime.now();
    var removed = 0;
    final alive = <({File file, DateTime modified, int size})>[];

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        // 写入中途崩溃留下的临时文件，一律清掉
        if (entity.path.endsWith('.tmp')) {
          await entity.delete();
          removed++;
          continue;
        }
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          await entity.delete();
          removed++;
          continue;
        }
        alive.add((file: entity, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }

    if (maxTotalBytes != null) {
      var total = alive.fold<int>(0, (sum, e) => sum + e.size);
      if (total > maxTotalBytes) {
        // 最旧的先删，保住最近看过的
        alive.sort((a, b) => a.modified.compareTo(b.modified));
        for (final e in alive) {
          if (total <= maxTotalBytes) break;
          try {
            await e.file.delete();
            total -= e.size;
            removed++;
          } catch (_) {}
        }
      }
    }

    if (removed > 0) debugPrint('[ApiCache] 清理缓存 $removed 条');
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
