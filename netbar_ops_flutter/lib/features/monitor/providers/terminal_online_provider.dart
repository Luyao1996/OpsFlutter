import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/task_ws_provider.dart';
import '../data/terminal_models.dart';

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

/// 终端上下机【原始事件流】：按网吧 id（family 参数）持续订阅后端推送。
///
/// - family(merchantId)：主窗口传当前网吧 id、独立子窗口传自己的 netbarId，
///   互不依赖全局"当前网吧"，各窗口独立订阅。
/// - 无监听者时自动 dispose → 取消订阅（autoDispose）。
/// - 底层 [TaskWs.subscribeHolding] 负责：1 分钟心跳保活 + 断线自动重订阅，
///   流不中断、对本 provider 透明。
final terminalOnlineStreamProvider = StreamProvider.autoDispose
    .family<TerminalOnlineEvent, int>((ref, merchantId) {
  final ws = ref.watch(taskWsProvider);
  return ws
      .subscribeHolding(
        event: 'reg.subscribe',
        merchantId: merchantId,
        data: const {'type': 'terminal'},
        // cancelEvent: 'reg.unsubscribe', // 后端若需显式退订帧再放开
      )
      .map(TerminalOnlineEvent.fromFrame);
});

/// 终端在线状态【聚合视图】：`seat → 最新上下机事件`，按网吧 id 隔离。
///
/// 监听 [terminalOnlineStreamProvider] 增量更新。UI 直接 watch 本 provider
/// 拿到该网吧的座位在线增量；与 HTTP 快照的合并用 [mergeTerminalStatus]。
final terminalOnlineMapProvider = StateNotifierProvider.autoDispose.family<
    TerminalOnlineNotifier,
    Map<String, TerminalOnlineEvent>,
    int>((ref, merchantId) {
  final notifier = TerminalOnlineNotifier();
  final sub = ref.listen<AsyncValue<TerminalOnlineEvent>>(
    terminalOnlineStreamProvider(merchantId),
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
}

/// 把 WS 上下机增量合并进 HTTP 快照的 [Terminal.status]。
///
/// - [e] == null（该座位无推送）→ 原样，沿用 HTTP 快照状态，天然无需 seed
/// - 推送离线 → status 置 0
/// - 推送在线 → 保留 busy(2，远程中) 三态不降级；否则置 1
/// 状态未变化时返回原实例，避免无谓重建。
Terminal mergeTerminalStatus(Terminal t, TerminalOnlineEvent? e) {
  if (e == null) return t;
  if (!e.online) return t.status == 0 ? t : t.copyWith(status: 0);
  if (t.status == 2) return t;
  return t.status == 1 ? t : t.copyWith(status: 1);
}
