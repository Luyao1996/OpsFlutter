import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/task_ws_provider.dart';
import '../../../shared/providers/app_providers.dart';

/// 终端上下机事件（解析自后端持续推送的 `subscribe.terminal` 帧 data）。
///
/// 后端帧示例：
///   {"event":"subscribe.terminal","id":"holdon-..","data":{
///     "mac":"00-CF-E0-59-E1-CC","seat":"VIP-127","name":"无盘服务端",
///     "ip":"10.0.0.127","version":"","ConnID":1,"mode":1,"online":1}}
class TerminalOnlineEvent {
  final String mac;
  final String seat;
  final String name;
  final String ip;
  final String version;
  final int connId;
  final int mode;
  final bool online;

  /// 原始帧 event 名（如 'subscribe.terminal'），便于上层区分语义。
  final String rawEvent;

  const TerminalOnlineEvent({
    required this.mac,
    required this.seat,
    required this.name,
    required this.ip,
    required this.version,
    required this.connId,
    required this.mode,
    required this.online,
    required this.rawEvent,
  });

  /// 从 [subscribeHolding] 推回的完整帧 `{event, id, data}` 解析。
  factory TerminalOnlineEvent.fromFrame(Map<String, dynamic> frame) {
    final data = frame['data'] is Map
        ? Map<String, dynamic>.from(frame['data'] as Map)
        : <String, dynamic>{};
    int toInt(dynamic v) => v is int
        ? v
        : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
    return TerminalOnlineEvent(
      mac: (data['mac'] ?? '').toString(),
      seat: (data['seat'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      ip: (data['ip'] ?? '').toString(),
      version: (data['version'] ?? '').toString(),
      connId: toInt(data['ConnID']),
      mode: toInt(data['mode']),
      online: toInt(data['online']) == 1,
      rawEvent: (frame['event'] ?? '').toString(),
    );
  }
}

/// 终端上下机【原始事件流】：按当前网吧 id 持续订阅后端推送。
///
/// - 随当前网吧切换自动重建（watch [currentNetbarIdProvider]）。
/// - 无监听者时自动 dispose → 取消订阅（autoDispose）。
/// - 底层 [TaskWs.subscribeHolding] 负责：1 分钟心跳保活 + 断线自动重订阅，
///   流不中断、对本 provider 透明。
final terminalOnlineStreamProvider =
    StreamProvider.autoDispose<TerminalOnlineEvent>((ref) {
  final netbarId = ref.watch(currentNetbarIdProvider);
  if (netbarId == null) return const Stream<TerminalOnlineEvent>.empty();
  final ws = ref.watch(taskWsProvider);
  return ws
      .subscribeHolding(
        event: 'reg.subscribe',
        merchantId: netbarId,
        data: const {'type': 'terminal'},
        // cancelEvent: 'reg.unsubscribe', // 后端若需显式退订帧再放开
      )
      .map(TerminalOnlineEvent.fromFrame);
});

/// 终端在线状态【聚合视图】：`seat → 最新上下机事件`。
///
/// 监听 [terminalOnlineStreamProvider] 增量更新。UI 直接 watch 本 provider
/// 即可拿到全量座位在线快照；首屏 HTTP 全量可用 [TerminalOnlineNotifier.seed] 预填。
final terminalOnlineMapProvider = StateNotifierProvider.autoDispose<
    TerminalOnlineNotifier, Map<String, TerminalOnlineEvent>>((ref) {
  final notifier = TerminalOnlineNotifier();
  final sub = ref.listen<AsyncValue<TerminalOnlineEvent>>(
    terminalOnlineStreamProvider,
    (prev, next) => next.whenData(notifier.apply),
  );
  ref.onDispose(sub.close);
  return notifier;
});

class TerminalOnlineNotifier
    extends StateNotifier<Map<String, TerminalOnlineEvent>> {
  TerminalOnlineNotifier() : super(const {});

  /// 应用一条增量上下机事件（按 seat 覆盖）。
  void apply(TerminalOnlineEvent e) {
    if (e.seat.isEmpty) return;
    state = {...state, e.seat: e};
  }

  /// 用首屏 HTTP 快照预填全量在线状态（与推送增量合并）。
  void seed(Iterable<TerminalOnlineEvent> events) {
    final next = {...state};
    for (final e in events) {
      if (e.seat.isNotEmpty) next[e.seat] = e;
    }
    state = next;
  }
}
