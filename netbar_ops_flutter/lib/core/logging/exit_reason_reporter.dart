import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webrtc_crash_logger.dart';

/// L4：Android 进程异常退出原因上报。
///
/// 借助 Android 11+(API 30) 的 ActivityManager.getHistoricalProcessExitReasons，
/// 在下次启动时查询"上次进程为什么死的"（OOM / 被杀 / native 崩溃 / ANR 等），
/// 把异常退出写入 crash_logs/exit_reason_*.log，从而捕获那些 Dart 层
/// 完全没有执行机会、"崩溃后无任何日志"的场景。
///
/// 仅 Android 生效；其它平台为空操作。
const MethodChannel _channel = MethodChannel('com.netbarops/exit_reasons');

/// 已处理退出记录的水位线（时间戳 ms），避免每次启动重复写文件。
const String _watermarkKey = 'crash_last_exit_watermark_ms';

/// 视为"异常退出"的 reason 取值（对应 ApplicationExitInfo.REASON_*）。
/// 正常退出（EXIT_SELF=1 / USER_REQUESTED=10 / USER_STOPPED=11 / PACKAGE_UPDATED=16 等）不记录。
const Set<int> _abnormalReasons = {
  2, // SIGNALED
  3, // LOW_MEMORY
  4, // CRASH（应用层未捕获崩溃）
  5, // CRASH_NATIVE（原生层崩溃）
  6, // ANR
  7, // INITIALIZATION_FAILURE
  9, // EXCESSIVE_RESOURCE_USAGE
  12, // DEPENDENCY_DIED
  14, // FREEZER
};

String _reasonZh(int reason, String reasonName) {
  switch (reason) {
    case 2:
      return '被系统信号杀死(SIGNALED)';
    case 3:
      return '内存不足被系统回收(LOW_MEMORY/OOM)';
    case 4:
      return '应用层崩溃(CRASH)';
    case 5:
      return '原生层崩溃(CRASH_NATIVE)';
    case 6:
      return '无响应被杀(ANR)';
    case 7:
      return '初始化失败(INITIALIZATION_FAILURE)';
    case 9:
      return '资源占用过高被杀(EXCESSIVE_RESOURCE_USAGE)';
    case 12:
      return '依赖进程死亡(DEPENDENCY_DIED)';
    case 14:
      return '被冻结杀死(FREEZER)';
    default:
      return reasonName.isEmpty ? 'reason=$reason' : reasonName;
  }
}

Future<List<Map<String, dynamic>>> _fetchExitReasons() async {
  final raw = await _channel.invokeMethod<List<dynamic>>('getExitReasons');
  if (raw == null) return const [];
  return raw
      .whereType<Map>()
      .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

/// 启动早期调用：把上次异常退出原因写入 crash_logs/，用 watermark 去重。
Future<void> recordExitReasons() async {
  if (kIsWeb || !Platform.isAndroid) return;
  try {
    final reasons = await _fetchExitReasons();
    if (reasons.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final watermark = prefs.getInt(_watermarkKey) ?? 0;
    int maxTs = watermark;

    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}crash_logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final m in reasons) {
      final ts = (m['timestamp'] as num?)?.toInt() ?? 0;
      if (ts <= watermark) continue;
      if (ts > maxTs) maxTs = ts;
      final reason = (m['reason'] as num?)?.toInt() ?? 0;
      if (!_abnormalReasons.contains(reason)) continue;
      _writeExitLog(dir, m);
      WebRtcCrashLogger.I.log(
        'WARN',
        'exit',
        'last_exit',
        '-',
        'reason=$reason name=${m['reasonName']} desc=${m['description']}',
      );
    }

    if (maxTs > watermark) {
      await prefs.setInt(_watermarkKey, maxTs);
    }
    WebRtcCrashLogger.I.flush();
  } catch (_) {
    // 上报失败不影响主流程
  }
}

void _writeExitLog(Directory dir, Map<String, dynamic> m) {
  try {
    final tsMs = (m['timestamp'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
    final reason = (m['reason'] as num?)?.toInt() ?? 0;
    final reasonName = m['reasonName']?.toString() ?? '';
    final fname = 'exit_reason_'
        '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}'
        '_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}${dt.second.toString().padLeft(2, '0')}.log';
    final file = File('${dir.path}${Platform.pathSeparator}$fname');
    final sb = StringBuffer()
      ..writeln('=== Android 进程上次异常退出 ===')
      ..writeln('Time: $dt')
      ..writeln('Reason: $reason ($reasonName)')
      ..writeln('ReasonZh: ${_reasonZh(reason, reasonName)}')
      ..writeln('Status: ${m['status']}')
      ..writeln('Importance: ${m['importance']}')
      ..writeln('ProcessName: ${m['processName']}')
      ..writeln('Pid: ${m['pid']}')
      ..writeln('Description: ${m['description']}')
      ..writeln('')
      ..writeln('Trace:')
      ..writeln((m['trace']?.toString().isNotEmpty ?? false)
          ? m['trace'].toString()
          : '(无 trace，部分退出原因不携带 tombstone)');
    file.writeAsStringSync(sb.toString(), flush: true);
  } catch (_) {}
}

/// 供"查看崩溃日志"页置顶提示使用：返回最近一次异常退出的中文摘要；无则 null。
Future<String?> getLastAbnormalExitHint() async {
  if (kIsWeb || !Platform.isAndroid) return null;
  try {
    final reasons = await _fetchExitReasons();
    // Android 返回顺序为最近在前，取第一条异常退出。
    for (final m in reasons) {
      final reason = (m['reason'] as num?)?.toInt() ?? 0;
      if (!_abnormalReasons.contains(reason)) continue;
      final tsMs = (m['timestamp'] as num?)?.toInt() ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
      final reasonName = m['reasonName']?.toString() ?? '';
      final mStr = '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '上次异常退出：${_reasonZh(reason, reasonName)}（$mStr）';
    }
    return null;
  } catch (_) {
    return null;
  }
}
