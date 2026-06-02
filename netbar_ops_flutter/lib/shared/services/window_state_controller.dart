import 'package:flutter/foundation.dart';

import 'window_control.dart';

/// 子窗口最大化状态的唯一真相来源（single source of truth）。
///
/// 物理状态只有一个：native 窗口的 `IsZoomed`。本控制器把它收敛为一份：
/// - [init] 启动时查询一次真实状态；
/// - [onNativeMaximizeChanged] 由 native `WM_SIZE`(SIZE_MAXIMIZED/SIZE_RESTORED)
///   推送驱动，实时同步，**取代轮询**；
/// - [toggleMaximize] 是唯一的最大化操作入口，统一走 [WindowControl]。
///
/// 所有 UI（详情页右上角按钮、笨鸟远程 wrapper 标题栏）都订阅本控制器，
/// 不再各自缓存/翻转 `_isMaximized`/`_isFullscreen`，也不再用裸 win32 直接
/// 改窗口——从设计上杜绝"同一物理状态多份缓存 + 多条操作路径"导致的不一致。
class WindowStateController extends ChangeNotifier {
  WindowStateController(this.windowId);

  final int windowId;

  bool _isMaximized = false;
  bool get isMaximized => _isMaximized;

  bool _disposed = false;

  void _set(bool maximized) {
    if (_disposed || _isMaximized == maximized) return;
    _isMaximized = maximized;
    notifyListeners();
  }

  /// 启动时同步一次真实窗口状态（避免首帧按钮图标与窗口不符）。
  Future<void> init() async {
    final m = await WindowControl.isMaximized(windowId);
    _set(m);
  }

  /// native `WM_SIZE` 推送的最大化/还原事件入口（权威状态，实时）。
  void onNativeMaximizeChanged(bool maximized) => _set(maximized);

  /// 唯一的最大化切换入口，统一走 [WindowControl]（native ToggleMaximize）。
  /// native 之后还会通过 `WM_SIZE` 回推 [onNativeMaximizeChanged]，二者幂等。
  Future<void> toggleMaximize() async {
    final m = await WindowControl.toggleMaximize(windowId);
    _set(m);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
