import 'package:flutter/foundation.dart';

/// 全局离线状态：当前设备与后端之间是否可达。
///
/// 不引入 connectivity_plus：网吧常见的透明代理 / 门户认证场景下，系统连通性
/// API 会误报「有网」，以真实请求结果判定更准，也省掉四端原生配置。
///
/// 状态由 [ApiCacheInterceptor] 单向驱动：
/// - 任一真实响应到达 → [markOnline]
/// - 请求因网络类错误失败 → [markOffline]
///
/// UI 侧用 [offline] 配合 `ValueListenableBuilder` 监听（不走 Riverpod，
/// 拦截器在任意 isolate 时序下都能直接置位，无需 container 引用）。
class OfflineStatus {
  static final OfflineStatus instance = OfflineStatus._();
  OfflineStatus._();

  /// 离线期间放行探针的最小间隔。
  static const Duration probeInterval = Duration(seconds: 5);

  /// 离线期间探针请求的超时上限。
  /// 全局默认 5s（AppConfig）在断网时会让用户明显卡顿，探针压到 2s。
  static const Duration probeTimeout = Duration(seconds: 2);

  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  bool get isOffline => offline.value;

  /// 上次放行探针的时刻（毫秒）。离线期间靠定期放行真实请求探活，
  /// 不额外造探活接口，也就不存在「探活接口通了但业务接口没通」的错判。
  int _lastProbeAt = 0;

  void markOnline() {
    if (!offline.value) return;
    _lastProbeAt = 0;
    offline.value = false;
    debugPrint('[OfflineStatus] 网络已恢复，退出离线模式');
  }

  void markOffline() {
    if (offline.value) return;
    offline.value = true;
    debugPrint('[OfflineStatus] 网络不可达，进入离线模式');
  }

  /// 离线期间是否轮到这个请求去探活。
  /// 返回 true 表示占用了本轮探针名额（同时刷新计时），调用方应放行真实请求。
  bool takeProbeSlot() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProbeAt < probeInterval.inMilliseconds) return false;
    _lastProbeAt = now;
    return true;
  }

  /// 仅供测试/登出复位使用。
  @visibleForTesting
  void reset() {
    _lastProbeAt = 0;
    offline.value = false;
  }
}
