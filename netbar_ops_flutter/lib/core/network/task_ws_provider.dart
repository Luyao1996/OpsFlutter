import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'task_ws.dart';
import 'task_ws_client.dart';
import 'task_ws_proxy.dart';
import 'window_runtime.dart';

/// 全局 [TaskWs] 实例。主窗口注入真实 [TaskWsClient]，
/// 子窗口注入 IPC 代理 [TaskWsProxy]。
final taskWsProvider = Provider<TaskWs>((ref) {
  return WindowRuntime.isMainWindow
      ? TaskWsClient.instance
      : TaskWsProxy.instance;
});

/// WS 状态广播流。可在 UI 上监听 ready/closed 等状态做防抖与重登。
final taskWsStateProvider = StreamProvider<TaskWsState>((ref) {
  final ws = ref.watch(taskWsProvider);
  return ws.state;
});
