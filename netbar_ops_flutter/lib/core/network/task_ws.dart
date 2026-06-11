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

  /// 发送一条裸 event 帧（非 peer 包装），等待同 id 的响应。
  ///
  /// 帧格式：`{event, id:<auto>, ...customFields}`
  /// 适用：sys.restart 等后端约定的特殊事件（不走 peer 任务通道）。
  /// id 由实现层自动生成并写入帧顶层；customFields 不应包含 'event' 或 'id'。
  /// 服务端按 id 推回响应帧，由 recv 路由完成 Completer。
  Future<dynamic> requestRawEvent({
    required String event,
    required Map<String, dynamic> customFields,
    Duration timeout = const Duration(seconds: 15),
  });

  /// 持续订阅 + 心跳保活：发一条裸 event 注册帧后，后端按 **同 id** 持续回推，
  /// 客户端把每条回推都送到返回的流上（流永不结束，除非主动取消）。
  ///
  /// 与 [requestStream] 的区别：
  ///   - 周期性重发注册帧保活（[heartbeat] 间隔，默认 60s，即"心跳/注册"）；
  ///   - 断线后自动重注册并重启心跳，返回的流不中断；
  ///   - 按 **完整消息 id** 路由（请求 id == 响应 id，响应 event 名可与请求不同）。
  ///
  /// 协议示例（网吧终端上下机）：
  ///   发: {event:'reg.subscribe',      id:'holdon-flutter-..', merchant_id, data:{type:'terminal'}}
  ///   收: {event:'subscribe.terminal', id:'holdon-flutter-..', data:{mac,seat,online,..}}（按同 id 持续推）
  ///
  /// [event] 注册事件名（如 'reg.subscribe'）。
  /// [merchantId] 该订阅所属网吧 id，写入帧顶层 merchant_id。
  /// [data] 注册参数（如 {'type':'terminal'}）。
  /// [kind] 消息 id 类型前缀，默认 'holdon'，生成形如 `holdon-flutter-<ts>-<seq>`，
  ///        用于在日志/抓包中一眼识别"持续型"消息。
  /// [heartbeat] 心跳（重发注册帧）的周期，默认 1 分钟。
  /// [cancelEvent] 取消订阅时发送的 event 名；为空则仅本地移除、不发取消帧。
  ///
  /// 返回流元素为完整响应帧 `{event, id, data}`，调用方按 event 区分语义，
  /// 并可在监听回调中用 [fireAndForget] 回送响应/ack（"收到即响应"由业务层决定）。
  Stream<Map<String, dynamic>> subscribeHolding({
    required String event,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String kind = 'holdon',
    Duration heartbeat = const Duration(minutes: 1),
    String? cancelEvent,
  });
}
