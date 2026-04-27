# WebSocket 升级改动方案（详细）

> 配套文档：`docs/WebSocket升级接口改动清单.md`
>
> ⚠️ **进程管理（getProcesses/getProcessTree/killProcess）和文件管理（getFiles/downloadFile）保持原 frp HTTP 不动**。因此 `terminal_api.dart` 中的 `_netbarGet/_netbarPost/_buildUrl/_createProxiedDio` 这套底座**不能整体删除**，要继续给这两类接口使用。

## 目录
- [0. 基础设施（前置依赖）](#0-基础设施前置依赖)
- [A. 改走 WebSocket 的接口（替换 POST {domain}/api/task）](#a-改走-websocket-的接口替换-post-domainapitask)
- [B. CMD 长流（替换 ws://{domain}/ws_client）](#b-cmd-长流替换-wsdomainws_client)
- [C. 路由器迁移到中央 HTTP](#c-路由器迁移到中央-http替换-httpsrouter-hostapi)
- [D. 座位列表迁移到中央 HTTP](#d-座位列表迁移到中央-http替换-httpsdomainapiseatlist)
- [E. 操作日志埋点（新增）](#e-操作日志埋点新增)
- [F. 不动刀的部分（明确保留）](#f-不动刀的部分明确保留)
- [G. 调用方梳理](#g-调用方梳理删除-domain-参数--加-merchantid-参数)

---

## 0. 基础设施（前置依赖）

### 0.1 抽象接口 `TaskWs`

**新建** `lib/core/network/task_ws.dart`

```dart
enum TaskWsState { idle, connecting, awaitingReady, ready, closed, authFailed }

abstract class TaskWs {
  Stream<TaskWsState> get state;
  TaskWsState get currentState;
  Future<void> ensureConnected();

  /// 单次请求/响应（剥外壳后的业务对象）
  Future<dynamic> request({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  });

  /// 流式请求（CMD 等长输出场景）
  Stream<dynamic> requestStream({
    required String fun,
    required String seat,
    required int merchantId,
    Map<String, dynamic> data = const {},
  });
}
```

### 0.2 主窗口实现 `TaskWsClient`

**新建** `lib/core/network/task_ws_client.dart`

```dart
class TaskWsClient implements TaskWs {
  static final instance = TaskWsClient._();
  TaskWsClient._();

  WebSocket? _ws;
  TaskWsState _state = TaskWsState.idle;
  final _stateCtrl = StreamController<TaskWsState>.broadcast();
  Completer<void>? _readyWaiter;
  int _seq = 0;
  Duration _retryDelay = const Duration(seconds: 1);

  // id → Completer / StreamController
  final _pending = <String, _Pending>{};

  String _genId() =>
      'flutter-${DateTime.now().millisecondsSinceEpoch}-${++_seq}';

  String _buildUrl() {
    final token = TokenStore.getToken() ?? '';
    if (kDebugMode) {
      return 'ws://118.123.99.244:9502/whatever?token=$token';
    }
    final host = Uri.parse(AppConfig.baseUrl).host;
    return 'wss://$host/whatever?token=$token';
  }

  @override
  Future<void> ensureConnected() async {
    if (_state == TaskWsState.ready) return;
    _readyWaiter ??= Completer<void>();
    if (_state == TaskWsState.idle || _state == TaskWsState.closed) {
      _connect();
    }
    return _readyWaiter!.future;
  }

  void _connect() async {
    _setState(TaskWsState.connecting);
    try {
      _ws = await WebSocket.connect(_buildUrl());
      _setState(TaskWsState.awaitingReady);
      _ws!.listen(_onMessage, onError: (_) => _onClose(), onDone: _onClose);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String);
    if (msg is! Map) return;

    if (msg['event'] == 'peer.ready') {
      _setState(TaskWsState.ready);
      _retryDelay = const Duration(seconds: 1);
      _readyWaiter?.complete();
      _readyWaiter = null;
      return;
    }
    if (msg['event'] == 'auth.failed') {
      _setState(TaskWsState.authFailed);
      _failAllPending('auth failed');
      _ws?.close();
      // 不重连，触发外层登出
      return;
    }

    // 业务响应：剥外壳
    Map payload = msg;
    if (msg['event'] == 'peer' && msg['data'] is Map) {
      payload = msg['data'] as Map;
    }
    final id = (payload['id'] ?? msg['id'])?.toString();
    if (id == null) return;
    final entry = _pending[id];
    if (entry == null) return;

    if (entry.isStream) {
      entry.streamCtrl!.add(payload);
      // 流终止：以后端约定为准（如收到 cmdlogout 或 closed:true）
      if (_isStreamEnd(payload)) {
        entry.streamCtrl!.close();
        _pending.remove(id);
      }
    } else {
      entry.completer!.complete(payload);
      _pending.remove(id);
    }
  }

  void _onClose() {
    _setState(TaskWsState.closed);
    _failAllPending('ws closed');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    Future.delayed(_retryDelay, _connect);
    _retryDelay = Duration(
      milliseconds: (_retryDelay.inMilliseconds * 2).clamp(1000, 30000),
    );
  }

  void _send(Map<String, dynamic> payload) {
    if (_state != TaskWsState.ready) throw StateError('ws not ready');
    _ws!.add(jsonEncode(payload));
  }

  @override
  Future<dynamic> request({
    required String fun, required String seat, required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    await ensureConnected();
    final id = _genId();
    final c = Completer<dynamic>();
    _pending[id] = _Pending.once(c);
    _send({
      'event': 'peer', 'id': id, 'merchant_id': merchantId,
      'data': {'fun': fun, 'seat': seat, 'data': data},
    });
    return c.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('ws request timeout: $fun');
    });
  }

  @override
  Stream<dynamic> requestStream({
    required String fun, required String seat, required int merchantId,
    Map<String, dynamic> data = const {},
  }) {
    final id = _genId();
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>(
      onCancel: () => _pending.remove(id),
    );
    _pending[id] = _Pending.stream(ctrl);
    ensureConnected().then((_) {
      _send({
        'event': 'peer', 'id': id, 'merchant_id': merchantId,
        'data': {'fun': fun, 'seat': seat, 'data': data},
      });
    }).catchError((e) {
      ctrl.addError(e); ctrl.close();
    });
    return ctrl.stream;
  }

  // ... _setState / _failAllPending / _isStreamEnd 略
}

class _Pending {
  final Completer? completer;
  final StreamController? streamCtrl;
  _Pending.once(this.completer) : streamCtrl = null;
  _Pending.stream(this.streamCtrl) : completer = null;
  bool get isStream => streamCtrl != null;
}
```

### 0.3 主窗口 IPC 注册 `TaskWsHost`

**修改** `lib/shared/services/terminal_window_bridge_desktop.dart:25 setMethodHandler` 内追加 case：

```dart
DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
  // ... 现有 terminal_minimize / terminal_close / terminal_tab_changed 保留 ...

  switch (call.method) {
    case 'ws/request': {
      final a = Map<String, dynamic>.from(call.arguments);
      try {
        final result = await TaskWsClient.instance.request(
          fun: a['fun'], seat: a['seat'],
          merchantId: a['merchantId'],
          data: Map<String, dynamic>.from(a['data'] ?? {}),
          timeout: Duration(milliseconds: a['timeout'] ?? 15000),
        );
        return {'ok': true, 'data': result};
      } catch (e) {
        return {'ok': false, 'msg': e.toString()};
      }
    }
    case 'ws/streamOpen': {
      final a = Map<String, dynamic>.from(call.arguments);
      final reqId = a['reqId'] as String;
      _hostStreams[reqId] = TaskWsClient.instance.requestStream(
        fun: a['fun'], seat: a['seat'],
        merchantId: a['merchantId'],
        data: Map<String, dynamic>.from(a['data'] ?? {}),
      ).listen(
        (chunk) => DesktopMultiWindow.invokeMethod(
            fromWindowId, 'ws/streamChunk', {'reqId': reqId, 'data': chunk}),
        onError: (e) => DesktopMultiWindow.invokeMethod(fromWindowId,
            'ws/streamEnd', {'reqId': reqId, 'ok': false, 'msg': '$e'}),
        onDone: () => DesktopMultiWindow.invokeMethod(
            fromWindowId, 'ws/streamEnd', {'reqId': reqId, 'ok': true}),
      );
      return {'ok': true};
    }
    case 'ws/streamCancel': {
      final reqId = (call.arguments as Map)['reqId'] as String;
      await _hostStreams.remove(reqId)?.cancel();
      return {'ok': true};
    }
    case 'ws/getState': {
      return {'state': TaskWsClient.instance.currentState.name};
    }
  }
});

// WS 状态广播到所有子窗口
TaskWsClient.instance.state.listen((s) async {
  final ids = await DesktopMultiWindow.getAllSubWindowIds();
  for (final id in ids) {
    DesktopMultiWindow.invokeMethod(id, 'ws/state', {'state': s.name});
  }
});

// 子窗口关闭时清理它的所有 stream（在现有 terminal_close case 内追加）
case 'terminal_close':
  // ... 原逻辑 ...
  _hostStreams.removeWhere((reqId, sub) {
    if (reqId.startsWith('w$fromWindowId-')) {
      sub.cancel(); return true;
    }
    return false;
  });
```

### 0.4 子窗口代理 `TaskWsProxy`

**新建** `lib/core/network/task_ws_proxy.dart`

```dart
class TaskWsProxy implements TaskWs {
  static final instance = TaskWsProxy._();
  late int _myWindowId;        // 子窗口启动时由 payload 传入
  int _seq = 0;
  TaskWsState _state = TaskWsState.idle;
  final _stateCtrl = StreamController<TaskWsState>.broadcast();
  final _streams = <String, StreamController<dynamic>>{};

  TaskWsProxy._() {
    DesktopMultiWindow.setMethodHandler((call, _) async {
      final a = Map<String, dynamic>.from(call.arguments);
      switch (call.method) {
        case 'ws/streamChunk':
          _streams[a['reqId']]?.add(a['data']);
          return null;
        case 'ws/streamEnd':
          final ctrl = _streams.remove(a['reqId']);
          if (a['ok'] == true) {
            await ctrl?.close();
          } else {
            ctrl?.addError(Exception(a['msg'] ?? 'stream error'));
            await ctrl?.close();
          }
          return null;
        case 'ws/state':
          _state = TaskWsState.values.byName(a['state']);
          _stateCtrl.add(_state);
          return null;
      }
    });
    // 启动后同步主窗口当前状态
    Future.microtask(() async {
      final r = await DesktopMultiWindow.invokeMethod(0, 'ws/getState', {});
      _state = TaskWsState.values.byName(r['state']);
      _stateCtrl.add(_state);
    });
  }

  String _genReqId() => 'w$_myWindowId-${++_seq}';

  @override
  Future<dynamic> request({
    required String fun, required String seat, required int merchantId,
    Map<String, dynamic> data = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final reqId = _genReqId();
    final res = await DesktopMultiWindow.invokeMethod(0, 'ws/request', {
      'reqId': reqId, 'fun': fun, 'seat': seat,
      'merchantId': merchantId, 'data': data,
      'timeout': timeout.inMilliseconds,
    });
    if (res['ok'] == true) return res['data'];
    throw Exception(res['msg']);
  }

  @override
  Stream<dynamic> requestStream({
    required String fun, required String seat, required int merchantId,
    Map<String, dynamic> data = const {},
  }) {
    final reqId = _genReqId();
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>(
      onCancel: () async {
        _streams.remove(reqId);
        try {
          await DesktopMultiWindow.invokeMethod(
              0, 'ws/streamCancel', {'reqId': reqId});
        } catch (_) {}
      },
    );
    _streams[reqId] = ctrl;
    DesktopMultiWindow.invokeMethod(0, 'ws/streamOpen', {
      'reqId': reqId, 'fun': fun, 'seat': seat,
      'merchantId': merchantId, 'data': data,
    });
    return ctrl.stream;
  }

  @override
  Future<void> ensureConnected() async {
    if (_state == TaskWsState.ready) return;
    final c = Completer<void>();
    final sub = _stateCtrl.stream.listen((s) {
      if (s == TaskWsState.ready && !c.isCompleted) c.complete();
    });
    await c.future;
    await sub.cancel();
  }
}
```

### 0.5 Provider 注入

**新建** `lib/core/network/task_ws_provider.dart`

```dart
final taskWsProvider = Provider<TaskWs>((ref) {
  // isMainWindow 由 main.dart 启动时根据是否有 windowId 参数判定
  return WindowRuntime.isMainWindow
      ? TaskWsClient.instance
      : TaskWsProxy.instance;
});

final taskWsStateProvider = StreamProvider<TaskWsState>(
  (ref) => ref.watch(taskWsProvider).state,
);
```

**修改** `terminal_window_bridge_desktop.dart:99-109` payload 增加 `myWindowId`：

```dart
final controller = await DesktopMultiWindow.createWindow(payload);
// 创建后立即把 windowId 发回子窗口（子窗口 main 接收并初始化 TaskWsProxy._myWindowId）
await DesktopMultiWindow.invokeMethod(
    controller.windowId, 'init/myWindowId', {'windowId': controller.windowId});
```

---

## A. 改走 WebSocket 的接口（替换 `POST {domain}/api/task`）

> ⚠️ 进程列表 / 进程树 / 结束进程 / 文件列表 / 文件下载 **不动**。

### A.1 远程连接 / 断开

**修改** `lib/features/monitor/data/terminal_api.dart:218 remote()`

改动前：
```dart
Future<Map<String, dynamic>> remote(String seatId, String action,
    {required String domain, Map<String, dynamic>? user}) async {
  final response = await _netbarPost(domain, '/task',
      queryParameters: {'seat': seatId},
      data: {'fun': 'remote', 'data': {...}});
  return _unwrapResponse(response) is Map ? ... : {};
}
```

改动后：
```dart
class TerminalApi {
  final TaskWs _ws;
  TerminalApi(this._ws);

  Future<Map<String, dynamic>> remote(
    String seatId, String action, {
    required int merchantId,
    Map<String, dynamic>? user,
  }) async {
    final res = await _ws.request(
      fun: 'remote', seat: seatId, merchantId: merchantId,
      data: {
        'enable': action != 'disconnect',
        'type': action == 'disconnect' ? null : action,
        if (user != null) 'user': user,
      },
    );
    if (res['code'] != 0) {
      throw ApiError(code: res['code'], message: res['msg'] ?? '远程失败');
    }
    final data = res['data'];
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }
}
```

**调用方修改**：
- `terminal_detail_page.dart:320,1641,1506-1522`：去掉 `domain:` 参数，加 `merchantId: netbar.id!`
- `monitor_page.dart:1064`：同上

### A.2 更新远端程序（**新增**）

**新增** 方法：

```dart
Future<void> updateProgram(String seatId, {required int merchantId}) async {
  final res = await _ws.request(
      fun: 'update', seat: seatId, merchantId: merchantId, data: {});
  if (res['code'] != 0) throw ApiError(code: res['code'], message: res['msg']);
}
```

**调用方**：在终端详情页右键菜单或工具栏新增"更新程序"按钮（参考 Web `useRemoteAwaken.js:224`）。

### A.3 远程截图

**修改** `lib/features/desktop/data/desktop_api.dart:253 ScreenshotApi.requestScreenshot`

改动前：
```dart
Future<ScreenshotResult> requestScreenshot({required String domain, required String seatId}) async {
  // 自建 Dio → POST .../api/task body {fun:'Screenshot',data:{}}, responseType: bytes
  // 解析 contentType: JSON 走 base64/url，否则 bytes
}
```

改动后：
```dart
class ScreenshotApi {
  final TaskWs _ws;
  ScreenshotApi(this._ws);

  Future<ScreenshotResult> requestScreenshot({
    required String seatId, required int merchantId,
  }) async {
    final res = await _ws.request(
        fun: 'Screenshot', seat: seatId, merchantId: merchantId, data: {});
    if (res['code'] != 0) {
      return ScreenshotResult.error(res['msg'] ?? '截图失败');
    }
    final p = (res['data'] ?? {}) as Map;
    final base64Data = p['base64'] ?? p['image_base64'] ?? p['img_base64'];
    final imageUrl   = p['url']    ?? p['file_url']     ?? p['image_url'];
    final w = p['width'] as int?, h = p['height'] as int?;
    if (base64Data != null) return ScreenshotResult.base64(base64Data, width: w, height: h);
    if (imageUrl   != null) return ScreenshotResult.url(imageUrl,    width: w, height: h);
    return ScreenshotResult.error('截图任务已触发，但未返回图片');
  }
}
```

**调用方修改**（去掉 `domain:`，加 `merchantId:`）：
- `monitor_page.dart:240 _loadSingleScreenshot`
- `terminal_detail_page.dart:319 _fetchScreenshotOnce`
- `desktop_management_page_impl.dart:380 _requestScreenshot`

### A.4 / A.5 硬件信息

**修改** `terminal_api.dart:501 getHardwareInfo` 与 `:536 getHardwareRealtime`

```dart
Future<List<Map<String, dynamic>>> getHardwareInfo(
    String seatId, {required int merchantId}) async {
  final infoRes = await _ws.request(
      fun: 'hwinfo', seat: seatId, merchantId: merchantId,
      data: {'type': 'info'});
  Map<String, dynamic> realtime = {};
  try {
    final rtRes = await _ws.request(
        fun: 'hwinfo', seat: seatId, merchantId: merchantId,
        data: {'type': 'realtime'});
    realtime = Map<String, dynamic>.from(rtRes['data'] ?? {});
  } catch (_) {}
  return _transformHardwareInfo(
      Map<String, dynamic>.from(infoRes['data'] ?? {}), realtime);
}

Future<Map<String, dynamic>> getHardwareRealtime(
    String seatId, {required int merchantId}) async {
  final res = await _ws.request(
      fun: 'hwinfo', seat: seatId, merchantId: merchantId,
      data: {'type': 'realtime'});
  return Map<String, dynamic>.from(res['data'] ?? {});
}
```

**调用方修改**：
- `monitor_page.dart:142 _loadRealtime`
- `terminal_detail_page.dart:1213`
- `widgets/hardware_info_tab.dart:35`
- `widgets/network_monitor_tab.dart:54`

全部改为传 `merchantId: netbar.id!`，去掉 `domain:`。

### A.6 电源控制

**修改** `terminal_api.dart:555 controlPc`

```dart
Future<void> controlPc(String seatId, String type,
    {required int merchantId}) async {
  final res = await _ws.request(
      fun: 'controlPc', seat: seatId, merchantId: merchantId,
      data: {'type': type});
  if (res['code'] != 0) throw ApiError(code: res['code'], message: res['msg']);
}
```

**调用方**：`terminal_detail_page.dart:1790 _remoteAction`。

### A.7 文件下载（待后端定方案）

`terminal_api.dart:466 downloadFile` 当前走 frp HTTP `responseType: bytes`，timeout 120s。**短期保留不动**，待后端给出"返回临时下载 URL"方案后再迁移。

---

## B. CMD 长流（替换 `ws://{domain}/ws_client`）

**修改** `lib/features/monitor/presentation/widgets/console_manager_tab.dart`

### B.1 删除独立 WS 建连

删除 `:95-107 _buildWsUrl` 与 `:889-945 connectWs` 内的所有 `new WebSocket(...)` 与 `wsInstance/wsReady` 状态。

### B.2 新连接逻辑

```dart
class _ConsoleManagerTabState extends ConsumerState {
  StreamSubscription? _cmdSub;
  bool cmdActive = false;
  TaskWs get _ws => ref.read(taskWsProvider);
  int get _merchantId => ref.read(currentNetbarProvider).id!;

  Future<void> _connect() async {
    _addSystemLine('[系统] 连接任务通道...');
    try {
      await _ws.ensureConnected();
      _addSystemLine('[系统] 通道已就绪');
      _login();
    } catch (e) {
      _addSystemLine('[错误] 连接失败: $e');
    }
  }

  // CMD 登录用 stream，后续命令输出全部由这条流回传
  void _login() {
    _cmdSub?.cancel();
    final stream = _ws.requestStream(
      fun: 'cmdlogin', seat: widget.seat.id,
      merchantId: _merchantId, data: {});
    _cmdSub = stream.listen(_onCmdEvent,
        onError: (e) {
          cmdActive = false;
          _addSystemLine('[错误] CMD 通道异常: $e');
        },
        onDone: () { cmdActive = false; });
  }

  void _onCmdEvent(dynamic msg) {
    final fun = msg['fun'];
    final code = msg['code'];
    if (fun == 'cmdlogin') {
      cmdActive = (code == 0);
      _addSystemLine(cmdActive ? '[系统] 登录成功' : '[错误] 登录失败');
      return;
    }
    if (fun == 'cmdRun' || fun == 'cmdReply') {
      final out = msg['data']?['msg'] ?? '';
      _writeOutput(out as String);
      return;
    }
    if (fun == 'cmdlogon') {
      cmdActive = false;
      _addSystemLine('[系统] 已注销');
      return;
    }
  }
}
```

### B.3 / B.4 执行命令 + Ctrl+C

```dart
Future<void> _runCmd(String cmd) async {
  if (!cmdActive) { _addSystemLine('[错误] 未登录'); return; }
  await _ws.request(
    fun: 'runcmd',                      // ⚠️ 旧 'cmd' 改为 'runcmd'
    seat: widget.seat.id,
    merchantId: _merchantId,
    data: {'cmd': cmd},
  );
}

Future<void> _sendCtrlC() => _runCmd('\x03');
```

### B.5 心跳/重连

删除 `_scheduleReconnect` / `reconnectTimer` 等重连状态，改为监听全局 WS 状态：

```dart
@override
void initState() {
  super.initState();
  ref.listenManual(taskWsStateProvider, (prev, curr) {
    final s = curr.value;
    if (s == TaskWsState.ready && !cmdActive) {
      _login();   // 全局重连后自动重 login
    }
  });
  _connect();
}

@override
void dispose() {
  _cmdSub?.cancel();
  super.dispose();
}
```

### B.6 接收命令输出

已合并到 `_onCmdEvent`（同时兼容 `cmdRun`/`cmdReply`，载荷一致）。

---

## C. 路由器迁移到中央 HTTP（替换 `https://router-{host}/api/...`）

**修改** `lib/features/monitor/data/router_api.dart`

### C.1 ~ C.7 整体重写

```dart
class RouterApi {
  final ApiClient _client = ApiClient.instance;
  final int _merchantId;
  RouterApi({required int merchantId}) : _merchantId = merchantId;

  Future<List<RouterInfo>> getAll() async {
    final res = await _client.get('/routers',
        queryParameters: {'merchant_id': _merchantId});
    final data = res.data;
    final list = data is List ? data : (data is Map && data['data'] is List ? data['data'] : []);
    return list.map((e) => RouterInfo.fromJson(e)).toList();
  }

  Future<RouterInfo> create(Map<String, dynamic> form) async {
    final res = await _client.post('/routers',
        data: {...form, 'merchant_id': _merchantId});  // ⚠️ create 必须带 merchant_id
    return RouterInfo.fromJson(res.data['data'] ?? res.data);
  }

  Future<RouterInfo> update(String id, Map<String, dynamic> form) async {
    final res = await _client.put('/routers/$id', data: form);  // update 不带
    return RouterInfo.fromJson(res.data['data'] ?? res.data);
  }

  // C.4 新增
  Future<void> saveRemark(String id, String remark) async {
    await _client.put('/routers/$id/remark', data: {'remark': remark});
  }

  Future<void> delete(String id) async {
    await _client.delete('/routers/$id');
  }

  // C.6 待后端确认路径
  Future<List<TrafficInterface>> getTraffic(String routerId) async {
    final res = await _client.get('/traffic/$routerId',
        queryParameters: {'merchant_id': _merchantId});
    final ifaces = (res.data['data']?['interfaces'] ?? []) as List;
    return ifaces.map((e) => TrafficInterface.fromJson(e)).toList();
  }

  // C.7 路径变更
  Future<List<String>> getScriptTypes() async {
    final res = await _client.get('/config/global/router_types');
    final data = res.data is List ? res.data : res.data['data'];
    return (data as List).map((e) {
      if (e is Map) return e['name']?.toString() ?? '';
      return e.toString();
    }).where((s) => s.isNotEmpty).toList();
  }
}
```

### C.8 Provider 调整

```dart
final routerApiProvider =
    Provider.autoDispose.family<RouterApi?, int?>((ref, netbarId) {
  if (netbarId == null) return null;
  final netbar = ref.watch(currentNetbarProvider);
  if (netbar.id != netbarId) return null;
  // 不再需要 subdomainFull
  return RouterApi(merchantId: netbarId);
});
// routersProvider / scriptTypesProvider 实现保持，consumer 不变
```

---

## D. 座位列表迁移到中央 HTTP（替换 `https://{domain}/api/seatlist`）

**修改** `terminal_api.dart:169 getAll`

```dart
Future<List<Terminal>> getAll({required int merchantId}) async {
  final res = await ApiClient.instance.get('/terminals',
      queryParameters: {'merchant_id': merchantId});
  final raw = res.data;
  final list = raw is List
      ? raw
      : (raw is Map && raw['data'] is List ? raw['data'] : []);
  return list.map<Terminal>((e) {
    final m = Map<String, dynamic>.from(e);
    // ⚠️ 字段映射：remoting_users 替代旧 remote
    final remote = m['remoting_users'] ?? m['remote'] ?? [];
    m['remote'] = remote;
    return Terminal.fromJson(m);
  }).toList();
}
```

**调用方修改**：
- `monitor_page.dart:40 terminalsProvider`：`api.getAll(merchantId: netbar.id!)`
- `desktop_management_page_impl.dart:296 _loadSeats`：删掉自己拼 URL 的 Dio 请求，改调 `terminalApi.getAll(merchantId: ...)`

**Terminal 模型**：在 `terminal_models.dart` 的 `Terminal.fromJson` 内增加对 `remoting_users` 数组的解析（字段：`user_id, nickname, group_name, started_at`）。

---

## E. 操作日志埋点（**新增**）

**新建** `lib/features/logs/data/operation_log_api.dart`

```dart
class OperationLogApi {
  final _client = ApiClient.instance;

  Future<void> add({required String event, required String description}) async {
    try {
      await _client.post('/operationLog',
          data: {'event': event, 'description': description});
    } catch (e) {
      debugPrint('[OperationLog] 上报失败（忽略）: $e');
    }
  }
}

final operationLogApiProvider = Provider((_) => OperationLogApi());
```

**调用点植入**（参考 Web `useRemoteAwaken.js:124,156,180`）：

| 位置 | 时机 | 参数 |
|---|---|---|
| `terminal_detail_page.dart` `_openVncRemote` / `_openWebRTCRemote` 成功后 | 远程连接成功 | `event:'remote.connect', description:'远程连接 ${terminal.name}'` |
| `terminal_detail_page.dart` `_remoteAction(wakeup)` 成功后 | 唤醒成功 | `event:'remote.awaken', description:'唤醒: ${terminal.name}'` |
| 远程断开成功后（远程菜单的"断开"） | 断开成功 | `event:'remote.disconnect', description:'断开远程连接: ${terminal.name}'` |

---

## F. 不动刀的部分（明确保留）

| 模块 | 代码地址 | 状态 |
|---|---|---|
| 进程列表（平铺） | `terminal_api.dart:253 getProcesses` | **保留 frp HTTP**，仍走 `_netbarPost(domain, '/task', ...)` |
| 进程树 | `terminal_api.dart:277 getProcessTree` | 同上 |
| 结束进程 | `terminal_api.dart:337 killProcess` | 同上 |
| 文件列表 | `terminal_api.dart:360 getFiles` | 同上 |
| 文件下载 | `terminal_api.dart:466 downloadFile` | 同上 |
| WOL 唤醒 | `terminal_api.dart:590 wakeOnLan` | 保留 `GET https://{domain}/api/awaken?seat=` |
| VNC 跳转 URL | `terminal_detail_page.dart:1657-1667` | URL 模板不变；前置 `remote()` 已切 WS |
| WebRTC 信令 URL | `terminal_detail_page.dart:1530-1573` | 不变；前置 `remote()` 已切 WS |
| 路由器后台跳转 | `monitor_page.dart:1095-1106` | `launchUrl(proxyUrl)` 不变 |

**因此以下底层代码不能删**（之前方案曾建议删除，本版**修正为保留**）：
- `terminal_api.dart` 内 `_buildUrl` / `_createProxiedDio` / `_netbarGet` / `_netbarPost` / `_unwrapResponse` / `_shouldReturnEmpty`：进程/文件/WOL 仍要用
- 上述方法签名保留 `domain` 参数；调用方仍要传 `domain: netbar.subdomainFull!`
- `terminal_api_dns_helper*.dart` / `terminal_api_http_helper*.dart`：本就未挂接，保持现状

---

## G. 调用方梳理（删除 domain 参数 / 加 merchantId 参数）

| 文件 | 行号 | 改动 |
|---|---|---|
| `terminal_detail_page.dart` | `:1641,1506-1522` | `api.remote(seat, type, merchantId: netbar.id!, user: ...)` |
| `terminal_detail_page.dart` | `:1786-1791` | `api.controlPc(seat, type, merchantId: netbar.id!)`；`wakeOnLan` 保留 domain |
| `terminal_detail_page.dart` | `:319` | `_screenshotApi.requestScreenshot(seatId, merchantId: netbar.id!)` |
| `terminal_detail_page.dart` | `:1207-1213` | `api.getHeartbeat / getHardwareRealtime` 改 merchantId |
| `monitor_page.dart` | `:40` | `terminalsProvider` 改用 `api.getAll(merchantId: netbar.id!)` |
| `monitor_page.dart` | `:142` | `getHardwareRealtime(seat, merchantId: ...)` |
| `monitor_page.dart` | `:240` | `_loadSingleScreenshot` 改 merchantId |
| `monitor_page.dart` | `:1064` | `api.remote(seat, action, merchantId: ...)` |
| `widgets/hardware_info_tab.dart` | `:35` | `getHardwareInfo(seat, merchantId: ...)` |
| `widgets/network_monitor_tab.dart` | `:54` | `getHardwareRealtime(seat, merchantId: ...)` |
| `widgets/process_manager_tab.dart` | `:50,96` | **不变**（仍用 domain） |
| `widgets/file_manager_tab.dart` | `:69,99,255,288` | **不变**（仍用 domain） |
| `widgets/console_manager_tab.dart` | 整体重写 | 见 B 节 |
| `desktop_management_page_impl.dart` | `:296,380` | 座位列表改 `terminalApi.getAll(merchantId)`；截图改 merchantId |
