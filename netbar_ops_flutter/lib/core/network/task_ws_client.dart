import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'task_ws.dart';
import 'ws_binary.dart';

/// 主窗口持有的真实 Peer WebSocket 单例。
///
/// 只在主窗口构造；子窗口拿到的是 [TaskWsProxy]，由 IPC 转发到这里。
class TaskWsClient implements TaskWs {
  TaskWsClient._();
  static final TaskWsClient instance = TaskWsClient._();

  /// auth.failed 回调（让 App 层跳登录页）。可选注入。
  static void Function()? onAuthFailed;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  TaskWsState _state = TaskWsState.idle;
  final StreamController<TaskWsState> _stateCtrl =
      StreamController<TaskWsState>.broadcast();

  /// id → _Pending（单次或流式）
  final Map<String, _Pending> _pending = {};

  Completer<void>? _readyWaiter;
  Timer? _reconnectTimer;
  Duration _retryDelay = const Duration(seconds: 1);
  static const Duration _maxRetryDelay = Duration(seconds: 30);
  /// 业务帧日志单字段截断阈值。
  /// 实际等同"不截断"——超过 1MB 才截，仅作异常场景兜底防止控制台 OOM。
  static const int _frameLogMaxChars = 1 << 20;
  int _seq = 0;

  // ---------- TaskWs 接口 ----------

  @override
  Stream<TaskWsState> get state => _stateCtrl.stream;

  @override
  TaskWsState get currentState => _state;

  @override
  Future<void> ensureConnected() {
    _log('INFO', 'ensure', '-',
        'called state=${_state.name} hasWaiter=${_readyWaiter != null} pending=${_pending.length}');
    if (_state == TaskWsState.ready) return Future.value();
    if (_state == TaskWsState.authFailed) {
      return Future.error(StateError('auth failed, refuse to reconnect'));
    }
    _readyWaiter ??= Completer<void>();
    if (_state == TaskWsState.idle || _state == TaskWsState.closed) {
      _connect();
    }
    return _readyWaiter!.future;
  }

  @override
  Future<dynamic> request({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureConnected();
    final id = _genId();
    final completer = Completer<dynamic>();
    final startMs = DateTime.now().millisecondsSinceEpoch;
    _pending[id] = _Pending.once(
      completer: completer,
      startMs: startMs,
      fun: fun,
      seat: seat,
      merchantId: merchantId,
      reqData: data,
    );
    _logFrame('INFO', 'send', id, {
      'fun': fun,
      'seat': seat,
      'merchant_id': merchantId,
      'data': data,
    });
    try {
      _send(_buildFrame(id, fun, seat, merchantId, data));
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      _logFrame('WARN', 'recv-timeout', id, {
        'elapsed_ms': elapsed,
        'fun': fun,
        'seat': seat,
      });
      throw TimeoutException('ws request timeout: fun=$fun seat=$seat');
    });
  }

  @override
  Future<dynamic> requestRawEvent({
    required String event,
    required Map<String, dynamic> customFields,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureConnected();
    final id = _genId();
    final completer = Completer<dynamic>();
    final startMs = DateTime.now().millisecondsSinceEpoch;
    _pending[id] = _Pending.once(
      completer: completer,
      startMs: startMs,
      fun: event, // 复用 fun 字段记日志（语义=event）
      seat: '', // 裸帧无 seat
      merchantId: customFields['merchant_id'] is int
          ? customFields['merchant_id'] as int
          : 0,
      reqData: customFields,
    );
    final frame = <String, dynamic>{
      'event': event,
      'id': id,
      ...customFields,
    };
    _logFrame('INFO', 'send-event', id, {
      'event': event,
      'fields': customFields,
    });
    try {
      _send(frame);
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      _logFrame('WARN', 'recv-timeout', id, {
        'elapsed_ms': elapsed,
        'event': event,
      });
      throw TimeoutException('ws requestRawEvent timeout: event=$event');
    });
  }

  @override
  Stream<dynamic> requestStream({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  }) {
    final id = sessionId ?? _genId();
    final startMs = DateTime.now().millisecondsSinceEpoch;
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>(
      onCancel: () {
        _pending.remove(id);
        _logFrame('INFO', 'stream-cancel', id, {
          'fun': fun,
          'seat': seat,
        });
      },
    );
    _pending[id] = _Pending.stream(
      streamCtrl: ctrl,
      startMs: startMs,
      fun: fun,
      seat: seat,
      merchantId: merchantId,
      reqData: data,
    );
    _logFrame('INFO', 'send-stream', id, {
      'fun': fun,
      'seat': seat,
      'merchant_id': merchantId,
      'data': data,
    });
    ensureConnected().then((_) {
      _send(_buildFrame(id, fun, seat, merchantId, data));
    }).catchError((Object e) {
      if (!ctrl.isClosed) {
        ctrl.addError(e);
        ctrl.close();
      }
      _pending.remove(id);
    });
    return ctrl.stream;
  }

  @override
  Future<void> fireAndForget({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    String? sessionId,
  }) async {
    await ensureConnected();
    final id = sessionId ?? _genId();
    _logFrame('INFO', 'send-ff', id, {
      'fun': fun,
      'seat': seat,
      'merchant_id': merchantId,
      'data': data,
    });
    _send(_buildFrame(id, fun, seat, merchantId, data));
  }

  @override
  String generateSessionId() => _genId();

  // ---------- 内部 ----------

  String _genId() =>
      'flutter-${DateTime.now().millisecondsSinceEpoch}-${++_seq}';

  Map<String, dynamic> _buildFrame(
    String id,
    String fun,
    String seat,
    int merchantId,
    Map<String, dynamic> data,
  ) =>
      {
        'event': 'peer',
        'id': id,
        'merchant_id': merchantId,
        'data': {'fun': fun, 'seat': seat, 'data': data},
      };

  String _buildUrl() {
    final token = TokenStore.getToken() ?? '';
    final encodedToken = Uri.encodeComponent(token);
    if (kDebugMode) {
      // 开发：直连后端 WS 调试地址
      return 'ws://118.123.99.244:9502/whatever?token=$encodedToken';
    }
    // 生产：与 AppConfig.baseUrl 同源
    final base = Uri.parse(AppConfig.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final hostPort = base.hasPort ? '${base.host}:${base.port}' : base.host;
    return '$scheme://$hostPort/whatever?token=$encodedToken';
  }

  void _connect() {
    if (_state == TaskWsState.connecting ||
        _state == TaskWsState.awaitingReady ||
        _state == TaskWsState.ready) {
      _log('WARN', 'connect', '-',
          'skip_connect already_in_progress state=${_state.name}');
      return;
    }
    _setState(TaskWsState.connecting);
    final url = _buildUrl();
    final tokenLen = (TokenStore.getToken() ?? '').length;
    _log('INFO', 'connect', '-',
        'connecting url=${_redactToken(url)} token_len=$tokenLen state=${_state.name}');
    try {
      final channel = WebSocketChannel.connect(Uri.parse(url));
      _channel = channel;
      _setState(TaskWsState.awaitingReady);

      // 底层 WS 握手成功/失败：能区分"握手就失败"和"握手成功但 peer.ready 不来"
      channel.ready.then((_) {
        _log('INFO', 'connect', '-',
            'ws_handshake_ok, waiting peer.ready');
      }).catchError((Object e, StackTrace s) {
        _log('ERROR', 'connect', '-',
            'ws_handshake_failed: type=${e.runtimeType} msg=$e\n${_topStack(s)}');
      });

      _channelSub = channel.stream.listen(
        _onMessage,
        onError: (Object e, StackTrace s) {
          _log('ERROR', 'stream', '-',
              'stream_error: type=${e.runtimeType} msg=$e\n${_topStack(s)}');
          _onClose('stream_error: $e');
        },
        onDone: () {
          final closeCode = channel.closeCode;
          final closeReason = channel.closeReason;
          _log('WARN', 'stream', '-',
              'stream_done closeCode=$closeCode closeReason=$closeReason');
          _onClose('done code=$closeCode reason=$closeReason');
        },
        cancelOnError: false,
      );
    } catch (e, s) {
      _log('ERROR', 'connect', '-',
          'connect_threw: type=${e.runtimeType} msg=$e\n${_topStack(s)}');
      _scheduleReconnect();
    }
  }

  /// 取 stackTrace 前 5 行，避免日志被一整堆栈刷屏
  String _topStack(StackTrace s) {
    final lines = s.toString().split('\n');
    final n = lines.length > 5 ? 5 : lines.length;
    return lines.take(n).join('\n');
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      // 二进制帧（wsbin）：thumbnail 等截图响应走此路径
      if (raw is List<int>) {
        _onBinaryFrame(raw is Uint8List ? raw : Uint8List.fromList(raw));
        return;
      }
      _log('WARN', 'recv-raw', '-',
          'non_string_msg type=${raw.runtimeType}');
      return;
    }
    // 完整打印 raw 消息体（不截断），便于联调时排查协议异常
    _log('INFO', 'recv-raw', '-', raw);
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _log('WARN', 'recv-raw', '-',
            'non_map_decoded type=${decoded.runtimeType}');
        return;
      }
      msg = Map<String, dynamic>.from(decoded);
    } catch (e) {
      _log('ERROR', 'recv-raw', '-', 'json_decode_failed: $e');
      return;
    }

    final event = msg['event'];

    if (event == 'peer.ready') {
      _setState(TaskWsState.ready);
      _retryDelay = const Duration(seconds: 1);
      final waiter = _readyWaiter;
      _readyWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      _log('INFO', 'ready', '-', 'peer.ready received');
      return;
    }

    if (event == 'auth.failed') {
      final dataMap = msg['data'];
      final reason = (dataMap is Map
              ? (dataMap['message'] ?? dataMap['msg'])
              : null) ??
          'auth failed';
      _log('ERROR', 'auth', '-', 'auth_failed: $reason');
      _setState(TaskWsState.authFailed);
      _failAllPending('auth failed: $reason');
      _closeChannel();
      try {
        onAuthFailed?.call();
      } catch (_) {}
      return;
    }

    // 业务响应：剥外壳
    Map<String, dynamic> payload = msg;
    if (event == 'peer' && msg['data'] is Map) {
      payload = Map<String, dynamic>.from(msg['data'] as Map);
    }
    final id = (payload['id'] ?? msg['id'])?.toString();
    if (id == null) return;
    final entry = _pending[id];
    if (entry == null) {
      // 找不到对应 pending：可能是重连漂帧、协议异常或服务端按 cmdlogin 主流推回的子帧
      _logFrame('WARN', 'recv-orphan', id, {'payload': payload});
      return;
    }
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - entry.startMs;

    if (entry.isStream) {
      final ctrl = entry.streamCtrl!;
      if (!ctrl.isClosed) ctrl.add(payload);
      if (_isStreamEnd(payload)) {
        _logFrame('INFO', 'recv-end', id, {
          'elapsed_ms': elapsed,
          'fun': entry.fun,
          'seat': entry.seat,
          'merchant_id': entry.merchantId,
          'reason': 'cmdlogon',
          'payload': payload,
        });
        if (!ctrl.isClosed) ctrl.close();
        _pending.remove(id);
      } else {
        _logFrame('INFO', 'recv-chunk', id, {
          'elapsed_ms': elapsed,
          'fun': entry.fun,
          'seat': entry.seat,
          'merchant_id': entry.merchantId,
          'chunk': payload,
        });
      }
    } else {
      _logFrame('INFO', 'recv', id, {
        'elapsed_ms': elapsed,
        'fun': entry.fun,
        'seat': entry.seat,
        'merchant_id': entry.merchantId,
        'req': entry.reqData,
        'resp': payload,
      });
      final c = entry.completer!;
      if (!c.isCompleted) c.complete(payload);
      _pending.remove(id);
    }
  }

  /// 处理 wsbin 二进制帧（thumbnail 等截图响应）。
  ///
  /// 按 [WsBinaryFrame.id] 关联 [_pending]，命中后以原始字节
  /// 完成对应 Completer（流式则推到流上并结束）。
  /// ⚠️ 日志只打 event/id/size，绝不把图片字节喂给 [_logFrame]（会序列化整张图刷屏）。
  void _onBinaryFrame(Uint8List bytes) {
    final frame = WsBinary.parse(bytes);
    if (frame == null) {
      _log('WARN', 'recv-bin', '-', 'parse_failed size=${bytes.length}');
      return;
    }
    final id = frame.id;
    final entry = _pending[id];
    if (entry == null) {
      _log('WARN', 'recv-bin-orphan', id,
          'event=${frame.event} size=${frame.data.length}');
      return;
    }
    final elapsed = DateTime.now().millisecondsSinceEpoch - entry.startMs;
    _log('INFO', 'recv-bin', id,
        'event=${frame.event} fun=${entry.fun} seat=${entry.seat} '
        'merchant_id=${entry.merchantId} elapsed_ms=$elapsed '
        'size=${frame.data.length}');
    if (entry.isStream) {
      final ctrl = entry.streamCtrl!;
      if (!ctrl.isClosed) {
        ctrl.add(frame.data);
        ctrl.close();
      }
      _pending.remove(id);
    } else {
      final c = entry.completer!;
      if (!c.isCompleted) c.complete(frame.data);
      _pending.remove(id);
    }
  }

  /// 流终止信号：服务端推 `cmdlogon` 且 code==0（注销成功）。
  /// 参考：toolboxPage `XtermCmdDialog.vue:1058-1066`。
  bool _isStreamEnd(Map<String, dynamic> payload) {
    final fun = payload['fun'];
    final code = payload['code'];
    if (fun == 'cmdlogon' && (code == 0 || code == '0')) return true;
    return false;
  }

  void _onClose(String reason) {
    _log('WARN', 'close', '-', 'reason=$reason');
    _closeChannel();
    if (_state == TaskWsState.authFailed) {
      // auth.failed 已处理，不重连
      return;
    }
    _setState(TaskWsState.closed);
    _failAllPending('ws closed: $reason');
    _scheduleReconnect();
  }

  void _closeChannel() {
    try {
      _channelSub?.cancel();
    } catch (_) {}
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = _retryDelay;
    _log('INFO', 'reconnect', '-', 'delay=${delay.inMilliseconds}ms');
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
    _retryDelay = Duration(
      milliseconds: (_retryDelay.inMilliseconds * 2)
          .clamp(1000, _maxRetryDelay.inMilliseconds),
    );
  }

  void _send(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null || _state != TaskWsState.ready) {
      throw StateError('ws not ready (state=$_state)');
    }
    final encoded = jsonEncode(payload);
    // 完整发送帧体（与 recv-raw 对称），便于联调时核对 merchant_id 等顶层字段
    _log('INFO', 'send-raw', '-', encoded);
    ch.sink.add(encoded);
  }

  void _setState(TaskWsState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  void _failAllPending(String reason) {
    if (_pending.isEmpty) return;
    final entries = List.of(_pending.entries);
    _pending.clear();
    final err = StateError(reason);
    for (final e in entries) {
      final p = e.value;
      if (p.isStream) {
        final c = p.streamCtrl!;
        if (!c.isClosed) {
          c.addError(err);
          c.close();
        }
      } else {
        final c = p.completer!;
        if (!c.isCompleted) c.completeError(err);
      }
    }
  }

  String _redactToken(String url) =>
      url.replaceAll(RegExp(r'token=[^&]*'), 'token=***');

  void _log(String level, String operType, String contextId, String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts][$level][task_ws][$operType][$contextId] $msg');
  }

  /// 业务帧日志：把 fields 拍平成 `k=v k=v ...`，单字段超 [_frameLogMaxChars] 截断。
  void _logFrame(
    String level,
    String operType,
    String reqId,
    Map<String, dynamic> fields,
  ) {
    final sb = StringBuffer();
    fields.forEach((k, v) {
      if (sb.isNotEmpty) sb.write(' ');
      sb.write('$k=${_truncForLog(_safeEncode(v))}');
    });
    _log(level, operType, reqId, sb.toString());
  }

  String _safeEncode(dynamic v) {
    if (v == null) return 'null';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();
    try {
      return jsonEncode(v);
    } catch (e) {
      return '[encode_failed:$e]';
    }
  }

  String _truncForLog(String s) {
    if (s.length <= _frameLogMaxChars) return s;
    return '${s.substring(0, _frameLogMaxChars)}...[truncated total=${s.length}]';
  }
}

/// 单次请求挂 Completer，流式请求挂 StreamController；同时携带发送元信息，
/// 用于响应到达时打印 "发送 + 响应 + 耗时 + 命令id" 配对日志。
class _Pending {
  final Completer<dynamic>? completer;
  final StreamController<dynamic>? streamCtrl;
  final int startMs;
  final String fun;
  final String seat;
  final int merchantId;
  final Map<String, dynamic> reqData;

  _Pending.once({
    required this.completer,
    required this.startMs,
    required this.fun,
    required this.seat,
    required this.merchantId,
    required this.reqData,
  }) : streamCtrl = null;

  _Pending.stream({
    required this.streamCtrl,
    required this.startMs,
    required this.fun,
    required this.seat,
    required this.merchantId,
    required this.reqData,
  }) : completer = null;

  bool get isStream => streamCtrl != null;
}
