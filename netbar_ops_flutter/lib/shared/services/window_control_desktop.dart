import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

class WindowControl {
  static const MethodChannel _channel =
      MethodChannel('mixin.one/flutter_multi_window');

  /// 终端详情独立窗口的系统标题栏隐藏由 native 侧在创建时处理。
  static Future<void> initTerminalDetailWindowChrome() async {
    if (!isDesktopPlatform) return;
  }

  static Future<bool> isMaximized(int windowId) async {
    if (!isDesktopPlatform) return false;
    final res =
        await _channel.invokeMethod<bool>('isMaximized', windowId);
    return res ?? false;
  }

  static Future<bool> toggleMaximize(int windowId) async {
    if (!isDesktopPlatform) return false;
    final res =
        await _channel.invokeMethod<bool>('toggleMaximize', windowId);
    return res ?? false;
  }

  static Future<void> startDragging(int windowId) async {
    if (!isDesktopPlatform) return;
    try {
      await _channel.invokeMethod('startDragging', windowId);
    } catch (_) {
      // ignore
    }
  }
}
