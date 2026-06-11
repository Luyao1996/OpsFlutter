import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'task_ws.dart';
import 'window_runtime.dart';

/// 子窗口持有的 [TaskWs] 代理：所有调用通过 DesktopMultiWindow 转发到
/// 主窗口（windowId=0）的真实 [TaskWsClient]。
///
/// 子窗口当前仅由 [TaskWsProxy] 调用 [DesktopMultiWindow.setMethodHandler]
/// （子窗口 main 入口未注册其他 handler），独占该回调，不会与他人冲突。
class TaskWsProxy implements TaskWs {
  TaskWsProxy._() {
    _initIpc();
  }
  static final TaskWsProxy instance = TaskWsProxy._();

  /// 主窗口 windowId 始终为 0（desktop_multi_window 约定）
  static const int _mainWindowId = 0;

  TaskWsState _state = TaskWsState.idle;
  final StreamController<TaskWsState> _stateCtrl =
      StreamController<TaskWsState>.broadcast();

  /// 本子窗口持有的流：reqId → 本地 StreamController
  final Map<String, StreamController<dynamic>> _streams = {};
  int _seq = 0;

  // ---------- IPC handler 注册 ----------

  void _initIpc() {
    DesktopMultiWindow.setMethodHandler(_onMethodCall);
    // 启动时主动拉一次主窗口当前状态（避免错过开窗前的 state 推送）
    Future.microtask(_pullState);
  }

  Future<dynamic> _onMethodCall(MethodCall call, int fromWindowId) async {
    final raw = call.arguments;
    final args = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    switch (call.method) {
      case 'ws/streamChunk':
        _onStreamChunk(args);
        return null;
      case 'ws/streamEnd':
        await _onStreamEnd(args);
        return null;
      case 'ws/state':
        _onStateBroadcast(args);
        return null;
    }
    return null;
  }

  void _onStreamChunk(Map<String, dynamic> args) {
    final reqId = args['reqId'] as String?;
    if (reqId == null) return;
    final ctrl = _streams[reqId];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(_deepCastFromIpc(args['data']));
  }

  Future<void> _onStreamEnd(Map<String, dynamic> args) async {
    final reqId = args['reqId'] as String?;
    if (reqId == null) return;
    final ctrl = _streams.remove(reqId);
    if (ctrl == null || ctrl.isClosed) return;
    if (args['ok'] == true) {
      await ctrl.close();
    } else {
      ctrl.addError(StateError((args['msg'] ?? 'stream error').toString()));
      await ctrl.close();
    }
  }

  void _onStateBroadcast(Map<String, dynamic> args) {
    final s = args['state'];
    if (s is String) {
      try {
        _setState(TaskWsState.values.byName(s));
      } catch (_) {}
    }
  }

  Future<void> _pullState() async {
    try {
      final r = await DesktopMultiWindow.invokeMethod(
          _mainWindowId, 'ws/getState', <String, dynamic>{});
      if (r is Map && r['state'] is String) {
        _setState(TaskWsState.values.byName(r['state'] as String));
      }
    } catch (e) {
      _log('WARN', 'pullState', '-', 'failed: $e');
    }
  }

  // ---------- TaskWs 接口（全部走 IPC） ----------

  @override
  Stream<TaskWsState> get state => _stateCtrl.stream;

  @override
  TaskWsState get currentState => _state;

  @override
  Future<void> ensureConnected() async {
    if (_state == TaskWsState.ready) return;
    if (_state == TaskWsState.authFailed) {
      throw StateError('auth failed');
    }
    final r = await DesktopMultiWindow.invokeMethod(
        _mainWindowId, 'ws/ensureConnected', <String, dynamic>{});
    if (r is Map && r['ok'] == true) {
      _setState(TaskWsState.ready);
      return;
    }
    final msg = (r is Map ? r['msg'] : 'ensureConnected failed').toString();
    throw StateError(msg);
  }

  @override
  Future<dynamic> request({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'ws/request',
      <String, dynamic>{
        'fun': fun,
        'seat': seat,
        'merchantId': merchantId,
        'data': data,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (r is Map && r['ok'] == true) return _deepCastFromIpc(r['data']);
    final msg = (r is Map ? r['msg'] : 'request failed').toString();
    throw StateError(msg);
  }

  @override
  Stream<dynamic> requestStream({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  }) {
    final reqId = _genReqId();
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>(
      onCancel: () async {
        _streams.remove(reqId);
        try {
          await DesktopMultiWindow.invokeMethod(
              _mainWindowId,
              'ws/streamCancel',
              <String, dynamic>{'reqId': reqId});
        } catch (_) {}
      },
    );
    _streams[reqId] = ctrl;
    DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'ws/streamOpen',
      <String, dynamic>{
        'reqId': reqId,
        'fun': fun,
        'seat': seat,
        'merchantId': merchantId,
        'data': data,
        if (sessionId != null) 'sessionId': sessionId,
      },
    ).catchError((Object e) {
      final c = _streams.remove(reqId);
      if (c != null && !c.isClosed) {
        c.addError(e);
        c.close();
      }
    });
    return ctrl.stream;
  }

  @override
  Stream<Map<String, dynamic>> subscribeHolding({
    required String event,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String kind = 'holdon',
    Duration heartbeat = const Duration(minutes: 1),
    String? cancelEvent,
  }) {
    // 心跳 timer 与订阅注册表都在主窗口 TaskWsClient 托管；
    // 子窗口仅本地建流接收回推（复用 streamChunk 通道），重连恢复对子窗口透明。
    final reqId = _genReqId();
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>.broadcast(
      onCancel: () async {
        _streams.remove(reqId);
        try {
          await DesktopMultiWindow.invokeMethod(_mainWindowId,
              'ws/holdingCancel', <String, dynamic>{'reqId': reqId});
        } catch (_) {}
      },
    );
    _streams[reqId] = ctrl;
    DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'ws/holdingOpen',
      <String, dynamic>{
        'reqId': reqId,
        'event': event,
        'merchantId': merchantId,
        'data': data,
        'kind': kind,
        'heartbeatMs': heartbeat.inMilliseconds,
        if (cancelEvent != null) 'cancelEvent': cancelEvent,
      },
    ).catchError((Object e) {
      final c = _streams.remove(reqId);
      if (c != null && !c.isClosed) {
        c.addError(e);
        c.close();
      }
    });
    return ctrl.stream.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> fireAndForget({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  }) async {
    await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'ws/fireAndForget',
      <String, dynamic>{
        'fun': fun,
        'seat': seat,
        'merchantId': merchantId,
        'data': data,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
  }

  @override
  Future<dynamic> requestRawEvent({
    required String event,
    required Map<String, dynamic> customFields,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final r = await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'ws/requestRawEvent',
      <String, dynamic>{
        'event': event,
        'customFields': customFields,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (r is Map && r['ok'] == true) return _deepCastFromIpc(r['data']);
    final msg = (r is Map ? r['msg'] : 'requestRawEvent failed').toString();
    throw StateError(msg);
  }

  @override
  String generateSessionId() {
    // 子窗口本地生成 sessionId（命名空间隔离：以 windowId 前缀避免主/子窗口冲突）
    final wid = WindowRuntime.subWindowId ?? 0;
    return 'flutter-w$wid-${DateTime.now().millisecondsSinceEpoch}-${++_seq}';
  }

  // ---------- 内部 ----------

  String _genReqId() {
    final wid = WindowRuntime.subWindowId ?? 0;
    return 'w$wid-${DateTime.now().millisecondsSinceEpoch}-${++_seq}';
  }

  void _setState(TaskWsState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _log(String level, String operType, String contextId, String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts][$level][task_ws_proxy][$operType][$contextId] $msg');
  }
}

/// 把 IPC 边界拿到的 Map/List 深度递归转成 `Map<String, dynamic>` / `List<dynamic>`。
///
/// 背景：`DesktopMultiWindow.invokeMethod` 走 Flutter platform channel
/// (`StandardMessageCodec`)，序列化往返后 `Map<String, dynamic>` 会被降级为
/// `Map<Object?, Object?>`，`List<dynamic>` 被降级为 `List<Object?>`。
/// 调用方常见的 `if (x is Map<String, dynamic>)` 类型断言对降级后的 Map
/// **永远 false**，导致 hwinfo / fileList / processTree 等业务字段全部丢失。
/// 在 IPC 边界做一次深度归一，所有消费方零侵入。
dynamic _deepCastFromIpc(dynamic v) {
  // 图片等二进制字节（wsbin thumbnail 经 IPC 回传）：Uint8List is List<int> 为 true，
  // 必须在 List 分支之前原样放行，否则会被下方 v.map(...).toList() 降级成普通
  // List<int>，导致 Image.memory 无法接收、图片字节被破坏。
  if (v is Uint8List) return v;
  if (v is Map) {
    final result = <String, dynamic>{};
    v.forEach((k, val) => result[k.toString()] = _deepCastFromIpc(val));
    return result;
  }
  if (v is List) {
    return v.map(_deepCastFromIpc).toList();
  }
  return v;
}
