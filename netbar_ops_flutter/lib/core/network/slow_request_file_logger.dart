import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 慢请求文件日志服务（单例）
/// 将超过阈值的 HTTP 请求完整报文写入本地文件，release 模式也生效。
/// 按天分文件：slow_http_YYYY-MM-DD.log，自动清理 7 天前的日志。
class SlowRequestFileLogger {
  static final SlowRequestFileLogger _instance = SlowRequestFileLogger._();
  static SlowRequestFileLogger get instance => _instance;
  SlowRequestFileLogger._();

  Directory? _logDir;
  bool _initialized = false;
  Completer<void>? _initCompleter;

  // 写入队列：串行写入防止并发冲突
  final List<_WriteTask> _queue = [];
  bool _writing = false;

  /// 初始化（获取日志目录），可多次调用，只执行一次
  Future<void> init() async {
    if (_initialized) return;
    // 如果已有初始化在进行，等待它完成
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      final appDir = await getApplicationSupportDirectory();
      _logDir = Directory('${appDir.path}${Platform.pathSeparator}http_logs');
      if (!_logDir!.existsSync()) {
        _logDir!.createSync(recursive: true);
      }
      _initialized = true;
      debugPrint('[SlowRequestFileLogger] 初始化成功: ${_logDir!.path}');
      _cleanOldLogs();
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[SlowRequestFileLogger] 初始化失败: $e');
      _initCompleter!.completeError(e);
    } finally {
      // 无论成功失败都重置，失败时允许下次重试
      _initCompleter = null;
    }
  }

  /// 写入一条慢请求日志
  Future<void> log(String content) async {
    final task = _WriteTask(content, Completer<void>());
    _queue.add(task);
    _processQueue();
    return task.completer.future;
  }

  void _processQueue() {
    if (_writing || _queue.isEmpty) return;
    _writing = true;
    final task = _queue.removeAt(0);
    _doWrite(task.content).then((_) {
      task.completer.complete();
    }).catchError((e) {
      debugPrint('[SlowRequestFileLogger] 写入失败: $e');
      task.completer.completeError(e);
    }).whenComplete(() {
      _writing = false;
      _processQueue();
    });
  }

  Future<void> _doWrite(String content) async {
    if (!_initialized) {
      await init();
    }
    if (_logDir == null) {
      throw StateError('日志目录未初始化');
    }

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
    final file = File('${_logDir!.path}${Platform.pathSeparator}slow_http_$dateStr.log');
    await file.writeAsString('$content\n', mode: FileMode.append, flush: true);
  }

  /// 清理 7 天前的日志文件
  void _cleanOldLogs() {
    if (_logDir == null) return;
    try {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(days: 7));
      for (final entity in _logDir!.listSync()) {
        if (entity is File && entity.path.contains('slow_http_')) {
          final stat = entity.statSync();
          if (stat.modified.isBefore(cutoff)) {
            entity.deleteSync();
          }
        }
      }
    } catch (_) {}
  }

  /// 获取日志目录路径（供外部查看）
  String? get logDirPath => _logDir?.path;

  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _WriteTask {
  final String content;
  final Completer<void> completer;
  _WriteTask(this.content, this.completer);
}
