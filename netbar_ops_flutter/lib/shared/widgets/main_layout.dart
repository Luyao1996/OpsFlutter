import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/storage/token_store.dart';
import '../providers/app_providers.dart';
import '../providers/netbar_tabs_provider.dart';
import '../../features/netbar/presentation/netbar_selector_modal.dart';
import '../../features/netbar/data/netbar_api.dart';
import '../../features/dashboard/presentation/dashboard_page.dart';
import '../../features/dashboard/data/dashboard_api.dart';
import 'netbar_tab_bar.dart';
import 'upload_queue_overlay.dart';
import '../../features/user/presentation/user_profile_dialog.dart';
import '../services/terminal_window_bridge.dart';
import '../services/terminal_dock_actions.dart';
import 'terminal_dock_bar.dart';
import '../providers/terminal_dock_provider.dart';
import '../../core/network/api_client.dart';
import '../../core/responsive/responsive.dart';
import '../../features/channel/presentation/platform_helper.dart';

/// 主布局 - 对应 Vue 的 ClientMainLayout
class MainLayout extends ConsumerStatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  final bool _isSystemMenuOpen = false;
  final bool _isOpsMenuOpen = false;
  final bool _isProfileOpen = false;
  bool _tabsInitialized = false;

  @override
  void initState() {
    super.initState();
    // 加载用户信息和统计
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final container = ProviderScope.containerOf(context, listen: false);
      TerminalWindowBridge.initMainWindowHandler(container);
      TokenStore.onBeforeClearAuth = () async {
        await TerminalDockActions.closeAllMinimized(container);
        await TerminalWindowBridge.closeAllSubWindows();
        container.read(terminalDockProvider.notifier).reset();
      };
      ApiClient.onUnauthorized = () {
        container.read(authNotifierProvider.notifier).forceLogout();
      };
      ref.read(authNotifierProvider.notifier).loadCurrentUser();
      _initializeNetbarTabs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final tabsState = ref.watch(netbarTabsProvider);
    final isNarrow = platformHelper.isMobile || context.isNarrow;

    // 同步活动标签到 currentNetbarProvider
    _syncActiveTab(tabsState);

    final content = Column(
      children: [
        // 顶栏
        _buildHeader(authState, isNarrow, stats),
        // 主内容
        Expanded(child: widget.child),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Stack(
        children: [
          if (platformHelper.isMobile)
            SafeArea(top: true, bottom: false, child: content)
          else
            content,
          if (platformHelper.isDesktop) const TerminalDockBar(),
        ],
      ),
    );
  }

  void _syncActiveTab(NetbarTabsState tabsState) {
    final activeTab = tabsState.activeTab;
    if (activeTab != null) {
      final currentNetbar = ref.read(currentNetbarProvider);
      if (currentNetbar.id != activeTab.id) {
        // 延迟同步避免在 build 中更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref
              .read(currentNetbarProvider.notifier)
              .setNetbar(activeTab.id, activeTab.name, activeTab.status, subdomainFull: activeTab.subdomainFull);
        });
      }
    }
  }

  Future<void> _initializeNetbarTabs() async {
    if (_tabsInitialized) return;
    _tabsInitialized = true;

    final netbarApi = NetbarApi();
    try {
      final netbars = await netbarApi.getList();
      if (!mounted) return;

      final tabsNotifier = ref.read(netbarTabsProvider.notifier);
      final currentNotifier = ref.read(currentNetbarProvider.notifier);
      final existing = ref.read(netbarTabsProvider);

      if (netbars.isEmpty) {
        await tabsNotifier.resetAll();
        await currentNotifier.clear();
        return;
      }

      final byId = {for (final n in netbars) n.id: n};

      // 过滤掉已无权限的历史标签
      final keptTabs = existing.tabs.where((t) => byId.containsKey(t.id)).toList();
      int? activeId = existing.activeTabId;
      if (activeId == null || !byId.containsKey(activeId)) {
        activeId = keptTabs.isNotEmpty ? keptTabs.last.id : netbars.first.id;
      }

      if (keptTabs.isEmpty) {
        // 无可用历史标签：打开第一个可访问网吧
        final target = netbars.first;
        await tabsNotifier.openTab(target.id, target.name, target.status, subdomainFull: target.subdomainFull);
        await currentNotifier.setNetbar(target.id, target.name, target.status, subdomainFull: target.subdomainFull);
        return;
      }

      // 用后端返回的最新 name/status 同步标签信息
      final syncedTabs = keptTabs
          .map((t) => OpenedNetbarTab(
                id: t.id,
                name: byId[t.id]!.name,
                status: byId[t.id]!.status,
                subdomainFull: byId[t.id]!.subdomainFull,
                openedAt: t.openedAt,
              ))
          .toList();
      await tabsNotifier.replaceAll(NetbarTabsState(tabs: syncedTabs, activeTabId: activeId));
      final activeNetbar = byId[activeId]!;
      await currentNotifier.setNetbar(activeNetbar.id, activeNetbar.name, activeNetbar.status, subdomainFull: activeNetbar.subdomainFull);
    } catch (_) {
      // 网络或数据错误时保持现状，避免阻塞 UI
    }
  }

  Widget _buildNetbarPicker(bool isNarrow) {
    final currentNetbar = ref.watch(currentNetbarProvider);
    final name = (currentNetbar.name?.isNotEmpty == true)
        ? currentNetbar.name!
        : '选择网吧';
    final status = currentNetbar.status;
    final statusColor = status == 'online'
        ? AppColors.iosBlue
        : status == 'offline'
        ? Colors.red
        : Colors.orange;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: _showNetbarSelector,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 10 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                LucideIcons.chevronDown,
                size: 16,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNetbarSelector() {
    final tabsNotifier = ref.read(netbarTabsProvider.notifier);
    final current = ref.read(currentNetbarProvider);
    final isMobile =
        platformHelper.isMobile || MediaQuery.of(context).size.width < 768;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(isMobile ? 12 : 32),
        child: NetbarSelectorModal(
          selectedId: current.id,
          onSelect: (id, name, status, {subdomainFull}) {
            tabsNotifier.openTab(id, name, status, subdomainFull: subdomainFull);
            ref
                .read(currentNetbarProvider.notifier)
                .setNetbar(id, name, status, subdomainFull: subdomainFull);
          },
          isMobile: isMobile,
        ),
      ),
    );
  }

  /// 全局页面路由（不需要显示网吧 Tab 栏）
  static const _globalRoutes = ['/dashboard', '/user-management', '/system-logs'];

  /// 判断当前是否是全局页面
  bool _isGlobalPage() {
    final location = GoRouterState.of(context).uri.path;
    return _globalRoutes.any((route) => location == route || location.startsWith('$route/'));
  }

  Widget _buildHeader(AuthState authState, bool isNarrow, AsyncValue<DashboardStats> stats) {
    final isGlobalPage = _isGlobalPage();

    if (isNarrow) {
      return Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _buildLeftSection(authState, isNarrow: true),
            const SizedBox(width: 10),
            // 全局页面不显示网吧选择器，网吧页面显示
            if (!isGlobalPage)
              Expanded(child: _buildNetbarPicker(true))
            else
              const Spacer(),
            const SizedBox(width: 10),
            _buildRightSection(authState, true),
          ],
        ),
      );
    }

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24),
      child: Row(
        children: [
          // 左侧: Logo & 菜单 & 页面名称
          _buildLeftSection(authState, isNarrow: isNarrow),
          const SizedBox(width: 24),
          // 全局页面不显示网吧选项卡，网吧页面显示
          if (!isGlobalPage) ...[
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: const NetbarTabBar()),
                  const SizedBox(width: 24),
                  _buildStatusPills(stats),
                ],
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 12),
          // 右侧: 用户菜单
          _buildRightSection(authState, isNarrow),
        ],
      ),
    );
  }

  /// 获取当前页面信息（名称、图标、颜色）
  ({String name, IconData icon, Color color}) _getCurrentPageInfo() {
    final location = GoRouterState.of(context).uri.path;

    if (location.startsWith('/dashboard')) {
      return (name: '概览', icon: LucideIcons.layoutDashboard, color: Colors.blue);
    } else if (location.startsWith('/monitor')) {
      return (name: '网吧管理', icon: LucideIcons.network, color: Colors.indigo);
    } else if (location.startsWith('/resource-management')) {
      return (name: '资源管理', icon: LucideIcons.database, color: Colors.orange);
    } else if (location.startsWith('/channel-management')) {
      return (name: '通道管理', icon: LucideIcons.activity, color: AppColors.iosBlue);
    } else if (location.startsWith('/desktop-management')) {
      return (name: '桌面管理', icon: LucideIcons.layoutGrid, color: Colors.teal);
    } else if (location.startsWith('/user-management')) {
      return (name: '用户账户', icon: LucideIcons.users, color: Colors.purple);
    } else if (location.startsWith('/channel-monitor')) {
      return (name: '监控中心', icon: LucideIcons.monitor, color: Colors.green);
    } else if (location.startsWith('/system-logs')) {
      return (name: '系统日志', icon: LucideIcons.fileText, color: Colors.grey);
    } else {
      return (name: '首页', icon: LucideIcons.home, color: AppColors.iosBlue);
    }
  }

  Widget _buildLeftSection(AuthState authState, {required bool isNarrow}) {
    final pageInfo = _getCurrentPageInfo();

    return Row(
      children: [
        // 系统菜单按钮
        PopupMenuButton<String>(
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          onSelected: (path) => context.go(path),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _isSystemMenuOpen
                  ? Colors.black.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.iosBlue,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.iosBlue.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    LucideIcons.menu,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          itemBuilder: (context) => [
            _buildMenuItem(
              '概览',
              '/dashboard',
              LucideIcons.layoutDashboard,
              Colors.blue,
            ),
            _buildMenuItem(
              '网吧管理',
              '/monitor',
              LucideIcons.network,
              Colors.indigo,
            ),
            _buildMenuItem(
              '资源管理',
              '/resource-management',
              LucideIcons.database,
              Colors.orange,
            ),
            _buildMenuItem(
              '通道管理',
              '/channel-management',
              LucideIcons.activity,
              AppColors.iosBlue,
            ),
            if (!platformHelper.isMobile)
              _buildMenuItem(
                '桌面管理',
                '/desktop-management',
                LucideIcons.layoutGrid,
                Colors.teal,
              ),
            // 总部管理员或分部管理员可以访问用户账户
            if (authState.user?.hasAdminAccess == true)
              _buildMenuItem(
                '用户账户',
                '/user-management',
                LucideIcons.users,
                Colors.purple,
              ),
            _buildMenuItem(
              '监控中心',
              '/channel-monitor',
              LucideIcons.monitor,
              Colors.green,
            ),
            _buildMenuItem(
              '系统日志',
              '/system-logs',
              LucideIcons.fileText,
              Colors.grey,
            ),
            _buildMenuItem('安全中心', '#', LucideIcons.shield, Colors.red),
          ],
        ),
        // 当前页面名称
        if (!isNarrow) ...[
          const SizedBox(width: 12),
          Icon(pageInfo.icon, size: 18, color: pageInfo.color),
          const SizedBox(width: 8),
          Text(
            pageInfo.name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String label,
    String path,
    IconData icon,
    Color color,
  ) {
    return PopupMenuItem(
      value: path,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPills(AsyncValue<DashboardStats> stats) {
    return stats.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade200.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            _buildPill(
              '终端',
              data.terminalTotal.toString(),
              AppColors.iosBlue,
              true,
            ),
            _buildPill('网吧', '${data.merchantTotal}', null, false),
            _buildPill('离线', '${data.merchantOffline}', Colors.red.shade400, false),
          ],
        ),
      ),
    );
  }

  Widget _buildPill(String label, String value, Color? dotColor, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        boxShadow: active ? AppShadows.sm : null,
      ),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: active ? Colors.grey.shade900 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSection(AuthState authState, bool isNarrow) {
    return Row(
      children: [
        // 用户菜单（头像触发）
        InkWell(
          onTap: () => _showUserProfile(authState),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            padding: EdgeInsets.all(isNarrow ? 10 : 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100.withOpacity(0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.blueGradient),
                  ),
                  child: Center(
                    child: Text(
                      (authState.user?.name ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (!isNarrow) ...[
                  const SizedBox(width: 8),
                  Text(
                    authState.user?.name ?? '加载中...',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: Colors.grey.shade400,
                  ), // Change chevronDown to chevronRight
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuRow(
    IconData icon,
    String label, {
    Color color = Colors.black,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showUserProfile(AuthState authState) {
    final isNarrow = platformHelper.isMobile || context.isNarrow;
    if (isNarrow) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.4),
        builder: (context) => const UserProfileDialog(asBottomSheet: true),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => const UserProfileDialog(),
    );
  }
}
