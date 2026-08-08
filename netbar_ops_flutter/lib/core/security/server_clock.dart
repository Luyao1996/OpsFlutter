import 'dart:async';

import 'package:flutter/foundation.dart';

import '../storage/token_store.dart';

/// 服务端时钟偏移，供离线 TOTP 计算补偿本机时钟。
///
/// TOTP 是纯时间函数：离线时本机时钟若偏出容错窗（内置种子 ±120s），算出的码
/// 一定是错的，而且用户完全看不出错在哪。因此在线时持续用响应的 `Date` 头校准，
/// 离线时用最后一次记下的偏移量补偿。
class ServerClock {
  static final ServerClock instance = ServerClock._();
  ServerClock._();

  static const String _key = 'server_clock_offset_ms';

  /// 偏移变化超过这个幅度才写盘。`Date` 头精度只有秒，又含一个 RTT 的误差，
  /// 几秒内的抖动属正常，不值得每个响应都落一次盘。
  static const int _persistThresholdMs = 2000;

  /// 服务端时间 − 本机时间（毫秒）。
  int _offsetMs = 0;
  int get offsetMs => _offsetMs;

  /// 上次校准的本机时刻（毫秒），0 表示本次安装从未校准过。
  int _syncedAt = 0;
  bool get hasSynced => _syncedAt > 0;

  /// 从本地恢复上次的偏移量。在 main() 中于 TokenStore.init() 之后调用。
  void init() {
    final raw = TokenStore.getString(_key);
    if (raw == null) return;
    final v = int.tryParse(raw);
    if (v == null) return;
    _offsetMs = v;
    _syncedAt = 1; // 非 0 即可：表示有一个从上次会话继承来的偏移
    debugPrint('[ServerClock] 恢复时钟偏移: ${v}ms');
  }

  /// 用服务端时间校准。[serverTime] 取自 HTTP 响应的 `Date` 头。
  void syncFrom(DateTime serverTime) {
    final localMs = DateTime.now().millisecondsSinceEpoch;
    final offset = serverTime.millisecondsSinceEpoch - localMs;
    final changed = (offset - _offsetMs).abs() > _persistThresholdMs;
    _offsetMs = offset;
    _syncedAt = localMs;
    if (changed) {
      unawaited(TokenStore.setString(_key, '$offset'));
      debugPrint('[ServerClock] 时钟偏移更新: ${offset}ms');
    }
  }

  /// 校准后的当前时间。从未校准过时退化为本机时间。
  DateTime now() =>
      DateTime.now().add(Duration(milliseconds: _offsetMs));
}

const Map<String, int> _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

final RegExp _rfc1123 = RegExp(
  r'^[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+'
  r'(\d{2}):(\d{2}):(\d{2})\s+GMT$',
);

/// 解析 HTTP `Date` 头（RFC 1123，如 `Wed, 21 Oct 2015 07:28:00 GMT`）。
///
/// 不用 dart:io 的 `HttpDate.parse`：Web 端编译不支持 dart:io。
/// 只认标准 RFC 1123 格式 —— 这是 HTTP/1.1 规定服务端必须使用的格式，
/// 解析不了就返回 null 让调用方跳过，宁可不校准也不能校歪。
DateTime? parseHttpDate(String value) {
  final m = _rfc1123.firstMatch(value.trim());
  if (m == null) return null;
  final month = _months[m.group(2)!];
  if (month == null) return null;
  try {
    return DateTime.utc(
      int.parse(m.group(3)!),
      month,
      int.parse(m.group(1)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  } catch (_) {
    return null;
  }
}
