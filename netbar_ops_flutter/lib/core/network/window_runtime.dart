/// 当前进程是主窗口还是子窗口的运行时标记。
///
/// 主窗口启动时不调用 [bindSubWindow]，[isMainWindow] 默认为 true；
/// 子窗口在 `main.dart` 的 multi_window 分支拿到 windowId 后，
/// 必须立即调用 [bindSubWindow] 把自己标识为子窗口，
/// 这样 [taskWsProvider] 才会注入 [TaskWsProxy] 而非 [TaskWsClient]。
class WindowRuntime {
  WindowRuntime._();

  static int? _subWindowId;

  /// 子窗口 main 入口调用，传入从 args[1] 解析到的 windowId。
  static void bindSubWindow(int windowId) {
    _subWindowId = windowId;
  }

  /// 当前是否为主窗口（即未调用过 [bindSubWindow]）。
  static bool get isMainWindow => _subWindowId == null;

  /// 子窗口 windowId；主窗口下为 null。
  static int? get subWindowId => _subWindowId;
}
