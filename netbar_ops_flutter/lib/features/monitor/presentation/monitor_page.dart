import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/network/task_ws_provider.dart';
import '../../../core/network/ws_binary.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/terminal_dock_provider.dart';
import '../../../shared/services/terminal_window_bridge.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/utils/platform_utils.dart';
import '../../../shared/utils/top_notice.dart';
import '../../../shared/utils/open_in_new_tab.dart';
import 'package:file_picker/file_picker.dart';
import '../data/terminal_api.dart';
import '../data/router_api.dart';
import '../providers/terminal_online_provider.dart';
import '../../netbar/data/netbar_api.dart';
import '../../netbar/data/netbar_list_provider.dart';
import '../../netbar/presentation/widgets/totp_dialog.dart';
import '../../netbar/presentation/edit_netbar_modal.dart';
import '../../../shared/providers/permission_provider.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../logs/data/operation_log_api.dart';
import 'widgets/terminal_card.dart';
import '../../../shared/widgets/app_error_view.dart';
import 'widgets/router_card.dart';
import 'widgets/router_edit_modal.dart';

/// 终端列表 Provider — 按 netbarId 隔离。
///
/// 历史背景：原来是非 family 的 `FutureProvider`，跨网吧共享，AsyncValue.previous
/// 会在切网吧后残留；若消费端用 `.valueOrNull` / `isLoading ? [] : value` 形式读取，
/// 会导致上个网吧的终端列表渲染到新网吧（与 routers 同模式的架构隐患）。
/// 现改为 `autoDispose.family<?, int?>`，切网吧后旧 family 实例会被释放，previous 不跨网吧保留。
final terminalsProvider =
    FutureProvider.autoDispose.family<List<Terminal>, int?>((ref, netbarId) async {
  if (netbarId == null) return const [];
  final netbar = ref.watch(currentNetbarProvider);
  // family key 与当前 state 不同步时返回空，防止极端竞态下串台
  if (netbar.id != netbarId) return const [];
  final api = ref.read(terminalApiProvider);
  return api.getAll(merchantId: netbarId);
});

/// 终端列表【实时视图】：HTTP 快照（[terminalsProvider]）+ WS 上下机增量合并。
///
/// - 快照=初值、推送=增量：WS 按 seatId 覆盖在线/离线，无推送的座位沿用快照
/// - busy(2，远程中) 三态保留，WS 在线推送不降级
/// - 所有 `ref.invalidate(terminalsProvider(...))` 刷新逻辑不变，HTTP 刷新与
///   WS 实时分层互不干扰；本 provider 仅供 UI 消费
final liveTerminalsProvider = Provider.autoDispose
    .family<AsyncValue<List<Terminal>>, int?>((ref, netbarId) {
  final base = ref.watch(terminalsProvider(netbarId));
  if (netbarId == null) return base;
  final onlineMap = ref.watch(terminalOnlineMapProvider(netbarId));
  return base.whenData((list) =>
      [for (final t in list) mergeTerminalStatus(t, onlineMap[t.seatId])]);
});

class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage>
    with WidgetsBindingObserver, WindowListener {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isListView = false;
  String _filterStatus = 'all'; // all, online, offline
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  // 右键菜单状态
  OverlayEntry? _menuOverlay;
  Terminal? _selectedTerminal;

  // 「下载服务端」状态：下载中标志 + 进度(0~1，total 缺失时为 null 表示不确定)
  // 空状态页按钮与关键设备区标题栏按钮共用（两者互斥显示，不会同时下载）
  bool _serverDownloading = false;
  double? _serverProgress;
  // 「下载副服务器」状态（仅关键设备区标题栏，桌面端）
  bool _subServerDownloading = false;
  double? _subServerProgress;

  // 关键设备区路由器流量手动刷新计数器：每次点击"刷新"按钮 +1，
  // RouterCard 通过 didUpdateWidget 检测变化后立即重拉一次流量并重置 15s 计时。
  int _routerRefreshTick = 0;

  // 截图缓存：seatId -> 截图数据
  final Map<String, Uint8List> _screenshotCache = {};
  bool _screenshotsLoading = false;
  // 刷新：强制重拉截图标志。为 true 时 build 的 data 分支会用最新列表强制重拉一次截图
  // （绕过缓存短路、不清空旧缓存），新图到达后 setState 覆盖，实现"保留旧图直到新图到达"无闪烁刷新。
  bool _screenshotForceRefresh = false;

  /// 批量截图并发上限（滑动窗口）：同时在飞的 thumbnail 请求最多 5 个
  static const int _maxScreenshotConcurrency = 5;

  // 截图重试相关
  final Map<String, int> _screenshotRetryCount = {}; // seatId -> 重试次数
  static const int _maxRetryCount = 10; // 最大重试次数
  static const Duration _retryBaseDelay = Duration(seconds: 3); // 基础重试延迟

  // hover 轮询：seatId -> 1s 定时器。鼠标悬停卡片时周期拉该终端的截图；
  // 离开即取消。同一时刻通常只有 1~2 个在跑。
  final Map<String, Timer> _hoverTimers = {};

  // Router traffic polling visibility control
  bool _appActive = true;       // app in foreground
  bool _onMonitorPage = true;   // GoRouter current location is /monitor
  int _mobileTabIndex = 0;      // mobile tab: 0=devices, 1=terminals

  bool get _devicesVisible => _appActive && _onMonitorPage && (!context.isPhone || _mobileTabIndex == 0);

  Listenable? _routeListenable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isDesktopPlatform) {
      // 桌面主窗口最小化/恢复事件：lifecycle paused 在桌面 Flutter 上不一定触发，
      // 加 WindowListener 兜底，确保最小化时停止 router 流量轮询等
      windowManager.addListener(this);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _routeListenable = GoRouter.of(context).routeInformationProvider;
        _routeListenable?.addListener(_onRouteChanged);
        _onRouteChanged();
      } catch (_) {}
    });
  }

  void _onRouteChanged() {
    if (!mounted) return;
    try {
      final location = GoRouterState.of(context).uri.path;
      final onMonitor = location == '/monitor';
      if (onMonitor != _onMonitorPage) {
        setState(() => _onMonitorPage = onMonitor);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancelAllHoverTimers();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (isDesktopPlatform) {
      windowManager.removeListener(this);
    }
    _routeListenable?.removeListener(_onRouteChanged);
    _hideContextMenu();
    super.dispose();
  }

  // WindowListener: 桌面主窗口最小化/恢复
  // (与 didChangeAppLifecycleState 互补——部分 Flutter Desktop 版本最小化
  // 不会触发 paused/inactive，仅依赖 lifecycle 不够稳)
  @override
  void onWindowMinimize() {
    if (!mounted) return;
    if (_appActive) setState(() => _appActive = false);
  }

  @override
  void onWindowRestore() {
    if (!mounted) return;
    if (!_appActive) setState(() => _appActive = true);
  }

  // WidgetsBindingObserver: app lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active != _appActive) {
      setState(() => _appActive = active);
    }
  }

  /// 鼠标进入卡片：启动该终端 1s 截图轮询。
  /// 立即拉一次，之后每 1s 一次。防串台：请求内校验 netbarId。
  void _onCardHoverStart(Terminal terminal) {
    if (terminal.status == 0) return; // 离线机器无实时数据，不拉截图
    final seatId = terminal.seatId;
    if (seatId.isEmpty || _hoverTimers.containsKey(seatId)) return;
    final netbarId = ref.read(currentNetbarIdProvider);
    void tick() {
      _loadHoverScreenshot(terminal, netbarId);
    }
    tick(); // 立即一次，避免等满 1s 才出数据
    _hoverTimers[seatId] =
        Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// 鼠标离开卡片：停止轮询。截图缓存保留（最后一帧作为更新后的静态缩略图）。
  void _onCardHoverEnd(String seatId) {
    _hoverTimers.remove(seatId)?.cancel();
  }

  void _cancelAllHoverTimers() {
    for (final t in _hoverTimers.values) {
      t.cancel();
    }
    _hoverTimers.clear();
  }

  /// hover 轮询的截图请求：直接拉缩略图覆盖缓存，失败等下个 tick，不走重试队列
  /// （高频轮询下 _scheduleRetry 会堆积）。
  Future<void> _loadHoverScreenshot(Terminal terminal, int? netbarId) async {
    if (terminal.seatId.isEmpty) return;
    try {
      final ws = ref.read(taskWsProvider);
      final bytes = await requestThumbnail(ws,
          seatId: terminal.seatId, merchantId: netbarId ?? 0);
      if (!mounted || ref.read(currentNetbarIdProvider) != netbarId) return;
      if (bytes != null && _hoverTimers.containsKey(terminal.seatId)) {
        setState(() => _screenshotCache[terminal.seatId] = bytes);
      }
    } catch (_) {}
  }

  /// 批量获取所有在线终端的截图。
  /// [netbarId] 为发起时的网吧 ID，贯穿整条异步链做防串台校验。
  Future<void> _loadScreenshots(List<Terminal> terminals, int? netbarId,
      {bool force = false}) async {
    // 只获取在线终端的截图
    final onlineTerminals = terminals.where((t) => t.status > 0).toList();
    if (onlineTerminals.isEmpty) return;

    setState(() => _screenshotsLoading = true);

    // 限流：滑动窗口并发池，同时在飞的截图请求最多 _maxScreenshotConcurrency 个，
    // 完成一个立即补下一个，避免一次性并发全部终端压垮服务端。
    // 防串台：worker 循环绑定发起时的 netbarId，一旦切换网吧立即停止旧网吧的请求。
    var nextIndex = 0;
    Future<void> worker() async {
      while (mounted && ref.read(currentNetbarIdProvider) == netbarId) {
        final i = nextIndex++;
        if (i >= onlineTerminals.length) return;
        await _loadSingleScreenshot(onlineTerminals[i], netbarId, force: force);
      }
    }

    final workerCount =
        onlineTerminals.length < _maxScreenshotConcurrency
            ? onlineTerminals.length
            : _maxScreenshotConcurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));

    if (mounted) {
      setState(() => _screenshotsLoading = false);
    }
  }

  /// 获取单个终端的截图，失败时静默重试。
  /// [netbarId] 为发起时的网吧 ID：merchantId 直接用它（避免与 seatId 错配），
  /// 且响应回来后校验仍是当前网吧，否则丢弃，防止切网吧后 A 的截图写进 B。
  Future<void> _loadSingleScreenshot(Terminal terminal, int? netbarId,
      {bool force = false}) async {
    if (!mounted) return;

    // 如果已经有缓存，不再请求；force(刷新)时绕过缓存短路，强制重拉以覆盖旧图。
    if (!force && _screenshotCache.containsKey(terminal.seatId)) return;

    try {
      // 改用 wsbin thumbnail（300px 缩略图）通道，merchantId 用发起时的网吧 ID
      final ws = ref.read(taskWsProvider);
      final bytes = await requestThumbnail(
        ws,
        seatId: terminal.seatId,
        merchantId: netbarId ?? 0,
      );
      // 防串台：响应回来后若已切换网吧，丢弃（不写缓存、不重试）
      if (!mounted || ref.read(currentNetbarIdProvider) != netbarId) return;

      if (bytes != null) {
        setState(() {
          _screenshotCache[terminal.seatId] = bytes;
          _screenshotRetryCount.remove(terminal.seatId); // 成功后清除重试计数
        });
      } else {
        // 返回数据为空，也进行重试
        _scheduleRetry(terminal, netbarId);
      }
    } catch (_) {
      // 防串台：异常后同样校验，已切网吧则不重试
      if (!mounted || ref.read(currentNetbarIdProvider) != netbarId) return;
      // 请求失败，安排重试
      _scheduleRetry(terminal, netbarId);
    }
  }

  /// 安排截图重试
  void _scheduleRetry(Terminal terminal, int? netbarId) {
    if (!mounted) return;

    final currentRetry = _screenshotRetryCount[terminal.seatId] ?? 0;
    if (currentRetry >= _maxRetryCount) {
      // 达到最大重试次数，停止重试
      _screenshotRetryCount.remove(terminal.seatId);
      return;
    }

    // 更新重试计数
    _screenshotRetryCount[terminal.seatId] = currentRetry + 1;

    // 计算延迟时间（递增延迟：3s, 6s, 9s, ...）
    final delay = _retryBaseDelay * (currentRetry + 1);

    Future.delayed(delay, () {
      // 防串台：延迟到期时若已切换网吧，放弃重试
      if (mounted &&
          ref.read(currentNetbarIdProvider) == netbarId &&
          !_screenshotCache.containsKey(terminal.seatId)) {
        _loadSingleScreenshot(terminal, netbarId);
      }
    });
  }

  void _hideContextMenu() {
    _menuOverlay?.remove();
    _menuOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    // 切换网吧时重置搜索和筛选状态
    ref.listen<CurrentNetbar>(currentNetbarProvider, (prev, next) {
      if (prev?.id != next.id) {
        _cancelAllHoverTimers(); // 切网吧：停掉所有 hover 轮询，防止旧网吧迟到响应串台
        // 切网吧重置手机端打开详情的去抖记录，避免跨网吧误判去抖窗口。
        _lastOpenTerminalId = null;
        _lastOpenTerminalAt = null;
        setState(() {
          _searchQuery = '';
          _filterStatus = 'all';
          _searchController.clear();
          _screenshotCache.clear();
          _screenshotRetryCount.clear();
        });
        // 防御：若当前路由栈在 /terminal/:id（主窗口 in-place 详情页），
        // 主窗口切网吧时将其归位到 /monitor，避免详情页持有旧网吧的 owner state。
        // 注：当前架构下 /terminal/:id 是顶层路由、不与 MainLayout 共存，用户
        // 实际无法在详情页上触发切网吧；此处仅作未来架构调整时的防御兜底。
        try {
          final loc = GoRouterState.of(context).uri.path;
          if (loc.startsWith('/terminal/')) {
            context.go('/monitor');
          }
        } catch (_) {}
      }
    });

    final netbarId = ref.watch(currentNetbarIdProvider);
    final terminalsAsync = ref.watch(liveTerminalsProvider(netbarId));

    return GestureDetector(
      onTap: _hideContextMenu,
      child: Container(
        color: AppColors.iosBg,
        child: terminalsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorView(
            error: error,
            onRetry: () => ref.invalidate(terminalsProvider(netbarId)),
          ),
          data: (terminals) {
            // 批量截图：改用 wsbin thumbnail（300px 缩略图）通道，首帧后批量拉取。
            // 触发条件：首次(_screenshotCache 为空) 或 刷新(_screenshotForceRefresh)。
            // force 模式绕过单图缓存短路、不清旧缓存，新图回来再覆盖，实现无闪烁刷新。
            if (terminals.isNotEmpty &&
                (_screenshotForceRefresh || _screenshotCache.isEmpty) &&
                !_screenshotsLoading) {
              final force = _screenshotForceRefresh;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _screenshotForceRefresh = false;
                _loadScreenshots(terminals, netbarId, force: force);
              });
            }
            return _buildContent(terminals);
          },
        ),
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.alertTriangle,
                color: Colors.red.shade500,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(fontSize: 14, color: Colors.red.shade600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(terminalsProvider(ref.read(currentNetbarIdProvider))),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('重新加载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // 与 Web 端(toolboxPage usePermission.js)对齐：受 '服务端下载' 细分权限控制，
    // 总部管理员(hasDetailPermission 内 isTopManager)直接放行；无权限则隐藏按钮。
    final canServerDownload =
        ref.watch(permissionProvider).hasDetailPermission('服务端下载');
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: AppShadows.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.monitor,
                size: 32,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '暂无终端',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前网吧还没有连接任何终端设备',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(terminalsProvider(ref.read(currentNetbarIdProvider))),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('刷新'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iosBlue,
                foregroundColor: Colors.white,
              ),
            ),
            if (canServerDownload) ...[
              const SizedBox(height: 12),
              _buildServerDownloadButton(),
            ],
          ],
        ),
      ),
    );
  }

  /// 「服务端下载」按钮：空闲时可点击；下载中显示进度（有总长显示百分比，否则不确定转圈）
  Widget _buildServerDownloadButton() {
    if (_serverDownloading) {
      final hasPercent = _serverProgress != null;
      return OutlinedButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: _serverProgress, // null => 不确定动画
            color: AppColors.iosBlue,
          ),
        ),
        label: Text(
          hasPercent
              ? '下载中 ${(_serverProgress! * 100).toInt()}%'
              : '下载中…',
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.iosBlue,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _handleServerDownload,
      icon: const Icon(LucideIcons.download, size: 16),
      label: const Text('服务端下载'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.iosBlue,
        side: BorderSide(color: AppColors.iosBlue.withValues(alpha: 0.4)),
      ),
    );
  }

  /// 处理服务端程序下载：选自定义保存路径 → 流式下载 → 进度上报 → 结果提示
  Future<void> _handleServerDownload() async {
    // 手机端不支持本地下载安装，引导用户去 PC 端（无 Web 端，非桌面即手机）
    if (!isDesktopPlatform) {
      if (mounted) {
        showTopNotice(context, '请前往PC端下载并安装服务端',
            level: NoticeLevel.info);
      }
      return;
    }

    final id = ref.read(currentNetbarProvider).id;
    if (id == null) {
      if (mounted) {
        showTopNotice(context, '未选择网吧，无法下载', level: NoticeLevel.warning);
      }
      return;
    }

    // 让用户自定义保存路径（文件名与 Web 端一致：ChannelLaunch_{id}.zip）
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存服务端程序',
      fileName: 'ChannelLaunch_$id.zip',
    );
    if (savePath == null) return; // 用户取消

    setState(() {
      _serverDownloading = true;
      _serverProgress = null;
    });
    try {
      await NetbarApi().downloadServerToFile(
        id,
        savePath,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _serverProgress = total > 0 ? received / total : null;
          });
        },
      );
      if (mounted) {
        showTopNotice(context, '下载成功: $savePath', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _serverDownloading = false;
          _serverProgress = null;
        });
      }
    }
  }

  Widget _buildNetbarHeader({EdgeInsets padding = EdgeInsets.zero, bool showActions = false}) {
    final netbar = ref.watch(currentNetbarProvider);
    final group = netbar.groupName;
    final name = netbar.name ?? '';
    if (name.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Row(
        children: [
          // 面包屑（组名 + chevron + 名称）独占左侧弹性空间，把操作按钮挤到最右。
          // 注意：不能用 Flexible(名称)+Spacer() 双弹性子节点——它们会平分剩余空间，
          // 导致按钮停在中间。改用单一 Expanded 包裹面包屑，才能让按钮真正贴右。
          Expanded(
            child: Row(
              children: [
                if (group != null && group.isNotEmpty) ...[
                  Text(
                    group,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(LucideIcons.chevronRight, size: 14, color: Colors.grey.shade400),
                  ),
                ],
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          // 右侧操作区（仅桌面端面包屑行显示）：生成超级密码 / 下载服务端 / 下载副服务器
          if (showActions) _buildHeaderActions(),
        ],
      ),
    );
  }

  /// 面包屑行右侧操作按钮区：生成超级密码 / 下载服务端 / 下载副服务器
  /// （从「设置菜单」「关键设备状态行」迁移而来，权限规则保持一致）
  Widget _buildHeaderActions() {
    final perm = ref.watch(permissionProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 「编辑网吧信息」复用切换网吧页(netbar_selector_modal _handleEdit)的逻辑，
        // 始终显示在最左侧（与切换网吧页一致，无权限门槛）
        _buildEditNetbarButton(),
        const SizedBox(width: 8),
        // 「生成超级密码」受 '生成超级密码' 细分权限控制
        if (perm.hasDetailPermission('生成超级密码')) ...[
          _buildSuperPwdButton(),
          const SizedBox(width: 8),
        ],
        // 「下载服务端」受 '服务端下载' 细分权限控制（与 Web 端一致）
        if (perm.hasDetailPermission('服务端下载')) ...[
          _buildKeyDeviceDownloadButton(
            label: '下载服务端',
            busy: _serverDownloading,
            progress: _serverProgress,
            onPressed: _handleServerDownload,
          ),
          const SizedBox(width: 8),
        ],
        // 「下载副服务器」无权限控制（与 Web 端一致，任何人可下）
        _buildKeyDeviceDownloadButton(
          label: '下载副服务器',
          busy: _subServerDownloading,
          progress: _subServerProgress,
          onPressed: _handleSubServerDownload,
        ),
      ],
    );
  }

  /// 「生成超级密码」按钮（样式与关键设备下载按钮一致，点击弹 TotpDialog）
  Widget _buildSuperPwdButton() {
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: () => showAdaptive<void>(
          context,
          (_) => const TotpDialog(),
          routeName: '/dialog/totp',
        ),
        icon: const Icon(LucideIcons.keyRound, size: 14),
        label: const Text('生成超级密码', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  /// 「编辑网吧信息」按钮（样式与其它 header 按钮一致，点击复用切换网吧页编辑逻辑）
  Widget _buildEditNetbarButton() {
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: _handleEditNetbar,
        icon: const Icon(LucideIcons.edit2, size: 14),
        label: const Text('编辑网吧信息', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  /// 编辑当前网吧信息：复用切换网吧页(netbar_selector_modal _handleEdit)逻辑。
  /// EditNetbarModal 需要完整 Netbar 对象回填，而其数据需异步拉取——为避免点击后
  /// 长时间无响应，这里先用 _EditNetbarLoader 立即弹窗显示加载特效，数据就绪后再
  /// 原地切换成编辑表单。保存/删除成功后同步 currentNetbar。
  Future<void> _handleEditNetbar() async {
    final id = ref.read(currentNetbarIdProvider);
    if (id == null) return;

    final saved = await showAdaptive<bool>(
      context,
      (context) => _EditNetbarLoader(netbarId: id),
      barrierColor: Colors.black.withValues(alpha: 0.2),
      routeName: '/dialog/edit-netbar',
    );
    if (saved != true) return;

    // 与切换网吧页一致：保存/删除成功后刷新列表
    final refreshed = await ref.refresh(netbarListProvider.future);

    // 编辑的是「当前网吧」，可能被改名/改分组/删除 → 同步 currentNetbar
    Netbar? updated;
    for (final n in refreshed.merchants) {
      if (n.id == id) {
        updated = n;
        break;
      }
    }
    if (!mounted) return;
    if (updated != null) {
      // 改名/改分组后同步，面包屑等立即反映新值
      await ref.read(currentNetbarProvider.notifier).setNetbar(
            updated.id,
            updated.name,
            updated.status,
            subdomainFull: updated.subdomainFull,
            groupName: updated.group,
          );
    } else {
      // 当前网吧已被删除：清空当前网吧并返回网吧列表，避免停留在已删网吧的监控页
      await ref.read(currentNetbarProvider.notifier).clear();
      if (mounted) context.go('/netbar-list');
    }
  }

  Widget _buildContent(List<Terminal> terminals) {
    // 空列表：显示暂无终端提示
    if (terminals.isEmpty) {
      return _buildEmptyState();
    }

    // 分离关键设备和普通终端
    final keyDevices = terminals.where((t) => t.isKeyDevice).toList();
    // 关键设备排序：主服务器 → 副服务器 → 其它关键设备，桶内保持原顺序
    final devices = [
      ...keyDevices.where((t) => t.isMainServer),
      ...keyDevices.where((t) => t.isBackupServer),
      ...keyDevices.where((t) => !t.isMainServer && !t.isBackupServer),
    ];
    final clients = terminals.where((t) => !t.isKeyDevice).toList();

    // 过滤
    var filteredClients = clients.where((t) {
      // 搜索过滤
      if (_searchQuery.isNotEmpty &&
          !t.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      // 状态过滤
      if (_filterStatus == 'online' && t.status != 1) return false; // 在线
      if (_filterStatus == 'offline' && t.status != 0) return false; // 离线

      return true;
    }).toList();

    // 排序
    filteredClients.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0: // 终端ID (Name)
          // Try to parse as int for correct numerical sorting
          final intA = int.tryParse(a.name) ?? 0;
          final intB = int.tryParse(b.name) ?? 0;
          if (intA > 0 && intB > 0) {
            cmp = intA.compareTo(intB);
          } else {
            cmp = a.name.compareTo(b.name);
          }
          break;
        case 1: // 状态
          cmp = b.status.compareTo(a.status);
          break;
        case 2: // IP
          cmp = a.ip.compareTo(b.ip);
          break;
        case 3:
          cmp = a.mac.compareTo(b.mac);
          break;
        case 4:
          cmp = a.uptime.compareTo(b.uptime);
          break;
        case 5:
          final aTime = _parseToCst(a.updatedAt);
          final bTime = _parseToCst(b.updatedAt);
          cmp = (aTime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            bTime ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
          break;
        default:
          // 默认排序：在线在前
          if (a.status > 0 && b.status == 0) return -1;
          if (a.status == 0 && b.status > 0) return 1;
          return 0;
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (context.isPhone) {
      return DefaultTabController(
        length: 2,
        initialIndex: 0, // 默认”关键设备状态”
        child: Column(
          children: [
            _buildNetbarHeader(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.iosCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.iosSeparator),
                  boxShadow: AppShadows.sm,
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: AppColors.iosBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey.shade600,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: const [
                    Tab(text: '关键设备状态'),
                    Tab(text: '终端列表'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _MobileTabAwareBuilder(
                onTabChanged: (index) {
                  if (_mobileTabIndex != index) {
                    setState(() => _mobileTabIndex = index);
                  }
                },
                builder: (context, tabIndex) => TabBarView(
                  children: [
                    // 关键设备状态
                    CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildDevicesSection(
                            devices,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          ),
                        ),
                      ],
                    ),
                  // 终端列表
                  CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildToolbar(filteredClients.length),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        sliver: _isListView
                            ? SliverToBoxAdapter(
                                child: _buildTerminalDataTable(filteredClients),
                              )
                            : SliverLayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.crossAxisExtent;
                                  int columns = 2;
                                  if (width >= 640) columns = 3;

                                  return SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: columns,
                                          childAspectRatio: 1.45, // 截图区接近 16:9 + 底部名称栏
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final terminal = filteredClients[index];
                                      return TerminalCard(
                                        terminal: terminal,
                                        screenshotBytes: _screenshotCache[terminal.seatId],
                                        onTap: () =>
                                            _openTerminalDetail(terminal),
                                        onSecondaryTapDown: (details) =>
                                            _showContextMenu(details, terminal),
                                        onHoverStart: () =>
                                            _onCardHoverStart(terminal),
                                        onHoverEnd: () =>
                                            _onCardHoverEnd(terminal.seatId),
                                      );
                                    }, childCount: filteredClients.length),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 当前网吧标题
        SliverToBoxAdapter(child: _buildNetbarHeader(padding: const EdgeInsets.fromLTRB(32, 24, 32, 0), showActions: true)),
        // 关键设备区域
        SliverToBoxAdapter(child: _buildDevicesSection(devices)),
        // 工具栏
        SliverToBoxAdapter(child: _buildToolbar(filteredClients.length)),
        // 终端列表/网格
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          sliver: _isListView
              ? SliverToBoxAdapter(
                  child: _buildTerminalDataTable(filteredClients),
                )
              : SliverLayoutBuilder(
                  builder: (context, constraints) {
                    // 响应式列数: 类似 Vue 的 grid-cols-2 sm:3 md:4 lg:5 xl:6 2xl:8
                    final width = constraints.crossAxisExtent;
                    int columns;
                    if (width >= 1536) {
                      columns = 8;
                    } else if (width >= 1280) {
                      columns = 6;
                    } else if (width >= 1024) {
                      columns = 5;
                    } else if (width >= 768) {
                      columns = 4;
                    } else if (width >= 640) {
                      columns = 3;
                    } else {
                      columns = 2;
                    }

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 1.45, // 截图区接近 16:9 + 底部名称栏
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final terminal = filteredClients[index];
                        return TerminalCard(
                          terminal: terminal,
                          screenshotBytes: _screenshotCache[terminal.seatId],
                          onTap: () => _openTerminalDetail(terminal),
                          onSecondaryTapDown: (details) =>
                              _showContextMenu(details, terminal),
                          onHoverStart: () => _onCardHoverStart(terminal),
                          onHoverEnd: () => _onCardHoverEnd(terminal.seatId),
                        );
                      }, childCount: filteredClients.length),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTerminalDataTable(List<Terminal> terminals) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.iosCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator),
        boxShadow: AppShadows.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  columns: [
                    _buildDataColumn('终端ID', 0),
                    _buildDataColumn('状态', 1),
                    _buildDataColumn('IP地址', 2),
                    _buildDataColumn('MAC地址', 3),
                    _buildDataColumn('在线时长', 4),
                    _buildDataColumn('最后活动时间', 5),
                  ],
                  rows: terminals.map((t) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            t.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(_buildStatusCell(t.status)),
                        DataCell(
                          Text(
                            t.ip,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ),
                        DataCell(
                          Text(
                            t.mac,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        DataCell(Text(t.uptime)),
                        DataCell(Text(_formatUpdatedAt(t.updatedAt))),
                      ],
                      onSelectChanged: (selected) {
                        if (selected == true) _openTerminalDetail(t);
                      },
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  DataColumn _buildDataColumn(String label, int index) {
    return DataColumn(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onSort: (colIndex, ascending) {
        setState(() {
          _sortColumnIndex = colIndex;
          _sortAscending = ascending;
        });
      },
    );
  }

  Widget _buildStatusCell(int status) {
    Color color;
    String text;
    if (status == 0) {
      color = Colors.grey;
      text = '离线';
    } else if (status == 1) {
      color = Colors.green;
      text = '在线';
    } else {
      color = Colors.grey; // status==2 是伪代码不会出现；其它未知值统一显示「未知」
      text = '未知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 打开终端详情
  // Mobile 去抖：记录最近一次打开的终端 id 与时刻，同一终端 600ms 内只 push 一次。
  // 不再依赖 push Future 的完成回调来清理——整栈被 context.go 替换时该 Future 永不
  // 完成，旧方案会让 id 永久残留、对应卡片永久点不动（间歇"点击无反应"根因）。
  int? _lastOpenTerminalId;
  DateTime? _lastOpenTerminalAt;

  void _openTerminalDetail(Terminal terminal) {
    if (isDesktopPlatform) {
      final netbar = ref.read(currentNetbarProvider);
      final netbarId = netbar.id ?? 0;
      final uniqueKey = '${netbarId}_${terminal.id}';

      // 先检查 Dock 中是否已有该终端（已打开则聚焦，已最小化则恢复）
      final dockState = ref.read(terminalDockProvider);
      final dockItem = dockState.items[uniqueKey];
      if (dockItem != null) {
        if (dockItem.isMinimized) {
          TerminalWindowBridge.restoreFromDock(ref, dockItem);
        } else {
          TerminalWindowBridge.focusWindow(dockItem);
        }
        return;
      }

      final lastTab = ref
          .read(terminalDockProvider.notifier)
          .lastTabFor(uniqueKey);
      TerminalWindowBridge.openTerminalWindow(
        terminalId: terminal.id,
        netbarId: netbarId,
        initialTab: lastTab,
        terminalSnapshot: terminal,
        screenshotBytes: _screenshotCache[terminal.seatId],
        netbarName: netbar.name,
        groupName: netbar.groupName,
        subdomainFull: netbar.subdomainFull,
      );
      return;
    }
    // Mobile/Web: 时间去抖防止连点重复 push（同一终端 600ms 内只触发一次）。
    // 超出窗口自动恢复，绝不会出现永久残留导致卡片永久点不动。
    final now = DateTime.now();
    if (_lastOpenTerminalId == terminal.id &&
        _lastOpenTerminalAt != null &&
        now.difference(_lastOpenTerminalAt!) <
            const Duration(milliseconds: 600)) {
      return;
    }
    _lastOpenTerminalId = terminal.id;
    _lastOpenTerminalAt = now;

    final location = '/terminal/${terminal.id}';
    if (kIsWeb) {
      openInNewTab(buildWebUrlForLocation(location));
      return;
    }
    context.push(location, extra: _screenshotCache[terminal.seatId]);
  }

  /// 转换并格式化为东八区时间
  String _formatUpdatedAt(String? value) {
    final dt = _parseToCst(value);
    if (dt == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  DateTime? _parseToCst(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final parsed = DateTime.parse(value);
      return parsed.toUtc().add(const Duration(hours: 8));
    } catch (_) {
      return null;
    }
  }

  /// 显示右键菜单
  void _showContextMenu(TapDownDetails details, Terminal terminal) {
    _hideContextMenu();
    _selectedTerminal = terminal;

    final overlay = Overlay.of(context);
    final position = details.globalPosition;

    _menuOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 背景遮罩
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideContextMenu,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 菜单
          Positioned(
            left: position.dx,
            top: position.dy,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: AppColors.iosCard, // 使用 AppColors.iosCard
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.iosSeparator,
                  ), // 使用 AppColors.iosSeparator
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildContextMenuItem('查看详情', LucideIcons.eye, () {
                      _hideContextMenu();
                      _openTerminalDetail(terminal);
                    }),
                    _buildMenuDivider(),
                    _buildContextMenuItem(
                      '重启',
                      LucideIcons.refreshCw,
                      () => _remoteAction('restart'),
                    ),
                    _buildContextMenuItem(
                      '关机',
                      LucideIcons.power,
                      () => _remoteAction('shutdown'),
                    ),
                    _buildContextMenuItem(
                      '唤醒',
                      LucideIcons.sunrise,
                      () => _remoteAction('wakeup'),
                    ),
                    _buildMenuDivider(),
                    _buildContextMenuItem(
                      '截图',
                      LucideIcons.camera,
                      () => _remoteAction('screenshot'),
                    ),
                    _buildContextMenuItem(
                      '远程桌面',
                      LucideIcons.monitor,
                      () => _remoteAction('remote'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_menuOverlay!);
  }

  Widget _buildContextMenuItem(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.iosHover, // 添加悬停效果
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: AppColors.iosGray,
            ), // 使用 AppColors.iosGray
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF333333)),
            ), // 使用更深的灰色文本
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(
      height: 1,
      color: AppColors.iosSeparator,
    ); // 使用 AppColors.iosSeparator
  }

  /// 远程操作
  Future<void> _remoteAction(String action) async {
    _hideContextMenu();
    if (_selectedTerminal == null) return;

    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }

    try {
      final api = ref.read(terminalApiProvider);
      final terminalName = _selectedTerminal!.name;
      await api.remote(_selectedTerminal!.seatId, action, merchantId: merchantId);
      // 上报操作日志（fire-and-forget）—— 与 terminal_detail_page 同入口埋点对齐
      ref.read(operationLogApiProvider).add(
            event: 'remote.connect',
            description: '远程连接 $terminalName',
          );
      if (mounted) {
        showTopNotice(
          context,
          '操作 $action 已发送到 $terminalName',
          level: NoticeLevel.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _openRouterInBrowser(RouterInfo router,
      {required int? expectedNetbarId}) async {
    debugPrint(
        '[Router] _openRouterInBrowser entry: id=${router.id} name=${router.name} proxyUrl=${router.proxyUrl}');
    // 禁用状态的路由器不应该被打开
    if (!router.enabled) {
      debugPrint('[Router] abort open: router disabled id=${router.id}');
      if (mounted) {
        showTopNotice(context, '该路由器已禁用，请先启用后再打开',
            level: NoticeLevel.warning);
      }
      return;
    }
    final token = TokenStore.getToken() ?? '';
    final netbar = ref.read(currentNetbarProvider);
    // 不变量：卡片渲染时绑定的 netbarId 必须与点击瞬间的当前 netbar 一致。
    // 这是"路由器数据跨网吧串台"bug 的最后一道防线：
    //   - debug：assert 直接崩溃，任何未来重构破坏该不变量都会在开发期暴露；
    //   - release：assert 被擦除，保留 warning + return，用户看到提示而不是打开错误路由器。
    if (expectedNetbarId != netbar.id) {
      assert(false,
          '[Router] netbarId 不变量被破坏：expected=$expectedNetbarId current=${netbar.id} proxyUrl=${router.proxyUrl}');
      debugPrint(
          '[Router] abort open: expectedNetbarId=$expectedNetbarId currentId=${netbar.id}');
      if (mounted) {
        showTopNotice(context, '网吧已切换，请重新操作',
            level: NoticeLevel.warning);
      }
      return;
    }
    final uri = Uri.parse(router.proxyUrl);
    final newUri = uri.replace(
      host: uri.host.toLowerCase(),
      path: '/embed/',
      queryParameters: {
        'netbarGroup': netbar.groupName ?? '',
        'netbarName': netbar.name ?? '',
        'Authorization': 'Bearer $token',
      },
    );
    final urlStr = newUri.toString();
    debugPrint('[Router] opening url(len=${urlStr.length})=$urlStr');
    try {
      final ok = await launchUrl(newUri, mode: LaunchMode.externalApplication);
      debugPrint('[Router] launchUrl returned ok=$ok');
      if (!ok && mounted) {
        showTopNotice(
            context, '打开浏览器失败：系统未返回成功状态（可能 URL 过长或无默认浏览器）',
            level: NoticeLevel.error);
      }
    } catch (e, st) {
      debugPrint('[Router] launchUrl exception: $e\n$st');
      if (mounted) {
        showTopNotice(context, '打开浏览器异常: $e',
            level: NoticeLevel.error);
      }
    }
  }

  void _showRouterEditModal({RouterInfo? router, required int? netbarId}) {
    if (netbarId == null) return;
    final api = ref.read(routerApiProvider(netbarId));
    if (api == null) return;
    showAdaptive<bool>(
      context,
      (_) => RouterEditModal(api: api, router: router, netbarId: netbarId),
      routeName: '/dialog/router-edit',
    ).then((saved) {
      if (saved == true) ref.refresh(routersProvider(netbarId));
    });
  }

  Widget _buildDevicesSection(List<Terminal> devices, {EdgeInsets? padding}) {
    final netbarId = ref.watch(currentNetbarIdProvider);
    final routersAsync = ref.watch(routersProvider(netbarId));
    final routerApi = ref.watch(routerApiProvider(netbarId));

    return Padding(
      padding: padding ?? const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar with "新增路由器" button
          if (context.isPhone)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '关键设备状态',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                    _buildAddRouterButton(compact: true),
                    const SizedBox(width: 8),
                    _buildDevicesRefreshButton(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '服务器 / 控制台 / 收银机 / 路由器',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            )
          else
            Row(
              children: [
                const Text(
                  '关键设备状态',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  '服务器 / 控制台 / 收银机 / 路由器',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                const Spacer(),
                _buildAddRouterButton(compact: false),
                // 「下载服务端」「下载副服务器」已迁移至顶部面包屑行右侧（_buildHeaderActions）
                const SizedBox(width: 8),
                _buildDevicesRefreshButton(),
              ],
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isPhone = context.isPhone;
              final gap = isPhone ? 12.0 : 16.0;
              // 列数断点与终端列表 1:1 对齐，避免关键设备卡片被撑得比终端卡大几倍
              int columns;
              if (isPhone) {
                columns = width >= 640 ? 3 : 2;
              } else if (width >= 1536) {
                columns = 8;
              } else if (width >= 1280) {
                columns = 6;
              } else if (width >= 1024) {
                columns = 5;
              } else if (width >= 768) {
                columns = 4;
              } else if (width >= 640) {
                columns = 3;
              } else {
                columns = 2;
              }
              final itemWidth = (width - (columns - 1) * gap) / columns;
              // 截图区接近 16:9 + 底部名称栏，与终端列表卡片比例(1.45)保持一致
              final itemHeight = itemWidth / 1.45;

              // Router 三态：
              //   1) hasValue + 非空 → 渲染 RouterCard 列表，无占位
              //   2) hasValue + 空    → 1 个"无路由信息"占位
              //   3) hasError        → 1 个"加载失败"占位（严格只接 AsyncData 的语义保持：不使用 previous）
              //   4) loading(首次)   → 1 个"正在加载路由信息"占位
              // 防串台原则：只有 hasValue 时才把数据取出来渲染 RouterCard；
              // AsyncError.previous（切网吧中途的旧数据）被统一降级为 loading/error 占位。
              final List<RouterInfo> routers;
              final _RouterPlaceholderKind? placeholderKind;
              if (routersAsync.hasValue && !routersAsync.hasError) {
                routers = routersAsync.value ?? const <RouterInfo>[];
                placeholderKind = routers.isEmpty ? _RouterPlaceholderKind.empty : null;
              } else if (routersAsync.hasError) {
                routers = const <RouterInfo>[];
                placeholderKind = _RouterPlaceholderKind.error;
              } else {
                routers = const <RouterInfo>[];
                placeholderKind = _RouterPlaceholderKind.loading;
              }

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  // 1) Key device cards (servers, consoles, cashiers)
                  ...devices.map(
                    (d) => SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: TerminalCard(
                        terminal: d,
                        screenshotBytes: _screenshotCache[d.seatId],
                        onTap: () => _openTerminalDetail(d),
                        onSecondaryTapDown: (details) =>
                            _showContextMenu(details, d),
                        onHoverStart: () => _onCardHoverStart(d),
                        onHoverEnd: () => _onCardHoverEnd(d.seatId),
                      ),
                    ),
                  ),
                  // 2) Router cards (always after devices)
                  ...routers.map(
                    (r) => SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: RouterCard(
                        // netbarId 入 key：切网吧时强制销毁旧 State，
                        // 避免 polling 用旧 api 查旧网吧 traffic。
                        key: ValueKey('router-$netbarId-${r.id}'),
                        router: r,
                        api: routerApi,
                        refreshTick: _routerRefreshTick,
                        active: _devicesVisible,
                        onTap: () => _openRouterInBrowser(r, expectedNetbarId: netbarId),
                        onEdit: () => _showRouterEditModal(router: r, netbarId: netbarId),
                      ),
                    ),
                  ),
                  // 3) Router placeholder：loading / empty / error 三态之一，不可点击
                  if (placeholderKind != null)
                    SizedBox(
                      width: itemWidth,
                      height: itemHeight,
                      child: _RouterPlaceholderCard(kind: placeholderKind),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 关键设备区标题栏紧凑下载按钮（高度与"新增路由器"一致）
  /// 下载中显示环形进度 + 百分比（progress 为 null 时显示"下载中…"不确定动画）
  Widget _buildKeyDeviceDownloadButton({
    required String label,
    required bool busy,
    required double? progress,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                  color: Colors.white,
                ),
              )
            : const Icon(LucideIcons.download, size: 14),
        label: Text(
          busy
              ? (progress != null ? '${(progress * 100).toInt()}%' : '下载中…')
              : label,
          style: const TextStyle(fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.iosBlue.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  /// 处理副服务器安装包下载：选自定义保存路径 → 流式下载固定 OSS 地址 → 进度 → 提示
  Future<void> _handleSubServerDownload() async {
    // 手机端不支持本地下载安装，引导去 PC 端（无 Web 端，非桌面即手机）
    if (!isDesktopPlatform) {
      if (mounted) {
        showTopNotice(context, '请前往PC端下载并安装服务端',
            level: NoticeLevel.info);
      }
      return;
    }

    // 让用户自定义保存路径（文件名与 Web 端一致：ControlChannelInstall.exe）
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存副服务器安装包',
      fileName: 'ControlChannelInstall.exe',
    );
    if (savePath == null) return; // 用户取消

    setState(() {
      _subServerDownloading = true;
      _subServerProgress = null;
    });
    try {
      await NetbarApi().downloadSubServerToFile(
        savePath,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _subServerProgress = total > 0 ? received / total : null;
          });
        },
      );
      if (mounted) {
        showTopNotice(context, '下载成功: $savePath', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _subServerDownloading = false;
          _subServerProgress = null;
        });
      }
    }
  }

  Widget _buildAddRouterButton({required bool compact}) {
    final netbarId = ref.watch(currentNetbarIdProvider);
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: netbarId == null ? null : () => _showRouterEditModal(netbarId: netbarId),
        icon: const Icon(LucideIcons.plus, size: 14),
        label: Text(compact ? '路由器' : '新增路由器', style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF06B6D4),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildDevicesRefreshButton() {
    final netbarId = ref.watch(currentNetbarIdProvider);
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: () {
          // 重新拉取：列表数据 + 路由 + 路由器流量 + 截图缩略图。
          // - _routerRefreshTick++ 让 RouterCard didUpdateWidget 立即重拉流量并重置 15s 计时
          // - _screenshotForceRefresh 让 build 用最新列表强制重拉截图(保留旧图直到新图到达)
          setState(() {
            _routerRefreshTick++;
            _screenshotForceRefresh = true;
          });
          ref.invalidate(terminalsProvider(netbarId));
          if (netbarId != null) ref.invalidate(routersProvider(netbarId));
        },
        icon: const Icon(LucideIcons.refreshCw, size: 14),
        style: IconButton.styleFrom(
          backgroundColor: Colors.grey.shade200,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildToolbar(int count) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    if (isNarrow && _isListView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isListView = false);
      });
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '终端列表',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const Spacer(),
              // 搜索框
              if (!isNarrow) SizedBox(width: 260, child: _buildSearchBox()),
              if (!isNarrow) const SizedBox(width: 12),
              // 筛选按钮
              PopupMenuButton<String>(
                tooltip: '筛选',
                offset: const Offset(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.iosCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.iosSeparator),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Icon(
                    LucideIcons.filter,
                    size: 18,
                    color: _filterStatus != 'all'
                        ? AppColors.iosBlue
                        : Colors.grey.shade600,
                  ),
                ),
                onSelected: (val) => setState(() => _filterStatus = val),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'all', child: Text('全部')),
                  const PopupMenuItem(value: 'online', child: Text('在线')),
                  const PopupMenuItem(value: 'offline', child: Text('离线')),
                ],
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: AppColors.iosSeparator),
              const SizedBox(width: 8),
              // 视图切换
              if (!isNarrow)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.iosCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.iosSeparator),
                    boxShadow: AppShadows.sm,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildToolbarSwitchItem(
                        icon: LucideIcons.layoutGrid,
                        isSelected: !_isListView,
                        onTap: () => setState(() => _isListView = false),
                      ),
                      _buildToolbarSwitchItem(
                        icon: LucideIcons.list,
                        isSelected: _isListView,
                        onTap: () => setState(() => _isListView = true),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
              // 刷新按钮
              _buildToolbarButton(
                icon: LucideIcons.refreshCw,
                tooltip: '刷新',
                // 重新拉取：终端列表数据 + 截图缩略图。
                // 置 _screenshotForceRefresh 让 build 用最新列表强制重拉截图(保留旧图直到新图到达)。
                onPressed: () {
                  setState(() {
                    _screenshotForceRefresh = true;
                  });
                  ref.invalidate(terminalsProvider(ref.read(currentNetbarIdProvider)));
                },
                size: isNarrow ? 40 : 44,
              ),
            ],
          ),
          if (isNarrow) const SizedBox(height: 12),
          if (isNarrow) _buildSearchBox(),
        ],
      ),
    );
  }

  /// 构建工具栏按钮
  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 44,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.iosCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.iosSeparator),
          boxShadow: AppShadows.sm,
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18, color: Colors.grey.shade600),
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          splashRadius: size / 2,
        ),
      ),
    );
  }

  /// 构建工具栏切换项 (例如, 网格/列表视图切换)
  Widget _buildToolbarSwitchItem({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.iosBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : Colors.grey.shade500,
          ),
        ), // AnimatedContainer 结束
      ), // GestureDetector 结束
    ); // MouseRegion 结束
  }

  Widget _buildSearchBox() {
    return Container(
      width: double.infinity,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.iosCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                filled: false,
                hintText: '搜索机号...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// Listens to DefaultTabController and rebuilds with current tab index.
class _MobileTabAwareBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, int tabIndex) builder;
  final ValueChanged<int>? onTabChanged;
  const _MobileTabAwareBuilder({required this.builder, this.onTabChanged});

  @override
  State<_MobileTabAwareBuilder> createState() => _MobileTabAwareBuilderState();
}

class _MobileTabAwareBuilderState extends State<_MobileTabAwareBuilder> {
  TabController? _tabController;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tc = DefaultTabController.of(context);
    if (tc != _tabController) {
      _tabController?.removeListener(_onTab);
      _tabController = tc;
      _tabController?.addListener(_onTab);
      _index = tc.index;
    }
  }

  void _onTab() {
    if (_tabController != null && _tabController!.index != _index) {
      setState(() => _index = _tabController!.index);
      widget.onTabChanged?.call(_index);
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _index);
}

/// 路由器占位卡：与 RouterCard 同尺寸/同风格的纯提示卡，无点击交互。
enum _RouterPlaceholderKind { loading, empty, error }

class _RouterPlaceholderCard extends StatelessWidget {
  final _RouterPlaceholderKind kind;
  const _RouterPlaceholderCard({required this.kind});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = context.isPhone || constraints.maxHeight < 180;
          final fontSize = isCompact ? 12.0 : 13.0;
          final iconSize = isCompact ? 22.0 : 28.0;

          late final Widget leading;
          late final String text;
          late final Color accent;
          switch (kind) {
            case _RouterPlaceholderKind.loading:
              accent = const Color(0xFF06B6D4);
              text = '正在加载路由信息...';
              leading = SizedBox(
                width: iconSize,
                height: iconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              );
              break;
            case _RouterPlaceholderKind.empty:
              accent = Colors.grey.shade500;
              text = '无路由信息';
              leading = Icon(LucideIcons.router, size: iconSize, color: accent);
              break;
            case _RouterPlaceholderKind.error:
              accent = const Color(0xFFF59E0B);
              text = '路由信息加载失败';
              leading = Icon(LucideIcons.alertTriangle, size: iconSize, color: accent);
              break;
          }

          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey.shade600.withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: AppShadows.sm,
            ),
            child: Opacity(
              opacity: 0.7,
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 10 : 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      leading,
                      SizedBox(height: isCompact ? 8 : 12),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: fontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 「编辑网吧信息」加载包装：点击后立即弹窗并显示加载特效，
/// 在后台异步拉取完整 Netbar 对象（EditNetbarModal 回填所需），就绪后原地切换成
/// 编辑表单。loading/error 占位与 EditNetbarModal 共用 ResponsiveDialogScaffold
/// (title:'编辑网吧', maxWidth:500)，外层尺寸一致，切换不跳变。
class _EditNetbarLoader extends ConsumerStatefulWidget {
  final int netbarId;

  const _EditNetbarLoader({required this.netbarId});

  @override
  ConsumerState<_EditNetbarLoader> createState() => _EditNetbarLoaderState();
}

class _EditNetbarLoaderState extends ConsumerState<_EditNetbarLoader> {
  Netbar? _netbar;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ref.read(netbarListProvider.future);
      Netbar? target;
      for (final n in resp.merchants) {
        if (n.id == widget.netbarId) {
          target = n;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        if (target == null) {
          _error = '未找到当前网吧信息，请关闭后重试';
        } else {
          _netbar = target;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = '网吧信息加载失败，请关闭后重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 数据就绪 → 渲染真正的编辑表单
    if (_netbar != null) {
      return EditNetbarModal(netbar: _netbar);
    }
    // 加载中 / 加载失败 → 占位（外层骨架与编辑表单一致，避免尺寸跳变）
    return ResponsiveDialogScaffold(
      title: '编辑网吧',
      maxWidth: 500,
      scrollableBody: false,
      body: SizedBox(
        height: 160,
        child: Center(
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2.5),
                    const SizedBox(height: 16),
                    Text('加载中…', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                )
              : Text(_error!, style: TextStyle(color: Colors.grey.shade700)),
        ),
      ),
      footer: _error == null
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
    );
  }
}
