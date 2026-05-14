/// 格式化字节数（B/KB/MB/GB/TB），与 Web 端 formatBytes 行为一致
String formatBytes(num? bytes) {
  if (bytes == null) return '—';
  final n = bytes.toDouble();
  if (!n.isFinite || n <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var v = n;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final fraction = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(fraction)}${units[i]}';
}

/// 格式化下载速度
String formatSpeed(num? bytesPerSec) {
  if (bytesPerSec == null || bytesPerSec == 0) return '0KB/s';
  return '${formatBytes(bytesPerSec)}/s';
}

/// 格式化剩余时间（毫秒 -> mm:ss / hh:mm:ss）
String formatEta(num? ms) {
  if (ms == null || ms <= 0) return '—';
  final totalSec = (ms / 1000).floor();
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '${pad(h)}:${pad(m)}:${pad(s)}' : '${pad(m)}:${pad(s)}';
}

/// 格式化 Unix 秒 -> YYYY-MM-DD HH:mm:ss
String formatUnix(num? sec) {
  if (sec == null || sec <= 0) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${pad(d.month)}-${pad(d.day)} '
      '${pad(d.hour)}:${pad(d.minute)}:${pad(d.second)}';
}

/// 健康提示"陈旧 X 时间前"
String formatStale(String? rfc3339) {
  if (rfc3339 == null || rfc3339.isEmpty) return '';
  final t = DateTime.tryParse(rfc3339);
  if (t == null) return '';
  // 过滤明显非法时间戳（< 2000 年）
  if (t.isBefore(DateTime.utc(2000))) return '';
  final sec = DateTime.now().difference(t).inSeconds;
  if (sec < 0) return '';
  if (sec < 60) return '$sec 秒前';
  if (sec < 3600) return '${sec ~/ 60} 分钟前';
  if (sec < 86400) return '${sec ~/ 3600} 小时前';
  return '${sec ~/ 86400} 天前';
}

/// HTTP 错误信息归一化（对照 Web 端 httpErrorMessage）
String httpErrorMessage(int status, String? rawError) {
  if (status == 0) return rawError ?? '网络请求失败';
  if (status == 400) return '参数错误（${rawError ?? 'bad request'}）';
  if (status == 404) return '接口不存在（请确认后端版本）';
  if (status == 405) return '方法不允许';
  if (status == 500) {
    return (rawError != null && rawError.isNotEmpty)
        ? '服务器内部错误：$rawError'
        : '服务器内部错误';
  }
  if (status == 503) return '平台未启用，请检查 /game_library/config 配置';
  if (status == 504) return '服务繁忙，worker 15s 未响应';
  return rawError != null && rawError.isNotEmpty ? rawError : 'HTTP $status';
}

/// 写接口 result 字段 -> 友好文案
String formatOpResultMessage(String? result) {
  if (result == null || result.isEmpty) return '未知错误';
  if (result == 'err: not connected') return '平台连接断开';
  if (result == 'platform_stopped') return '平台 worker 已停止';
  if (result.startsWith('err:')) {
    return result.replaceFirst(RegExp(r'^err:\s*'), '');
  }
  return result;
}
