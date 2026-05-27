import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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
import '../data/terminal_api.dart';
import '../data/router_api.dart';
import '../../logs/data/operation_log_api.dart';
import 'widgets/terminal_card.dart';
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

class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> with WidgetsBindingObserver {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isListView = false;
  String _filterStatus = 'all'; // all, busy, offline
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  // 右键菜单状态
  OverlayEntry? _menuOverlay;
  Terminal? _selectedTerminal;

  // 截图缓存：seatId -> 截图数据
  final Map<String, Uint8List> _screenshotCache = {};
  bool _screenshotsLoading = false;

  /// 批量截图并发上限（滑动窗口）：同时在飞的 thumbnail 请求最多 5 个
  static const int _maxScreenshotConcurrency = 5;

  // 截图重试相关
  final Map<String, int> _screenshotRetryCount = {}; // seatId -> 重试次数
  static const int _maxRetryCount = 10; // 最大重试次数
  static const Duration _retryBaseDelay = Duration(seconds: 3); // 基础重试延迟

  // Realtime hwinfo cache: seatId -> {cpu, gpu, ram, disk}
  final Map<String, Map<String, double>> _realtimeCache = {};
  bool _realtimeLoading = false;
  Timer? _realtimeTimer;

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
    _searchController.dispose();
    _realtimeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _routeListenable?.removeListener(_onRouteChanged);
    _hideContextMenu();
    super.dispose();
  }

  // WidgetsBindingObserver: app lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (active != _appActive) {
      setState(() => _appActive = active);
    }
  }

  /// 批量获取在线终端的 hwinfo realtime（CPU/GPU/RAM）—— 走 WebSocket
  Future<void> _loadRealtimeStats(List<Terminal> terminals) async {
    if (_realtimeLoading) return;
    _realtimeLoading = true;
    final api = ref.read(terminalApiProvider);
    final merchantId = ref.read(currentNetbarProvider).id;
    if (merchantId == null) { _realtimeLoading = false; return; }

    final online = terminals.where((t) => t.status > 0 && t.seatId.isNotEmpty).toList();

    // Fetch in parallel, max 5 concurrent
    final futures = <Future>[];
    for (final t in online) {
      futures.add(
        api.getHardwareRealtime(t.seatId, merchantId: merchantId).then((rt) {
          if (!mounted) return;
          final stats = <String, double>{};
          // CPU
          final cpuList = rt['cpu'] as List?;
          if (cpuList != null && cpuList.isNotEmpty) {
            final c = cpuList[0];
            if (c is Map<String, dynamic>) stats['cpu'] = (c['load_total'] ?? 0).toDouble();
          }
          // GPU
          final gpuList = rt['gpu'] as List?;
          if (gpuList != null && gpuList.isNotEmpty) {
            final g = gpuList[0];
            if (g is Map<String, dynamic>) stats['gpu'] = (g['load_gpu'] ?? 0).toDouble();
          }
          // Memory
          final memData = rt['memory'];
          if (memData is List && memData.isNotEmpty) {
            double total = 0; int count = 0;
            for (final m in memData) {
              if (m is Map<String, dynamic>) { total += (m['load_total'] ?? 0).toDouble(); count++; }
            }
            if (count > 0) stats['ram'] = total / count;
          } else if (memData is Map<String, dynamic>) {
            stats['ram'] = (memData['load_total'] ?? 0).toDouble();
          }
          _realtimeCache[t.seatId] = stats;
        }).catchError((_) {}),
      );
      // Throttle: every 5 requests, wait for them to complete
      if (futures.length >= 5) {
        await Future.wait(futures);
        futures.clear();
      }
    }
    if (futures.isNotEmpty) await Future.wait(futures);

    _realtimeLoading = false;
    if (mounted) setState(() {}); // trigger rebuild with updated cache

    // Schedule next refresh after 15 seconds
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer(const Duration(seconds: 15), () {
      final currentId = ref.read(currentNetbarIdProvider);
      final ts = ref.read(terminalsProvider(currentId)).valueOrNull ?? [];
      _loadRealtimeStats(ts);
    });
  }

  /// Apply cached realtime stats to a terminal
  Terminal _applyRealtimeStats(Terminal t) {
    final stats = _realtimeCache[t.seatId];
    if (stats == null || stats.isEmpty) return t;
    return Terminal(
      id: t.id, seatId: t.seatId, name: t.name, code: t.code,
      netbarId: t.netbarId, areaId: t.areaId, ip: t.ip, mac: t.mac,
      os: t.os, type: t.type, status: t.status,
      cpuUsage: stats['cpu'] ?? t.cpuUsage,
      ramUsage: stats['ram'] ?? t.ramUsage,
      gpuUsage: stats['gpu'] ?? t.gpuUsage,
      diskUsage: t.diskUsage, uptime: t.uptime,
      screenshotUrl: t.screenshotUrl, lastOnline: t.lastOnline,
      lastHeartbeat: t.lastHeartbeat, createdAt: t.createdAt,
      updatedAt: t.updatedAt, remote: t.remote,
      mode: t.mode, // 透传 mode 字段，避免下游 mode==1 判断误判
      version: t.version, // 透传 version，避免实时数据合入后卡片版本号丢失
      remark: t.remark, // 透传 remark
    );
  }

  /// 批量获取所有在线终端的截图
  Future<void> _loadScreenshots(List<Terminal> terminals) async {
    final netbar = ref.read(currentNetbarProvider);
    // thumbnail 走 WS，不依赖网吧域名；domain 仅作占位透传给重试逻辑
    final domain = netbar.subdomainFull ?? '';

    // 只获取在线终端的截图
    final onlineTerminals = terminals.where((t) => t.status > 0).toList();
    if (onlineTerminals.isEmpty) return;

    setState(() => _screenshotsLoading = true);

    // 限流：滑动窗口并发池，同时在飞的截图请求最多 _maxScreenshotConcurrency 个，
    // 完成一个立即补下一个，避免一次性并发全部终端压垮服务端。
    var nextIndex = 0;
    Future<void> worker() async {
      while (mounted) {
        final i = nextIndex++;
        if (i >= onlineTerminals.length) return;
        await _loadSingleScreenshot(onlineTerminals[i], domain);
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

  /// 获取单个终端的截图，失败时静默重试
  Future<void> _loadSingleScreenshot(Terminal terminal, String domain) async {
    if (!mounted) return;

    // 如果已经有缓存，不再请求
    if (_screenshotCache.containsKey(terminal.seatId)) return;

    try {
      // 改用 wsbin thumbnail（300px 缩略图）通道，替代原 HTTP ScreenshotApi
      final ws = ref.read(taskWsProvider);
      final merchantId = ref.read(currentNetbarProvider).id ?? 0;
      final bytes = await requestThumbnail(
        ws,
        seatId: terminal.seatId,
        merchantId: merchantId,
      );
      if (!mounted) return;

      if (bytes != null) {
        setState(() {
          _screenshotCache[terminal.seatId] = bytes;
          _screenshotRetryCount.remove(terminal.seatId); // 成功后清除重试计数
        });
      } else {
        // 返回数据为空，也进行重试
        _scheduleRetry(terminal, domain);
      }
    } catch (_) {
      // 请求失败，安排重试
      _scheduleRetry(terminal, domain);
    }
  }

  /// 安排截图重试
  void _scheduleRetry(Terminal terminal, String domain) {
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
      if (mounted && !_screenshotCache.containsKey(terminal.seatId)) {
        _loadSingleScreenshot(terminal, domain);
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
        _realtimeTimer?.cancel();
        setState(() {
          _searchQuery = '';
          _filterStatus = 'all';
          _searchController.clear();
          _screenshotCache.clear();
          _screenshotRetryCount.clear();
          _realtimeCache.clear();
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
    final terminalsAsync = ref.watch(terminalsProvider(netbarId));

    return GestureDetector(
      onTap: _hideContextMenu,
      child: Container(
        color: AppColors.iosBg,
        child: terminalsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _buildErrorView(error.toString()),
          data: (terminals) {
            // 批量截图：改用 wsbin thumbnail（300px 缩略图）通道，首帧后批量拉取
            if (terminals.isNotEmpty && _screenshotCache.isEmpty && !_screenshotsLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadScreenshots(terminals);
              });
            }
            // TODO: 批量实时硬件请求暂停，并发量过大影响服务端响应
            // if (terminals.isNotEmpty && _realtimeCache.isEmpty && !_realtimeLoading) {
            //   WidgetsBinding.instance.addPostFrameCallback((_) {
            //     _loadRealtimeStats(terminals);
            //   });
            // }
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
          ],
        ),
      ),
    );
  }

  Widget _buildNetbarHeader({EdgeInsets padding = EdgeInsets.zero}) {
    final netbar = ref.watch(currentNetbarProvider);
    final group = netbar.groupName;
    final name = netbar.name ?? '';
    if (name.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
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
    );
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
      if (_filterStatus == 'busy' && t.status != 2) return false; // 使用中
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
                                          childAspectRatio: 0.9,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final terminal = _applyRealtimeStats(filteredClients[index]);
                                      return TerminalCard(
                                        terminal: terminal,
                                        screenshotBytes: _screenshotCache[terminal.seatId],
                                        onTap: () =>
                                            _openTerminalDetail(terminal),
                                        onSecondaryTapDown: (details) =>
                                            _showContextMenu(details, terminal),
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
        SliverToBoxAdapter(child: _buildNetbarHeader(padding: const EdgeInsets.fromLTRB(32, 24, 32, 0))),
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
                        childAspectRatio: 0.9, // 接近 16:9 图片 + 底部名称栏
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final terminal = _applyRealtimeStats(filteredClients[index]);
                        return TerminalCard(
                          terminal: terminal,
                          screenshotBytes: _screenshotCache[terminal.seatId],
                          onTap: () => _openTerminalDetail(terminal),
                          onSecondaryTapDown: (details) =>
                              _showContextMenu(details, terminal),
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
    } else if (status == 2) {
      color = Colors.orange;
      text = '使用中';
    } else {
      color = Colors.grey; // Default for unknown status
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
  // Track open terminal detail on mobile to prevent duplicates
  final Set<int> _mobileOpenTerminals = {};

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
    // Mobile: prevent duplicate push
    if (_mobileOpenTerminals.contains(terminal.id)) return;
    _mobileOpenTerminals.add(terminal.id);

    final location = '/terminal/${terminal.id}';
    if (kIsWeb) {
      openInNewTab(buildWebUrlForLocation(location));
      _mobileOpenTerminals.remove(terminal.id);
      return;
    }
    context.push(location, extra: _screenshotCache[terminal.seatId]).then((_) {
      _mobileOpenTerminals.remove(terminal.id);
    });
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
                const SizedBox(width: 8),
                _buildDevicesRefreshButton(),
              ],
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isPhone = context.isPhone;
              int columns;
              if (isPhone) {
                columns = width >= 320 ? 2 : 1;
              } else if (width >= 1024) {
                columns = 4;
              } else if (width >= 640) {
                columns = 2;
              } else {
                columns = 1;
              }

              final gap = isPhone ? 12.0 : 16.0;
              final itemWidth = (width - (columns - 1) * gap) / columns;
              final itemHeight = isPhone ? 160.0 : 200.0;

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
                        terminal: _applyRealtimeStats(d),
                        screenshotBytes: _screenshotCache[d.seatId],
                        onTap: () => _openTerminalDetail(d),
                        onSecondaryTapDown: (details) =>
                            _showContextMenu(details, d),
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
          ref.refresh(terminalsProvider(netbarId));
          if (netbarId != null) ref.refresh(routersProvider(netbarId));
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
                  const PopupMenuItem(value: 'busy', child: Text('使用中')),
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
                onPressed: () => ref.invalidate(terminalsProvider(ref.read(currentNetbarIdProvider))),
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
