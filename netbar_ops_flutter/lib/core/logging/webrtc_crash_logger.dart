import 'dart:convert';
import 'dart:io';

/// 同步落盘的 WebRTC 崩溃定位日志。
///
/// 设计目标：在 native 崩溃（libwebrtc/msvcp140）前一定把最后若干条
/// Dart 侧的调用参数刷到磁盘。每行写入都 flushSync，保证进程意外退出
/// 时不会丢失最后一行日志。
///
/// 日志位置：{exeDir}/webrtc_logs/webrtc_YYYYMMDD.log
/// 日志格式：[ISO8601ms][LEVEL][module][operType][contextId] message
class WebRtcCrashLogger {
  WebRtcCrashLogger._();
  static final WebRtcCrashLogger I = WebRtcCrashLogger._();

  RandomAccessFile? _raf;
  String? _currentDayKey;
  String? _logDirPath;
  bool _inited = false;

  /// 单条字段最大字节数（SDP / candidate 太大时截断）。
  static const int _maxFieldBytes = 4096;

  Future<void> init() async {
    if (_inited) return;
    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final dir = Directory('${exeDir.path}${Platform.pathSeparator}webrtc_logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _logDirPath = dir.path;
      _openForToday();
      _inited = true;
      log('INFO', 'boot', 'logger_init', '-',
          'WebRtcCrashLogger initialized dir=${dir.path} pid=$pid exe=${Platform.resolvedExecutable}');
    } catch (e) {
      // 日志初始化失败不影响主流程
      // ignore: avoid_print
      print('[WebRtcCrashLogger] init failed: $e');
    }
  }

  void _openForToday() {
    final now = DateTime.now();
    final dayKey =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    if (_currentDayKey == dayKey && _raf != null) return;
    try {
      _raf?.closeSync();
    } catch (_) {}
    final path = '$_logDirPath${Platform.pathSeparator}webrtc_$dayKey.log';
    final file = File(path);
    if (!file.existsSync()) file.createSync(recursive: true);
    _raf = file.openSync(mode: FileMode.append);
    _currentDayKey = dayKey;
  }

  /// 同步写一行日志，立即 flush。
  void log(String level, String module, String op, String ctxId, String msg) {
    try {
      if (!_inited) return;
      _openForToday();
      final raf = _raf;
      if (raf == null) return;
      final ts = DateTime.now().toIso8601String();
      final line = '[$ts][$level][$module][$op][$ctxId] $msg\n';
      raf.writeStringSync(line);
      raf.flushSync();
    } catch (_) {
      // 写日志失败时不要抛，避免影响业务
    }
  }

  /// 对可能过大的字段做截断，保留头部 + 尾部提示长度。
  String truncate(String? s) {
    if (s == null) return 'null';
    final bytes = utf8.encode(s);
    if (bytes.length <= _maxFieldBytes) return s;
    final head = utf8.decode(bytes.sublist(0, _maxFieldBytes), allowMalformed: true);
    return '$head...(TRUNCATED_total=${bytes.length}B)';
  }

  /// 把任意对象转成便于人眼阅读的 JSON 字符串（不抛异常），超长自动截断。
  String jsonOrString(Object? value) {
    if (value == null) return 'null';
    try {
      return truncate(const JsonEncoder().convert(value));
    } catch (_) {
      return truncate(value.toString());
    }
  }

  void close() {
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
    _inited = false;
  }
}
