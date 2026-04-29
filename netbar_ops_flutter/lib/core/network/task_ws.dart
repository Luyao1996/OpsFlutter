import 'dart:async';

/// Peer 任务 WebSocket 通道的状态
///
/// 状态机：
///   idle → connecting → awaitingReady → ready
///                                ↓
///                              closed → connecting (指数退避重连)
///                                ↓
///                          authFailed (终止状态，不重连)
enum TaskWsState {
  /// 未启动
  idle,

  /// 正在建立 TCP/TLS + WS 握手
  connecting,

  /// WS 已建立，正在等待服务端 push `{event:'peer.ready'}`
  awaitingReady,

  /// 通道就绪，可以收发业务帧
  ready,

  /// 已关闭，等待重连
  closed,

  /// 鉴权失败（收到 `{event:'auth.failed'}`），不再重连
  authFailed,
}

/// 全局 Peer 任务 WebSocket 通道。
///
/// 单例长连接，多路复用，主窗口一份真实实例 [TaskWsClient]，
/// 子窗口拿到的是 [TaskWsProxy]，通过 DesktopMultiWindow IPC 转发到主窗口。
///
/// 帧外壳约定：
///   请求：{event:'peer', id, merchant_id, data:{fun, seat, data}}
///   响应：{event:'peer', data:{...}}（剥一层外壳后取到业务对象）
abstract class TaskWs {
  /// 状态变化广播
  Stream<TaskWsState> get state;

  /// 当前状态（同步快照）
  TaskWsState get currentState;

  /// 确保 WS 处于 [TaskWsState.ready] 状态。
  /// 若未连接则触发懒连，已连接则立即返回。
  Future<void> ensureConnected();

  /// 单次请求/响应（剥外壳后的业务对象）。
  /// [timeout] 超时后抛 [TimeoutException]，并清理对应 pending。
  Future<dynamic> request({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  });

  /// 流式请求（CMD 长流场景）。
  /// 一次请求挂一个 StreamController，服务端推回的同 id 帧逐条推到流上。
  /// 调用方 `cancel()` 流时会向服务端撤销订阅（具体协议由实现层处理）。
  ///
  /// [sessionId] 可选：CMD 模块需要预生成 id 并在后续 fireAndForget 复用，
  /// 传入即用、否则内部自动生成（与 toolboxPage `XtermCmdDialog.vue` 的 wsSessionId 协议对齐）。
  Stream<dynamic> requestStream({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  });

  /// Fire-and-forget：发出后不等响应、不挂 Completer。
  ///
  /// 用途：CMD 模块下的 `cmdRun` / `cmdlogout` —— 服务端不会用同 id 单回，
  /// 输出会推到 `cmdlogin` 那条主流上。详见 toolboxPage `XtermCmdDialog.vue:740,786`。
  ///
  /// [sessionId] 可选：CMD 的 cmdRun/cmdlogout **必须传入与 cmdlogin 相同的 sessionId**，
  /// 否则后端找不到对应 CMD 会话，返回 `code:2 没有找到对应的CMD执行接口`。
  Future<void> fireAndForget({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  });

  /// 生成一个全局唯一的 sessionId，供 [requestStream] 与 [fireAndForget] 复用同一会话。
  /// 主窗口直接生成；子窗口走 IPC 由主窗口生成（命名空间隔离）。
  String generateSessionId();
}
