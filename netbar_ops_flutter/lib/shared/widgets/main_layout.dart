import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../providers/netbar_tabs_provider.dart';
import '../../features/netbar/presentation/netbar_selector_modal.dart';
import 'netbar_tab_bar.dart';
import 'upload_queue_overlay.dart';

/// 主布局 - 对应 Vue 的 ClientMainLayout
class MainLayout extends ConsumerStatefulWidget {
  final Widget child;

  const MainLayout({super.key, required this.child});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  bool _isSystemMenuOpen = false;
  bool _isOpsMenuOpen = false;
  bool _isProfileOpen = false;

  @override
  void initState() {
    super.initState();
    // 加载用户信息和统计
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authNotifierProvider.notifier).loadCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final stats = ref.watch(dashboardStatsProvider);
    final tabsState = ref.watch(netbarTabsProvider);
    final isNarrow = MediaQuery.of(context).size.width < 900 ||
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;

    // 同步活动标签到 currentNetbarProvider
    _syncActiveTab(tabsState);

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Stack(
        children: [
          Column(
            children: [
              // 顶栏
              _buildHeader(authState, isNarrow),
              // 主内容
              Expanded(child: widget.child),
            ],
          ),
          // 状态Pills浮动在右上角内容区域
          if (!isNarrow)
            Positioned(
              top: 56 + 8, // header高度 + 间距
              right: 24,
              child: _buildStatusPills(stats),
            ),
          const UploadQueueOverlay(),
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
          ref.read(currentNetbarProvider.notifier).setNetbar(
            activeTab.id,
            activeTab.name,
            activeTab.status,
          );
        });
      }
    }
  }

  Widget _buildNetbarPicker(bool isNarrow) {
    final currentNetbar = ref.watch(currentNetbarProvider);
    final name = (currentNetbar.name?.isNotEmpty == true) ? currentNetbar.name! : '选择网吧';
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
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(LucideIcons.chevronDown, size: 16, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }

  void _showNetbarSelector() {
    final tabsNotifier = ref.read(netbarTabsProvider.notifier);
    final current = ref.read(currentNetbarProvider);
    final isMobile = MediaQuery.of(context).size.width < 768 ||
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(32),
        child: NetbarSelectorModal(
          selectedId: current.id,
          onSelect: (id, name, status) {
            tabsNotifier.openTab(id, name, status);
            ref.read(currentNetbarProvider.notifier).setNetbar(id, name, status);
          },
          isMobile: isMobile,
        ),
      ),
    );
  }

  Widget _buildHeader(AuthState authState, bool isNarrow) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24),
      child: Row(
        children: [
          // 左侧: Logo & 菜单
          _buildLeftSection(),
          const SizedBox(width: 24),
          Container(width: 1, height: 24, color: Colors.grey.shade200),
          const SizedBox(width: 24),
          // 网吧选择：桌面用标签栏，移动用单个选择按钮
          Expanded(
            child: isNarrow ? _buildNetbarPicker(isNarrow) : NetbarTabBar(),
          ),
          const SizedBox(width: 12),
          // 右侧: 运维、通知、用户
          _buildRightSection(authState, isNarrow),
        ],
      ),
    );
  }

  Widget _buildLeftSection() {
    return Row(
      children: [
        // 系统菜单按钮
        PopupMenuButton<String>(
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (path) => context.go(path),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: _isSystemMenuOpen ? Colors.black.withValues(alpha: 0.05) : Colors.transparent,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.iosBlue,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [BoxShadow(color: AppColors.iosBlue.withValues(alpha: 0.3), blurRadius: 8)],
                  ),
                  child: const Icon(LucideIcons.menu, size: 18, color: Colors.white),
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            _buildMenuItem('概览', '/dashboard', LucideIcons.layoutDashboard, Colors.blue),
            _buildMenuItem('网吧管理', '/monitor', LucideIcons.network, Colors.indigo),
            _buildMenuItem('资源管理', '/resource-management', LucideIcons.database, Colors.orange),
            _buildMenuItem('用户账户', '/user-management', LucideIcons.users, Colors.purple),
            _buildMenuItem('监控中心', '/channel-monitor', LucideIcons.monitor, Colors.green),
            _buildMenuItem('系统日志', '/system-logs', LucideIcons.fileText, Colors.grey),
            _buildMenuItem('安全中心', '#', LucideIcons.shield, Colors.red),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(String label, String path, IconData icon, Color color) {
    return PopupMenuItem(
      value: path,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStatusPills(AsyncValue stats) {
    return stats.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            _buildPill('客户机', data.onlineDesktops.toString(), AppColors.iosBlue, true),
            _buildPill('运行', '${data.serverUptime}天', null, false),
            _buildPill('VIP', '${data.vipDays}天', null, false),
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
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)),
            const SizedBox(width: 8),
          ],
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.grey.shade900 : Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSection(AuthState authState, bool isNarrow) {
    return Row(
      children: [
        // 运维管理下拉
        PopupMenuButton<String>(
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (path) => context.go(path),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 12, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(LucideIcons.wrench, size: 16, color: AppColors.iosBlue),
                if (!isNarrow) ...[
                  const SizedBox(width: 6),
                  const Text('运维管理', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 4), // Added small spacing before chevron
                  Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade400),
                ],
              ],
            ),
          ),
          itemBuilder: (context) => [
            _buildMenuItem('通道管理', '/channel-management', LucideIcons.activity, AppColors.iosBlue),
            _buildMenuItem('桌面管理', '/desktop-management', LucideIcons.layoutGrid, Colors.orange),
          ],
        ),
        const SizedBox(width: 8),
        // 用户菜单（头像触发）
        PopupMenuButton<String>(
          offset: const Offset(0, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'profile') {
              _showUserProfile(authState);
            } else if (value == 'logout') {
              ref.read(authNotifierProvider.notifier).logout();
              context.go('/login');
            } else if (value == 'settings') {
              context.go('/settings');
            }
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.blueGradient),
                  ),
                  child: Center(
                    child: Text(
                      (authState.user?.name ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (!isNarrow) ...[
                  const SizedBox(width: 8),
                  Text(
                    authState.user?.name ?? '加载中...',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade400),
                ],
              ],
            ),
          ),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'profile', child: _buildMenuRow(LucideIcons.user, '个人资料')),
            PopupMenuItem(value: 'settings', child: _buildMenuRow(LucideIcons.settings, '设置')),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'logout',
              child: _buildMenuRow(LucideIcons.logOut, '退出登录', color: AppColors.red),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuRow(IconData icon, String label, {Color color = Colors.black}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color)),
      ],
    );
  }

  void _showUserProfile(AuthState authState) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: AppColors.blueGradient),
              ),
              child: Center(
                child: Text(
                  (authState.user?.name ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authState.user?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  authState.user?.role == 'admin' ? '管理员' : '操作员',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.user),
              title: const Text('个人资料'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(LucideIcons.settings),
              title: const Text('设置'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authNotifierProvider.notifier).logout();
              context.go('/login');
            },
            icon: const Icon(LucideIcons.logOut, size: 16, color: AppColors.red),
            label: const Text('退出登录', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }
}
