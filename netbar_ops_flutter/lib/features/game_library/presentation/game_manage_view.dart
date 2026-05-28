import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/game_constants.dart';
import '../data/game_models.dart';
import '../providers/game_library_providers.dart';
import '../utils/formatter.dart';
import '../utils/pinyin_match.dart';
import 'widgets/batch_result_dialog.dart';
import 'widgets/health_banner.dart';
import 'widgets/recycle_bar.dart';
import 'widgets/recycle_schedule_dialog.dart';
import 'widgets/seat_picker_dialog.dart';

enum _Tab { local, all, downloads, idle }

/// 游戏管理内容视图（嵌入式 Widget，不带 Dialog 外壳）。
///
/// 用作终端详情页的 Tab 内容。父级负责通过 [isFullscreen] 与
/// [onToggleFullscreen] 控制"应用内全屏"切换。
///
/// - 桌面端：依赖父级布局（嵌入 Tab 或全屏铺满）
/// - 移动端：本组件本身已按响应式布局适配窄屏
class GameManageView extends ConsumerStatefulWidget {
  final int merchantId;
  final String subdomainFull;
  final String netbarName;

  /// 是否全屏（仅显示态，由父级控制）
  final bool isFullscreen;

  /// 全屏切换回调；为 null 时隐藏全屏按钮
  final VoidCallback? onToggleFullscreen;

  const GameManageView({
    super.key,
    required this.merchantId,
    required this.subdomainFull,
    required this.netbarName,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });

  @override
  ConsumerState<GameManageView> createState() => _GameManageViewState();
}

class _GameManageViewState extends ConsumerState<GameManageView> {
  _Tab _activeTab = _Tab.local;
  String _filterPlatform = '';
  String _filterCategory = '';
  String _filterStatus = ''; // installed / not_installed / upgradable
  String _search = '';
  String _searchDebounced = '';

  int _renderedCount = kRenderBatch;
  bool _loadingMore = false;

  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounceTimer;

  // 手机端：筛选条件是否展开（搜索框始终可见，其它筛选项默认折叠）
  bool _filtersExpanded = false;

  // 行内按钮 loading: '<platform>:<gid>:<action>' -> true
  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final n =
          ref.read(gameLibraryNotifierProvider(widget.subdomainFull).notifier);
      n.refresh();
      // 与 Web 端 watch(modelValue→fetchRecyclePlan) 对齐：进入视图就拉一次持久化的回收策略
      n.fetchRecyclePlan();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  GameLibraryNotifier get _notifier =>
      ref.read(gameLibraryNotifierProvider(widget.subdomainFull).notifier);

  // ----------- 滚动触底 -----------
  void _onScroll() {
    final pos = _scrollCtrl.position;
    if (pos.maxScrollExtent - pos.pixels < kLoadMoreDistance) {
      _loadMore();
    }
  }

  void _loadMore() {
    final state = ref.read(gameLibraryNotifierProvider(widget.subdomainFull));
    final total = _currentTotal(state);
    if (_loadingMore || _renderedCount >= total) return;
    setState(() => _loadingMore = true);
    // 80ms 让 indicator 可见
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      setState(() {
        _renderedCount = (_renderedCount + kRenderBatch).clamp(0, total);
        _loadingMore = false;
      });
    });
  }

  void _resetPaging() {
    _renderedCount = kRenderBatch;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(0);
    }
  }

  int _currentTotal(GameLibraryState state) {
    if (_activeTab == _Tab.downloads) return _filteredDownloads(state).length;
    return _filteredGames(state).length;
  }

  // ----------- 搜索防抖 -----------
  void _onSearchChanged(String v) {
    _search = v;
    _searchDebounceTimer?.cancel();
    if (v.isEmpty) {
      setState(() => _searchDebounced = '');
      _resetPaging();
      // 搜索条件变化 → 清空多选（避免不可见的选中残留）
      _notifier.clearSelection();
      return;
    }
    _searchDebounceTimer = Timer(kSearchDebounce, () {
      if (!mounted) return;
      setState(() => _searchDebounced = v.trim().toLowerCase());
      _resetPaging();
      _notifier.clearSelection();
    });
  }

  // ----------- Tab 切换 -----------
  void _switchTab(_Tab t) {
    if (_activeTab == t) return;
    setState(() {
      _activeTab = t;
      _resetPaging();
    });
    // 切 tab 一律清掉多选（避免 idle 切走后 selected 残留）
    _notifier.clearSelection();
    if (t == _Tab.downloads) {
      _notifier.startDownloadPolling();
    } else {
      _notifier.stopDownloadPolling();
    }
    // 切到 idle 且 plan 仍为 null 时兜底拉一次（视图首次 fetchRecyclePlan 可能失败/无数据）
    if (t == _Tab.idle) {
      final s = ref.read(gameLibraryNotifierProvider(widget.subdomainFull));
      if (s.recyclePlan == null) _notifier.fetchRecyclePlan();
    }
  }

  // ----------- 过滤 -----------
  List<GameItem> _filteredGames(GameLibraryState state) {
    final List<GameItem> source;
    switch (_activeTab) {
      case _Tab.local:
        source = state.localGames;
        break;
      case _Tab.idle:
        // idleGames 已在 Provider 侧硬过滤 isDeprecated / isProtectedCategory
        source = state.idleGames;
        break;
      case _Tab.all:
        source = state.games;
        break;
      case _Tab.downloads:
        source = const [];
        break;
    }
    final kw = _searchDebounced;
    return source.where((g) {
      // idle 不再额外硬过滤 isDeprecated（Provider 已做）；其它 Tab 仍硬过滤 isDeprecated
      if (_activeTab != _Tab.idle && g.isDeprecated) return false;
      if (_filterPlatform.isNotEmpty && g.platform != _filterPlatform) return false;
      if (_filterCategory.isNotEmpty && g.category != _filterCategory) return false;
      if (_activeTab == _Tab.all && _filterStatus.isNotEmpty) {
        if (_filterStatus == 'installed' && !g.isInstalledIncludingStory) return false;
        if (_filterStatus == 'not_installed' && g.isInstalledIncludingStory) return false;
        if (_filterStatus == 'upgradable' && !g.isUpgradable) return false;
      }
      if (kw.isNotEmpty) {
        if (!matchKeyword(g.name, kw) &&
            !matchKeyword(g.friendlyName, kw) &&
            !g.gid.toString().contains(kw)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  List<DownloadTask> _filteredDownloads(GameLibraryState state) {
    final kw = _searchDebounced;
    return state.downloads.where((t) {
      if (_filterPlatform.isNotEmpty && t.platform != _filterPlatform) return false;
      if (kw.isNotEmpty) {
        if (!matchKeyword(t.name, kw) &&
            !t.gid.toString().contains(kw) &&
            !matchKeyword(t.seat, kw)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  // ----------- 平台过滤变化 → 触发全量刷新（与 Web 端 watch(filterPlatform) 一致） -----------
  void _onPlatformFilterChanged(String? v) {
    setState(() {
      _filterPlatform = v ?? '';
      _resetPaging();
    });
    _notifier.clearSelection();
    _notifier.refresh(platform: _filterPlatform.isEmpty ? null : _filterPlatform);
  }

  // ============================================
  // ============== 操作（写接口） ==============
  // ============================================
  void _setActionLoading(GameItem row, String action, bool on) {
    setState(() {
      final k = '${row.platform}:${row.gid}:$action';
      if (on) {
        _actionLoading[k] = true;
      } else {
        _actionLoading.remove(k);
      }
    });
  }

  void _setActionLoadingDL(DownloadTask row, String action, bool on) {
    setState(() {
      final k = '${row.platform}:${row.gid}:$action';
      if (on) {
        _actionLoading[k] = true;
      } else {
        _actionLoading.remove(k);
      }
    });
  }

  bool _isActionLoading(String platform, int gid, String action) =>
      _actionLoading['$platform:$gid:$action'] == true;

  Future<void> _onDownload(GameItem row) async {
    final picked = await SeatPickerDialog.show(
      context,
      merchantId: widget.merchantId,
      row: row,
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    // Web 端规则：用户在 picker 里选了真实机号 → seat 单任务约束抢占旧任务；
    // picker 选了"工具箱身份"或手敲了 WW_TOOLBOX → seat=WW_TOOLBOX + from=wwls 旁路 seat 单任务约束
    final isToolbox = picked == kToolboxSeat;
    final seat = isToolbox ? kToolboxSeat : picked;
    final fromParam = isToolbox ? 'wwls' : null;

    _setActionLoading(row, 'download', true);
    try {
      final api = ref.read(gameLibraryApiProvider(widget.subdomainFull));
      final res = await api.doDownload(
        seat: seat,
        platform: row.platform,
        gid: row.gid,
        from: fromParam,
      );
      if (!mounted) return;
      if (!res.ok) {
        _toastError('下载失败：${httpErrorMessage(res.status, res.error)}');
        return;
      }
      final result = res.results[row.gid];
      if (result == 'ok') {
        final who = isToolbox ? '工具箱' : '机号 $seat';
        _toast('已加入下载队列：${row.name ?? row.gid}（$who）');
        if (res.cancelled != null) {
          final c = res.cancelled!;
          _toast(
            '已自动取消旧任务：${kPlatformLabel[c.platform] ?? c.platform} GID ${c.gid}（${c.result ?? "ok"}）',
          );
        }
        _switchTab(_Tab.downloads);
        _notifier.refreshDownloading();
      } else if (result == 'already_downloading') {
        _toastWarn('该游戏已被其他机号下载，无法抢占（换个机号重试）');
      } else {
        _toastWarn('下载失败：${formatOpResultMessage(result)}');
      }
    } catch (e) {
      if (mounted) _toastError('下载请求异常：$e');
    } finally {
      if (mounted) _setActionLoading(row, 'download', false);
    }
  }

  Future<void> _onUninstall(GameItem row) async {
    final ok = await _confirmDanger(
      title: '危险操作',
      message: '确认永久删除「${row.name ?? row.gid}」及其本地文件？该操作不可恢复。',
      confirmLabel: '确认删除',
    );
    if (!ok || !mounted) return;

    _setActionLoading(row, 'delete', true);
    try {
      final r = await _notifier.deleteSingle(row);
      if (!mounted) return;
      if (r.ok) {
        _toast('已删除：${row.name ?? row.gid}（后端清盘可能持续数秒）');
        // 1.5s 后 refresh，让后端清盘完成（与 Web 端 setTimeout 1500 对齐）
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          _notifier.refresh(platform: _filterPlatform.isEmpty ? null : _filterPlatform);
        });
        return;
      }
      // 失败分支
      if (r.status == 403) {
        _toastError('删除被拒绝：game_library 仅允许本机调用 delete_game，请通过网吧本地管理界面操作');
      } else if (r.resultCode != null) {
        _toastWarn('删除失败：${formatOpResultMessage(r.resultCode)}');
      } else {
        _toastError('删除失败：${httpErrorMessage(r.status, r.error)}');
      }
    } catch (e) {
      if (mounted) _toastError('删除请求异常：$e');
    } finally {
      if (mounted) _setActionLoading(row, 'delete', false);
    }
  }

  // ===== PR-3：闲置 Tab 批量删除 / 执行时间弹窗 =====

  /// 红色危险二次确认 AlertDialog
  Future<bool> _confirmDanger({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return r == true;
  }

  /// 闲置 Tab：底部「批量删除」入口
  /// 与 Web 端 onBulkDelete 1:1 对齐：二次确认 → 串行删除（已下沉到 Provider.deleteBulk）→ 成败分流提示 → 1.5s 后 refresh
  Future<void> _onBulkDelete() async {
    final state = ref.read(gameLibraryNotifierProvider(widget.subdomainFull));
    final selectable = _filteredGames(state);
    final targets = selectable
        .where((g) => state.selectedRowKeys.contains(g.rowKey))
        .toList(growable: false);
    if (targets.isEmpty) return;

    final ok = await _confirmDanger(
      title: '批量删除',
      message: '确认永久删除选中的 ${targets.length} 个游戏及其本地文件？该操作不可恢复。',
      confirmLabel: '确认删除',
    );
    if (!ok || !mounted) return;

    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomainFull).notifier);
    final result = await notifier.deleteBulk(targets);
    if (!mounted) return;
    notifier.clearSelection();

    if (result.failures.isEmpty) {
      _toast('已删除 ${result.success} 个游戏（后端清盘可能持续数秒）');
    } else if (result.success == 0) {
      final preview =
          result.failures.take(3).map((f) => f.name).join('、');
      _toastError(
          '全部失败 ${result.failures.length} 个：$preview${result.failures.length > 3 ? "…" : ""}');
    } else {
      await BatchResultDialog.show(
        context,
        success: result.success,
        failures: result.failures,
      );
    }

    // 仅在有成功删除时才延迟 1.5s 刷新（与单删一致，避免无效 IO）
    if (result.success > 0) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          notifier.refresh(
              platform: _filterPlatform.isEmpty ? null : _filterPlatform);
        }
      });
    }
  }

  /// 闲置 Tab：打开「执行时间」弹窗
  Future<void> _openSchedule() async {
    final state = ref.read(gameLibraryNotifierProvider(widget.subdomainFull));
    final cur = state.recyclePlan;
    final res = await RecycleScheduleDialog.show(
      context,
      weekdays: List<int>.from(cur?.weekdays ?? const <int>[]),
      time: cur?.time ?? RecycleDefaults.time,
    );
    if (res == null || !mounted) return;
    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomainFull).notifier);
    final r = await notifier.confirmSchedule(
      weekdays: res.weekdays,
      time: res.time,
    );
    if (!mounted) return;
    if (!r.ok) {
      _toastError('保存失败：${r.error ?? "未知错误"}');
    } else {
      _toast('已保存自动清理策略');
    }
  }

  Future<void> _onCancel(DownloadTask row) async {
    _setActionLoadingDL(row, 'cancel', true);
    try {
      final api = ref.read(gameLibraryApiProvider(widget.subdomainFull));
      final res = await api.cancleDownload(
        seat: row.seat ?? '',
        platform: row.platform,
        gid: row.gid,
      );
      if (!mounted) return;
      if (!res.ok) {
        _toastError('取消失败：${httpErrorMessage(res.status, res.error)}');
        return;
      }
      final result = res.results[row.gid];
      if (result == 'ok') {
        _toast('已取消：${row.name ?? row.gid}');
        _notifier.refreshDownloading();
      } else if (result == 'rejected: not owner') {
        _toastWarn('该任务由其他终端发起，当前账号无权取消');
      } else if (result == 'not_in_progress') {
        _toast('任务当前不在下载中');
        _notifier.refreshDownloading();
      } else {
        _toastWarn('取消失败：${formatOpResultMessage(result)}');
      }
    } catch (e) {
      if (mounted) _toastError('取消请求异常：$e');
    } finally {
      if (mounted) _setActionLoadingDL(row, 'cancel', false);
    }
  }

  Future<void> _onTop(DownloadTask row) async {
    if (row.platform == kPlatformStory) {
      _toast('story 平台不支持置顶');
      return;
    }
    _setActionLoadingDL(row, 'top', true);
    try {
      final api = ref.read(gameLibraryApiProvider(widget.subdomainFull));
      final res = await api.topDownload(
        seat: row.seat ?? '',
        platform: row.platform,
        gid: row.gid,
      );
      if (!mounted) return;
      if (!res.ok) {
        _toastError('置顶失败：${httpErrorMessage(res.status, res.error)}');
        return;
      }
      final result = res.results[row.gid];
      if (result == 'ok') {
        _toast('已置顶：${row.name ?? row.gid}');
        _notifier.refreshDownloading();
      } else {
        _toastWarn('置顶失败：${formatOpResultMessage(result)}');
      }
    } catch (e) {
      if (mounted) _toastError('置顶请求异常：$e');
    } finally {
      if (mounted) _setActionLoadingDL(row, 'top', false);
    }
  }

  void _toast(String msg) => _showSnack(msg, Colors.black87);
  void _toastWarn(String msg) => _showSnack(msg, const Color(0xFFB45309));
  void _toastError(String msg) => _showSnack(msg, AppColors.red);

  void _showSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================
  // =================== 构建 ===================
  // ============================================
  @override
  Widget build(BuildContext context) {
    if (widget.subdomainFull.isEmpty) {
      return const Center(
        child: Text(
          '当前网吧域名为空，无法访问游戏库',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      );
    }
    final state = ref.watch(gameLibraryNotifierProvider(widget.subdomainFull));
    final isNarrow = MediaQuery.of(context).size.width < 720;
    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        children: [
          // 手机端不渲染独立 Header（刷新/全屏按钮已挪到筛选行末尾）
          if (!isNarrow) _buildHeader(state, isNarrow: isNarrow),
          if (!isNarrow) const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _buildTabs(state, isNarrow: isNarrow),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          // 闲置 Tab 顶部回收策略工具条（顶到 list 上方、Tabs 下方，全宽贴边）
          if (_activeTab == _Tab.idle)
            RecycleBar(
              subdomain: widget.subdomainFull,
              onOpenSchedule: _openSchedule,
            ),
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(isNarrow ? 10 : 16, 10, isNarrow ? 10 : 16, 0),
              child: Column(
                children: [
                  HealthBanner(
                    unhealthyPlatforms: state.unhealthyPlatforms,
                    snapshots: state.snapshots,
                  ),
                  _buildToolbar(state, isNarrow: isNarrow),
                  const SizedBox(height: 10),
                  Expanded(child: _buildList(state)),
                  if (_activeTab == _Tab.idle) _buildBulkBar(state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(GameLibraryState state, {required bool isNarrow}) {
    // 手机端：隐藏"游戏管理"标题，只保留刷新+全屏按钮（紧贴右侧）
    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _refreshButton(state),
            if (widget.onToggleFullscreen != null) _fullscreenButton(),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.iosBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.netbarName.isEmpty ? widget.subdomainFull : widget.netbarName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  '游戏管理',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          _refreshButton(state),
          if (widget.onToggleFullscreen != null) _fullscreenButton(),
        ],
      ),
    );
  }

  Widget _refreshButton(GameLibraryState state) {
    return IconButton(
      tooltip: state.loading ? '刷新中…' : '刷新',
      onPressed: state.loading
          ? null
          : () => _notifier.refresh(
                platform: _filterPlatform.isEmpty ? null : _filterPlatform,
              ),
      icon: state.loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.refreshCw, size: 16),
      color: AppColors.iosBlue,
    );
  }

  Widget _fullscreenButton() {
    return IconButton(
      tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.onToggleFullscreen,
      icon: Icon(
        widget.isFullscreen ? LucideIcons.minimize2 : LucideIcons.maximize2,
        size: 16,
      ),
      color: AppColors.iosBlue,
    );
  }

  Widget _buildTabs(GameLibraryState state, {required bool isNarrow}) {
    final localCount = state.localGames.length;
    final allCount = state.games.length;
    final dlCount = state.downloads.length;
    final idleCount = state.idleGames.length;
    final items = [
      (_Tab.local, LucideIcons.hardDrive, '本地游戏', localCount),
      (_Tab.all, LucideIcons.listChecks, '全部游戏', allCount),
      (_Tab.downloads, LucideIcons.downloadCloud, '下载任务', dlCount),
      (_Tab.idle, LucideIcons.recycle, '闲置游戏', idleCount),
    ];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 4 : 16),
      child: Row(
        children: [
          for (final it in items)
            // 窄屏：Expanded 三等分防溢出；桌面：保持自适应宽度
            isNarrow
                ? Expanded(child: _tabItem(it.$1, it.$2, it.$3, it.$4, isNarrow: true))
                : _tabItem(it.$1, it.$2, it.$3, it.$4, isNarrow: false),
        ],
      ),
    );
  }

  Widget _tabItem(_Tab tab, IconData icon, String label, int badge, {required bool isNarrow}) {
    final active = _activeTab == tab;
    return InkWell(
      onTap: () => _switchTab(tab),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 4 : 12,
          vertical: isNarrow ? 8 : 10,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.iosBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: isNarrow ? 12 : 14,
                color: active ? AppColors.iosBlue : Colors.black54),
            SizedBox(width: isNarrow ? 3 : 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isNarrow ? 12 : 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppColors.iosBlue : Colors.black87,
                ),
              ),
            ),
            SizedBox(width: isNarrow ? 3 : 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: active ? AppColors.iosBlue.withOpacity(0.1) : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                badge.toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: active ? AppColors.iosBlue : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(GameLibraryState state, {required bool isNarrow}) {
    // 搜索框：桌面 260px 定宽；手机端铺满宽度
    final searchField = TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索游戏名 / GID',
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
        prefixIcon: const Icon(LucideIcons.search, size: 14),
        prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(LucideIcons.x, size: 12),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  _searchCtrl.clear();
                  _onSearchChanged('');
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      ),
    );

    // 筛选条件区域：平台/分类/状态/隐藏废弃/隐藏系统
    final filterChildren = <Widget>[
      _dropdown<String>(
        value: _filterPlatform.isEmpty ? null : _filterPlatform,
        hint: '全部平台',
        items: [
          const DropdownMenuItem(value: '', child: Text('全部平台')),
          for (final p in kAllPlatforms)
            DropdownMenuItem(
              value: p,
              child: Text(
                '${kPlatformLabel[p] ?? p}'
                '${state.unavailablePlatforms.contains(p) ? '（未安装）' : ''}',
              ),
            ),
        ],
        onChanged: _onPlatformFilterChanged,
      ),
      if (_activeTab != _Tab.downloads)
        _dropdown<String>(
          value: _filterCategory.isEmpty ? null : _filterCategory,
          hint: '全部分类',
          items: [
            const DropdownMenuItem(value: '', child: Text('全部分类')),
            for (final c in state.categories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) {
            setState(() {
              _filterCategory = v ?? '';
              _resetPaging();
            });
            _notifier.clearSelection();
          },
        ),
      if (_activeTab == _Tab.all)
        _dropdown<String>(
          value: _filterStatus.isEmpty ? null : _filterStatus,
          hint: '全部状态',
          items: const [
            DropdownMenuItem(value: '', child: Text('全部状态')),
            DropdownMenuItem(value: 'installed', child: Text('已下载')),
            DropdownMenuItem(value: 'not_installed', child: Text('未下载')),
            DropdownMenuItem(value: 'upgradable', child: Text('可更新')),
          ],
          onChanged: (v) {
            setState(() {
              _filterStatus = v ?? '';
              _resetPaging();
            });
            _notifier.clearSelection();
          },
        ),
    ];

    // 桌面端：搜索 + 筛选项一行 Wrap 平铺
    if (!isNarrow) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 260, child: searchField),
          ...filterChildren,
        ],
      );
    }

    // 手机端：第一行 搜索 + 筛选展开按钮 + 刷新 + 全屏；展开时第二行 Wrap 渲染筛选项
    final appliedCount = _appliedFilterCount();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 6),
            _filtersToggleButton(appliedCount),
            SizedBox(width: 40, height: 40, child: _refreshButton(state)),
            if (widget.onToggleFullscreen != null)
              SizedBox(width: 40, height: 40, child: _fullscreenButton()),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _filtersExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: filterChildren,
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }

  /// 计算已应用的筛选项数量（用于折叠按钮上的角标）
  int _appliedFilterCount() {
    var n = 0;
    if (_filterPlatform.isNotEmpty) n++;
    if (_activeTab != _Tab.downloads && _filterCategory.isNotEmpty) n++;
    if (_activeTab == _Tab.all && _filterStatus.isNotEmpty) n++;
    return n;
  }

  Widget _filtersToggleButton(int appliedCount) {
    return InkWell(
      onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _filtersExpanded ? const Color(0xFFEFF6FF) : Colors.white,
          border: Border.all(
            color: _filtersExpanded ? AppColors.iosBlue : const Color(0xFFD1D5DB),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.filter,
              size: 14,
              color: _filtersExpanded ? AppColors.iosBlue : Colors.black54,
            ),
            const SizedBox(width: 4),
            Text(
              '筛选',
              style: TextStyle(
                fontSize: 12,
                color: _filtersExpanded ? AppColors.iosBlue : Colors.black87,
              ),
            ),
            if (appliedCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.iosBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  appliedCount.toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              _filtersExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 12,
              color: _filtersExpanded ? AppColors.iosBlue : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          items: items,
          onChanged: onChanged,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          icon: const Icon(LucideIcons.chevronDown, size: 12),
        ),
      ),
    );
  }

  // ============== 列表 ==============
  Widget _buildList(GameLibraryState state) {
    final isDownloads = _activeTab == _Tab.downloads;
    final games = isDownloads ? const <GameItem>[] : _filteredGames(state);
    final downloads = isDownloads ? _filteredDownloads(state) : const <DownloadTask>[];
    final total = isDownloads ? downloads.length : games.length;
    final loading = state.loading && state.games.isEmpty && state.downloads.isEmpty;

    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (total == 0) {
      return _buildEmpty();
    }

    final visible = _renderedCount.clamp(0, total);
    final reachedEnd = visible >= total;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: visible + 1, // 末尾留 1 行：加载中/已加载完
      itemBuilder: (context, idx) {
        if (idx == visible) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          if (reachedEnd && total > 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '已显示全部 $total 条',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }
        if (isDownloads) {
          return _buildDownloadRow(downloads[idx]);
        }
        return _buildGameRow(games[idx]);
      },
    );
  }

  Widget _buildEmpty() {
    final isDownloads = _activeTab == _Tab.downloads;
    final isIdle = _activeTab == _Tab.idle;
    final IconData icon;
    final String title;
    final String tip;
    if (isDownloads) {
      icon = LucideIcons.download;
      title = '当前没有下载任务';
      tip = '在"本地"或"全部"列表点"下载"开始';
    } else if (isIdle) {
      final plan = ref
          .read(gameLibraryNotifierProvider(widget.subdomainFull))
          .recyclePlan;
      final days = plan?.retainDays ?? RecycleDefaults.retainDays;
      icon = LucideIcons.recycle;
      title = '当前没有闲置游戏';
      tip = '所有已安装游戏都在 $days 天内被打开过';
    } else {
      icon = LucideIcons.inbox;
      title = '没有符合条件的游戏';
      tip = '尝试清除筛选或修改搜索关键词';
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 8),
          Text(title,
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          Text(tip,
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }

  // ============== 游戏行 ==============
  Widget _buildGameRow(GameItem row) {
    final accent = platformAccent(row.platform);
    final accentSoft = platformAccentSoft(row.platform);
    final stateEnum = row.rowState;
    final liveState = ref.watch(gameLibraryNotifierProvider(widget.subdomainFull));
    final downloading = liveState.downloads
        .any((t) => t.platform == row.platform && t.gid == row.gid);

    final selectable = _activeTab == _Tab.idle;
    final selected = selectable && liveState.selectedRowKeys.contains(row.rowKey);

    // 选中态强化左边框为 iosBlue，其它平台 accent；未选中沿用 platform accent
    final borderColor = selected ? AppColors.iosBlue : accent;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // 选中态用极淡蓝色背景；未选中保持白底
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        border: Border(left: BorderSide(color: borderColor, width: 3)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 闲置 Tab：左侧 Checkbox
          if (selectable) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: selected,
                onChanged: (_) => _notifier.toggleSelect(row.rowKey),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.iosBlue,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.name ?? row.friendlyName ?? '未命名',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _stateChip(stateEnum, accent, accentSoft),
                    // 闲置 Tab：隐藏下载/卸载按钮（避免与底部批删路径并存）
                    if (!selectable) ...[
                      const SizedBox(width: 6),
                      _gameActionButton(row, downloading),
                    ],
                  ],
                ),
                if (row.friendlyName != null &&
                    row.friendlyName!.isNotEmpty &&
                    row.friendlyName != row.name)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      row.friendlyName!,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF9CA3AF)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _platformTag(row.platform, accent, accentSoft),
                    _metaCell(LucideIcons.hardDrive, formatBytes(row.sizeBytes),
                        bold: true),
                    _metaCell(LucideIcons.hash, row.gid.toString()),
                    if (row.isUpgradable)
                      _metaCell(
                        LucideIcons.sparkles,
                        'v${row.localVersion} → v${row.cloudVersion}',
                        color: const Color(0xFFB45309),
                      )
                    else if (row.localVersion > 0)
                      _metaCell(LucideIcons.gitCommit, 'v${row.localVersion}',
                          color: const Color(0xFF9CA3AF)),
                    if (row.category != null && row.category!.isNotEmpty)
                      _metaCell(LucideIcons.folderOpen, row.category!,
                          color: row.isSystemCategory
                              ? const Color(0xFFB45309)
                              : const Color(0xFF9CA3AF)),
                    if (row.popularity != null && row.popularity! > 0)
                      _metaCell(LucideIcons.flame, row.popularity.toString(),
                          color: const Color(0xFF9CA3AF)),
                    if (row.idcUpdateTs != null && row.idcUpdateTs! > 0)
                      _metaCell(LucideIcons.clock, formatUnix(row.idcUpdateTs),
                          color: const Color(0xFF9CA3AF)),
                    // 闲置 Tab：最近打开时间 / 从未启动
                    if (selectable)
                      (row.lastLaunchTs != null && row.lastLaunchTs! > 0)
                          ? _metaCell(LucideIcons.calendarClock,
                              '最近打开 ${formatUnix(row.lastLaunchTs)}',
                              color: const Color(0xFF10B981))
                          : _metaCell(LucideIcons.calendarClock, '从未启动',
                              color: const Color(0xFF9CA3AF)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // 闲置 Tab：整卡片点击 = 切换选择
    if (!selectable) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _notifier.toggleSelect(row.rowKey),
      child: card,
    );
  }

  Widget _gameActionButton(GameItem row, bool downloading) {
    final loadingDl = _isActionLoading(row.platform, row.gid, 'download');
    final loadingDel = _isActionLoading(row.platform, row.gid, 'delete');
    if (!row.isInstalledIncludingStory || row.isUpgradable) {
      return TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: AppColors.iosBlue,
        ),
        onPressed: (loadingDl || downloading) ? null : () => _onDownload(row),
        icon: loadingDl
            ? const SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                row.isUpgradable ? LucideIcons.arrowUpCircle : LucideIcons.download,
                size: 13,
              ),
        label: Text(row.isUpgradable ? '更新' : '下载',
            style: const TextStyle(fontSize: 12)),
      );
    }
    return TextButton.icon(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        foregroundColor: AppColors.red,
      ),
      onPressed: loadingDel ? null : () => _onUninstall(row),
      icon: loadingDel
          ? const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.trash2, size: 13),
      label: const Text('卸载', style: TextStyle(fontSize: 12)),
    );
  }

  // ============== 下载行 ==============
  Widget _buildDownloadRow(DownloadTask row) {
    final accent = platformAccent(row.platform);
    final accentSoft = platformAccentSoft(row.platform);
    final loadingTop = _isActionLoading(row.platform, row.gid, 'top');
    final loadingCancel = _isActionLoading(row.platform, row.gid, 'cancel');
    final percent = row.percent.clamp(0, 100).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name ?? 'GID ${row.gid}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _dlStateChip(row, accent, accentSoft),
              const SizedBox(width: 6),
              TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: row.platform == kPlatformStory
                      ? Colors.grey
                      : AppColors.iosBlue,
                ),
                onPressed: (row.platform == kPlatformStory || loadingTop)
                    ? null
                    : () => _onTop(row),
                icon: loadingTop
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.chevronsUp, size: 13),
                label: const Text('置顶', style: TextStyle(fontSize: 12)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: AppColors.red,
                ),
                onPressed: loadingCancel ? null : () => _onCancel(row),
                icon: loadingCancel
                    ? const SizedBox(
                        width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.x, size: 13),
                label: const Text('取消', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            row.seat != null && row.seat!.isNotEmpty
                ? '由 ${row.seat} 发起'
                : '外部发起',
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _platformTag(row.platform, accent, accentSoft),
              _metaCell(LucideIcons.hash, row.gid.toString()),
              Text(
                '${formatBytes(row.downloadedBytes)} / ',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              Text(
                formatBytes(row.totalBytes),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              if (row.status == GameStatus.downloading)
                _metaCell(LucideIcons.zap, formatSpeed(row.speed),
                    color: AppColors.iosBlue),
              if (row.status == GameStatus.downloading)
                Text(
                  '剩余 ${formatEta(row.etaMs)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: percent / 100,
                    backgroundColor: const Color(0xFFF3F4F6),
                    valueColor: AlwaysStoppedAnimation<Color>(_progressColor(row)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _progressLabel(row),
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _progressColor(DownloadTask row) {
    if (row.status == GameStatus.deleting || row.status == GameStatus.unknown) {
      return AppColors.red;
    }
    if (row.status == GameStatus.paused) return const Color(0xFFF59E0B);
    if (row.status == GameStatus.downloaded) return const Color(0xFF10B981);
    if (row.status == GameStatus.indexing) return const Color(0xFF6366F1);
    return AppColors.iosBlue;
  }

  String _progressLabel(DownloadTask row) {
    final pct = row.percent.toStringAsFixed(1);
    final s = row.status;
    if (s == GameStatus.downloading) return '$pct%';
    if (s == GameStatus.paused) return '已暂停 $pct%';
    if (s == GameStatus.indexing) return row.percent >= 99 ? '准备完成' : '准备 $pct%';
    if (s == GameStatus.unknown) return '未知 raw=${row.statusRaw}';
    return kGameStatusLabel[s] ?? '状态$s';
  }

  // ============== 小组件 ==============
  Widget _stateChip(GameRowState state, Color accent, Color accentSoft) {
    Color bg;
    Color fg;
    switch (state) {
      case GameRowState.installed:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF047857);
        break;
      case GameRowState.upgrade:
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFB45309);
        break;
      case GameRowState.deprecated:
        bg = const Color(0xFFF3F4F6);
        fg = const Color(0xFF6B7280);
        break;
      case GameRowState.pending:
        bg = accentSoft;
        fg = accent;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        kGameRowStateLabel[state] ?? '',
        style: TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _dlStateChip(DownloadTask row, Color accent, Color accentSoft) {
    final color = _progressColor(row);
    final label = kGameStatusLabel[row.status] ?? '状态${row.statusRaw ?? row.status}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _platformTag(String platform, Color accent, Color accentSoft) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        kPlatformLabel[platform] ?? platform,
        style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _metaCell(IconData icon, String text,
      {Color? color, bool bold = false}) {
    final c = color ?? const Color(0xFF6B7280);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: c),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: c,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ============== 闲置 Tab：底部批量操作栏 ==============
  Widget _buildBulkBar(GameLibraryState state) {
    // 选择范围 = 当前筛选/搜索后的可见闲置集合（与 Web selectableGames=filteredGames 对齐）
    final selectable = _filteredGames(state);
    if (selectable.isEmpty) return const SizedBox.shrink();

    final selectedRowKeys = state.selectedRowKeys;
    final selectedCount =
        selectable.where((g) => selectedRowKeys.contains(g.rowKey)).length;
    final isAll = selectable.isNotEmpty &&
        selectable.every((g) => selectedRowKeys.contains(g.rowKey));
    final isIndet = selectedCount > 0 && !isAll;

    final bulkProgress = state.bulkProgress;
    final bulkDeleting = bulkProgress != null;

    final btnLabel = bulkDeleting
        ? '批量删除中 ${bulkProgress.done}/${bulkProgress.total}…'
        : (selectedCount > 0 ? '批量删除 ($selectedCount)' : '批量删除');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          // 全选 / 取消全选（含 indeterminate）
          InkWell(
            onTap: bulkDeleting
                ? null
                : () {
                    if (isAll) {
                      _notifier.clearSelection();
                    } else {
                      _notifier.selectAll(selectable.map((g) => g.rowKey));
                    }
                  },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: isAll ? true : (isIndet ? null : false),
                      tristate: true,
                      onChanged: bulkDeleting
                          ? null
                          : (_) {
                              if (isAll) {
                                _notifier.clearSelection();
                              } else {
                                _notifier
                                    .selectAll(selectable.map((g) => g.rowKey));
                              }
                            },
                      activeColor: AppColors.iosBlue,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isAll ? '取消全选' : '全选',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '已选 $selectedCount / ${selectable.length}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: (selectedCount == 0 || bulkDeleting) ? null : _onBulkDelete,
            icon: bulkDeleting
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(LucideIcons.trash2, size: 13),
            label: Text(btnLabel, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
