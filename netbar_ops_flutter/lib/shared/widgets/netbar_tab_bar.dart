import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../utils/adaptive_show.dart';
import '../../features/netbar/data/netbar_api.dart';
import '../../features/netbar/data/netbar_pinyin_matcher.dart';
import '../../features/netbar/presentation/netbar_selector_modal.dart';
import '../../features/netbar/presentation/widgets/default_win_pwd_dialog.dart';
import '../../features/netbar/presentation/widgets/batch_reset_pwd_dialog.dart';
import '../../features/netbar/presentation/widgets/batch_update_program_dialog.dart';
import '../../features/netbar/presentation/widgets/totp_dialog.dart';
import '../providers/app_providers.dart';
import '../providers/netbar_tabs_provider.dart';
import '../providers/permission_provider.dart';

/// 分组颜色调色板 — 根据 groupName 的 hashCode 稳定映射
const _groupColors = <Color>[
  Color(0xFF3B82F6), // blue
  Color(0xFFF59E0B), // amber
  Color(0xFF10B981), // emerald
  Color(0xFFEF4444), // red
  Color(0xFF8B5CF6), // violet
  Color(0xFFEC4899), // pink
  Color(0xFF06B6D4), // cyan
  Color(0xFFF97316), // orange
];

Color _groupColor(String? groupName) {
  if (groupName == null || groupName.isEmpty) return const Color(0xFF9CA3AF); // grey
  return _groupColors[groupName.hashCode.abs() % _groupColors.length];
}

/// 网吧选项卡栏 - 类似浏览器标签页
class NetbarTabBar extends ConsumerStatefulWidget {
  const NetbarTabBar({super.key});

  @override
  ConsumerState<NetbarTabBar> createState() => _NetbarTabBarState();
}

class _NetbarTabBarState extends ConsumerState<NetbarTabBar> {
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = false;

  @override
  void initState() {
    super.initState();
    // 每分钟刷新一次显示时间
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_updateArrowVisibility);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.removeListener(_updateArrowVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!mounted) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    setState(() {
      _showLeftArrow = currentScroll > 0;
      _showRightArrow = currentScroll < maxScroll;
    });
  }

  void _checkOverflow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      setState(() {
        _showLeftArrow = _scrollController.offset > 0;
        _showRightArrow = maxScroll > 0 && _scrollController.offset < maxScroll;
      });
    });
  }

  void _scrollLeft() {
    final newOffset = (_scrollController.offset - 150).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollRight() {
    final newOffset = (_scrollController.offset + 150).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _syncCurrentNetbar() {
    final activeTab = ref.read(netbarTabsProvider).activeTab;
    if (activeTab == null) return;
    final current = ref.read(currentNetbarProvider);
    if (current.id == activeTab.id) return;
    ref.read(currentNetbarProvider.notifier).setNetbar(
      activeTab.id, activeTab.name, activeTab.status,
      subdomainFull: activeTab.subdomainFull,
      groupName: activeTab.groupName,
    );
  }

  void _openNewTab() {
    showAdaptive<void>(
      context,
      (context) => NetbarSelectorModal(
        selectedId: ref.read(netbarTabsProvider).activeTabId,
        onSelect: (id, name, status, {String? subdomainFull, String? groupName}) {
          ref.read(netbarTabsProvider.notifier).openTab(id, name, status, subdomainFull: subdomainFull, groupName: groupName);
          _syncCurrentNetbar();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(netbarTabsProvider);

    // 检查是否需要显示箭头
    _checkOverflow();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 左箭头
        if (_showLeftArrow) _buildScrollButton(isLeft: true),
        // 标签页列表（始终可滚动，支持鼠标滚轮）
        Expanded(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent && _scrollController.hasClients) {
                final offset = (_scrollController.offset + event.scrollDelta.dy).clamp(
                  0.0,
                  _scrollController.position.maxScrollExtent,
                );
                _scrollController.jumpTo(offset);
              }
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ...tabsState.tabs.map((tab) => _buildTab(
                    tab,
                    tabsState.activeTabId,
                    canClose: tabsState.tabs.length > 1,
                  )),
                ],
              ),
            ),
          ),
        ),
        // 右箭头
        if (_showRightArrow) _buildScrollButton(isLeft: false),
        // "+"按钮
        _buildAddButton(),
        // 搜索按钮 — 点击向右展开搜索框，下方实时显示结果
        _buildSearchButton(),
        // 视图按钮 — 打开分组总览弹层
        if (tabsState.tabs.length > 1) _buildViewButton(tabsState),
        // 设置按钮 — 齿轮图标下拉菜单（最右侧）
        _buildSettingsButton(),
      ],
    );
  }

  Widget _buildScrollButton({required bool isLeft}) {
    return _HoverableScrollButton(
      isLeft: isLeft,
      onTap: isLeft ? _scrollLeft : _scrollRight,
    );
  }

  Widget _buildViewButton(NetbarTabsState tabsState) {
    return _HoverableViewButton(
      onTap: () => _showTabOverview(tabsState),
    );
  }

  void _showTabOverview(NetbarTabsState tabsState) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => _TabOverviewDialog(
        tabsState: tabsState,
        onSwitch: (id) {
          Navigator.of(ctx).pop();
          ref.read(netbarTabsProvider.notifier).switchToTab(id);
          _syncCurrentNetbar();
        },
        onClose: (id) {
          ref.read(netbarTabsProvider.notifier).closeTab(id);
          _syncCurrentNetbar();
        },
      ),
    );
  }

  Widget _buildTab(OpenedNetbarTab tab, int? activeTabId, {required bool canClose}) {
    final isActive = tab.id == activeTabId;

    return _HoverableTab(
      isActive: isActive,
      onTap: () {
        ref.read(netbarTabsProvider.notifier).switchToTab(tab.id);
        _syncCurrentNetbar();
      },
      onClose: () {
        ref.read(netbarTabsProvider.notifier).closeTab(tab.id);
        _syncCurrentNetbar();
      },
      onContextMenu: (offset) => _showTabContextMenu(offset, tab),
      tab: tab,
      canClose: canClose,
    );
  }

  void _showTabContextMenu(Offset position, OpenedNetbarTab tab) {
    final notifier = ref.read(netbarTabsProvider.notifier);
    final tabs = ref.read(netbarTabsProvider).tabs;
    final idx = tabs.indexWhere((t) => t.id == tab.id);
    final hasRight = idx < tabs.length - 1;
    final hasLeft = idx > 0;
    final hasOthers = tabs.length > 1;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: 'close_right', enabled: hasRight, child: const Text('关闭右侧所有标签')),
        PopupMenuItem(value: 'close_left', enabled: hasLeft, child: const Text('关闭左侧所有标签')),
        PopupMenuItem(value: 'close_others', enabled: hasOthers, child: const Text('关闭其他标签')),
        PopupMenuItem(value: 'close_current', enabled: hasOthers, child: const Text('关闭当前标签')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'insert_after', child: Text('在当前标签后新增')),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'close_right':
          notifier.closeTabsToTheRight(tab.id);
        case 'close_left':
          notifier.closeTabsToTheLeft(tab.id);
        case 'close_others':
          notifier.closeOtherTabs(tab.id);
        case 'close_current':
          notifier.closeTab(tab.id);
        case 'insert_after':
          _openNewTabAfter(tab.id);
          return;
      }
      _syncCurrentNetbar();
    });
  }

  void _openNewTabAfter(int afterId) {
    showAdaptive<void>(
      context,
      (context) => NetbarSelectorModal(
        selectedId: ref.read(netbarTabsProvider).activeTabId,
        onSelect: (id, name, status, {String? subdomainFull, String? groupName}) {
          final existing = ref.read(netbarTabsProvider).tabs;
          if (existing.any((t) => t.id == id)) {
            ref.read(netbarTabsProvider.notifier).switchToTab(id);
          } else {
            final newTab = OpenedNetbarTab(
              id: id,
              name: name,
              status: status,
              subdomainFull: subdomainFull,
              groupName: groupName,
              openedAt: DateTime.now(),
            );
            ref.read(netbarTabsProvider.notifier).insertTabAfter(afterId, newTab);
          }
          _syncCurrentNetbar();
        },
      ),
    );
  }

  Widget _buildSearchButton() {
    return _HoverableSearchButton(
      onSelectNetbar: (n) {
        ref.read(netbarTabsProvider.notifier).openTab(
              n.id,
              n.name,
              n.status,
              subdomainFull: n.subdomainFull,
              groupName: n.group,
            );
        _syncCurrentNetbar();
      },
    );
  }

  Widget _buildAddButton() {
    return _HoverableAddButton(onTap: _openNewTab);
  }

  /// 设置菜单按钮（对标 Vue 端 NetbarPage.vue 第 136-158 行）
  Widget _buildSettingsButton() {
    final perm = ref.watch(permissionProvider);

    // 菜单项列表（根据权限动态构建）
    // 对标 Vue 端 hasSettingItems computed（第 534-536 行）
    final items = <PopupMenuEntry<String>>[];

    // "默认服务端Windows密码" — 非总部用户 + 有权限时显示
    // 对标 Vue 端 v-if="!isHQUser && canServerWinPwd"
    if (!perm.isHQUser && perm.hasDetailPermission('服务端Windows密码')) {
      items.add(const PopupMenuItem(value: 'defaultWinPwd', child: Text('默认服务端Windows密码', style: TextStyle(fontSize: 14))));
    }

    // "批量重置Windows密码"
    if (perm.hasDetailPermission('批量清除Windows密码')) {
      items.add(const PopupMenuItem(value: 'batchResetPwd', child: Text('批量重置Windows密码', style: TextStyle(fontSize: 14))));
    }

    // "批量更新程序"
    if (perm.hasDetailPermission('更新')) {
      items.add(const PopupMenuItem(value: 'batchUpdate', child: Text('批量更新程序', style: TextStyle(fontSize: 14))));
    }

    // "生成超级密码"
    if (perm.hasDetailPermission('生成超级密码')) {
      items.add(const PopupMenuItem(value: 'superPwd', child: Text('生成超级密码', style: TextStyle(fontSize: 14))));
    }

    // 无可见项则不渲染按钮
    if (items.isEmpty) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: '设置',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (value) {
        switch (value) {
          case 'defaultWinPwd':
            showAdaptive<void>(context, (_) => const DefaultWinPwdDialog(), routeName: '/dialog/default-win-pwd');
            break;
          case 'batchResetPwd':
            showAdaptive<void>(context, (_) => const BatchResetPwdDialog(), routeName: '/dialog/batch-reset-pwd');
            break;
          case 'batchUpdate':
            showAdaptive<void>(context, (_) => const BatchUpdateProgramDialog(), routeName: '/dialog/batch-update-program');
            break;
          case 'superPwd':
            showAdaptive<void>(context, (_) => const TotpDialog(), routeName: '/dialog/totp');
            break;
        }
      },
      itemBuilder: (_) => items,
      child: _HoverableSettingsIcon(),
    );
  }
}

/// 带 Hover 效果的滚动按钮
class _HoverableScrollButton extends StatefulWidget {
  final bool isLeft;
  final VoidCallback onTap;

  const _HoverableScrollButton({
    required this.isLeft,
    required this.onTap,
  });

  @override
  State<_HoverableScrollButton> createState() => _HoverableScrollButtonState();
}

class _HoverableScrollButtonState extends State<_HoverableScrollButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 24,
          height: 32,
          margin: EdgeInsets.only(
            left: widget.isLeft ? 0 : 2,
            right: widget.isLeft ? 2 : 0,
          ),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.shade200 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Icon(
            widget.isLeft ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
            size: 14,
            color: _isHovered ? Colors.grey.shade700 : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

/// 带 Hover 效果的 Tab
class _HoverableTab extends StatefulWidget {
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<Offset>? onContextMenu;
  final OpenedNetbarTab tab;
  final bool canClose;

  const _HoverableTab({
    required this.isActive,
    required this.onTap,
    required this.onClose,
    this.onContextMenu,
    required this.tab,
    this.canClose = true,
  });

  @override
  State<_HoverableTab> createState() => _HoverableTabState();
}

class _HoverableTabState extends State<_HoverableTab> {
  bool _isHovered = false;
  bool _isCloseHovered = false;

  static const Color _activeTabColor = Color(0xFF07C160);

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive;
    final canClose = widget.canClose;
    final closeHovered = canClose && _isCloseHovered;

    // 计算背景色
    Color bgColor;
    if (isActive) {
      bgColor = _isHovered ? _activeTabColor.withValues(alpha: 0.85) : _activeTabColor;
    } else {
      bgColor = _isHovered ? Colors.grey.shade200 : Colors.grey.shade100;
    }

    final groupColor = _groupColor(widget.tab.groupName);
    final tooltipText = widget.tab.groupName != null && widget.tab.groupName!.isNotEmpty
        ? '${widget.tab.groupName} · ${widget.tab.name}'
        : widget.tab.name;

    return Tooltip(
      message: tooltipText,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onContextMenu != null
              ? (details) => widget.onContextMenu!(details.globalPosition)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
              border: isActive ? null : Border.all(color: Colors.grey.shade200),
              boxShadow: isActive || _isHovered ? AppShadows.sm : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 分组色标
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white.withValues(alpha: 0.8) : groupColor,
                    shape: BoxShape.circle,
                    border: isActive ? Border.all(color: groupColor, width: 1.5) : null,
                  ),
                ),
                const SizedBox(width: 6),
                // 网吧名称
                Text(
                  widget.tab.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? Colors.white : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              const SizedBox(width: 6),
              // 打开时长标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.tab.formattedDuration,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : Colors.grey.shade500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 关闭按钮
              MouseRegion(
                cursor: canClose ? SystemMouseCursors.click : SystemMouseCursors.basic,
                onEnter: canClose ? (_) => setState(() => _isCloseHovered = true) : null,
                onExit: canClose ? (_) => setState(() => _isCloseHovered = false) : null,
                child: GestureDetector(
                  onTap: canClose ? widget.onClose : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: closeHovered
                          ? (isActive ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade300)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      LucideIcons.x,
                      size: 12,
                      color: !canClose
                          ? Colors.grey.shade400
                          : isActive
                              ? Colors.white.withValues(alpha: closeHovered ? 1.0 : 0.8)
                              : (closeHovered ? Colors.grey.shade700 : Colors.grey.shade400),
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 带 Hover 效果的添加按钮
/// 设置按钮图标（样式对齐 _HoverableAddButton）
class _HoverableSettingsIcon extends StatefulWidget {
  @override
  State<_HoverableSettingsIcon> createState() => _HoverableSettingsIconState();
}

class _HoverableSettingsIconState extends State<_HoverableSettingsIcon> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: _isHovered ? Colors.grey.shade200 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _isHovered ? Colors.grey.shade300 : Colors.grey.shade200,
          ),
          boxShadow: _isHovered ? AppShadows.sm : null,
        ),
        child: Icon(
          LucideIcons.settings,
          size: 16,
          color: _isHovered ? Colors.grey.shade700 : Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _HoverableAddButton extends StatefulWidget {
  final VoidCallback onTap;

  const _HoverableAddButton({required this.onTap});

  @override
  State<_HoverableAddButton> createState() => _HoverableAddButtonState();
}

class _HoverableAddButtonState extends State<_HoverableAddButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.shade200 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isHovered ? Colors.grey.shade300 : Colors.grey.shade200,
            ),
            boxShadow: _isHovered ? AppShadows.sm : null,
          ),
          child: Icon(
            LucideIcons.plus,
            size: 16,
            color: _isHovered ? Colors.grey.shade700 : Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

/// 带 Hover 效果的视图按钮
class _HoverableViewButton extends StatefulWidget {
  final VoidCallback onTap;

  const _HoverableViewButton({required this.onTap});

  @override
  State<_HoverableViewButton> createState() => _HoverableViewButtonState();
}

class _HoverableViewButtonState extends State<_HoverableViewButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '标签总览',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered ? Colors.grey.shade200 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovered ? Colors.grey.shade300 : Colors.grey.shade200,
              ),
              boxShadow: _isHovered ? AppShadows.sm : null,
            ),
            child: Icon(
              LucideIcons.layoutGrid,
              size: 16,
              color: _isHovered ? Colors.grey.shade700 : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 标签总览弹层 — 按分组展示所有已开网吧，支持搜索
class _TabOverviewDialog extends StatefulWidget {
  final NetbarTabsState tabsState;
  final ValueChanged<int> onSwitch;
  final ValueChanged<int> onClose;

  const _TabOverviewDialog({
    required this.tabsState,
    required this.onSwitch,
    required this.onClose,
  });

  @override
  State<_TabOverviewDialog> createState() => _TabOverviewDialogState();
}

class _TabOverviewDialogState extends State<_TabOverviewDialog> {
  String _query = '';

  Map<String, List<OpenedNetbarTab>> _buildGrouped() {
    final grouped = <String, List<OpenedNetbarTab>>{};
    final q = _query.toLowerCase();
    for (final tab in widget.tabsState.tabs) {
      final group = tab.groupName ?? '未分组';
      if (q.isNotEmpty &&
          !tab.name.toLowerCase().contains(q) &&
          !group.toLowerCase().contains(q)) {
        continue;
      }
      grouped.putIfAbsent(group, () => []).add(tab);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _buildGrouped();
    final sortedGroups = grouped.keys.toList()..sort();
    final matchCount = grouped.values.fold<int>(0, (s, l) => s + l.length);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 60),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(LucideIcons.layoutGrid, size: 18, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    '已打开 ${widget.tabsState.tabs.length} 个网吧',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, size: 18, color: Colors.grey.shade400),
                    splashRadius: 16,
                  ),
                ],
              ),
            ),
            // 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          hintText: '搜索网吧名称或分组...',
                          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade100),
            // 分组列表
            if (sortedGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '无匹配结果',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: sortedGroups.length,
                  itemBuilder: (context, gi) {
                    final group = sortedGroups[gi];
                    final tabs = grouped[group]!;
                    final groupColor = _groupColor(group);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 分组标题
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: groupColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                group,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${tabs.length})',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                        // 网吧列表
                        ...tabs.map((tab) {
                          final isActive = tab.id == widget.tabsState.activeTabId;
                          return _OverviewTabItem(
                            tab: tab,
                            isActive: isActive,
                            groupColor: groupColor,
                            canClose: widget.tabsState.tabs.length > 1,
                            onTap: () => widget.onSwitch(tab.id),
                            onClose: () => widget.onClose(tab.id),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 弹层中的单个网吧条目
class _OverviewTabItem extends StatefulWidget {
  final OpenedNetbarTab tab;
  final bool isActive;
  final Color groupColor;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _OverviewTabItem({
    required this.tab,
    required this.isActive,
    required this.groupColor,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_OverviewTabItem> createState() => _OverviewTabItemState();
}

class _OverviewTabItemState extends State<_OverviewTabItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? widget.groupColor.withValues(alpha: 0.08)
                : _isHovered
                    ? Colors.grey.shade50
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isActive
                ? Border.all(color: widget.groupColor.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              // 色标
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.groupColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // 名称
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.tab.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isActive ? widget.groupColor : Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已打开 ${widget.tab.formattedDuration}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              // 当前标记
              if (widget.isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.groupColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '当前',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: widget.groupColor,
                    ),
                  ),
                ),
              // 关闭按钮
              if (widget.canClose && _isHovered) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(LucideIcons.x, size: 14, color: Colors.grey.shade400),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// 可展开的搜索按钮：
/// - 默认：32x32 图标按钮（跟 + / ▣ / ⚙ 同尺寸）
/// - 点击展开为约 240px 宽搜索框，下方浮层实时显示结果（最多 10 条）
/// - Esc / 点 ✕ / 选中结果 → 收起
/// - Enter → 选中第一个结果
class _HoverableSearchButton extends ConsumerStatefulWidget {
  final ValueChanged<Netbar> onSelectNetbar;
  const _HoverableSearchButton({required this.onSelectNetbar});

  @override
  ConsumerState<_HoverableSearchButton> createState() =>
      _HoverableSearchButtonState();
}

class _HoverableSearchButtonState
    extends ConsumerState<_HoverableSearchButton> {
  static const double _collapsedWidth = 32;
  static const double _expandedWidth = 240;
  static const int _maxResults = 10;

  bool _isExpanded = false;
  bool _isHovered = false;
  String _query = '';

  final _focusNode = FocusNode();
  final _controller = TextEditingController();
  final _portalController = OverlayPortalController();
  final _link = LayerLink();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _expand() {
    setState(() => _isExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _collapse() {
    _focusNode.unfocus();
    _portalController.hide();
    setState(() {
      _isExpanded = false;
      _query = '';
    });
    _controller.clear();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    if (v.isNotEmpty) {
      _portalController.show();
    } else {
      _portalController.hide();
    }
  }

  List<Netbar> _filterResults(List<Netbar> all) {
    if (_query.isEmpty) return const [];
    final filtered =
        all.where((n) => NetbarMatcher.match(n, _query)).toList();
    filtered.sort((a, b) => a.id.compareTo(b.id));
    return filtered.take(_maxResults).toList();
  }

  void _selectFirst() {
    final asyncRes = ref.read(netbarListProvider);
    asyncRes.whenData((response) {
      final results = _filterResults(response.merchants);
      if (results.isNotEmpty) {
        widget.onSelectNetbar(results.first);
        _collapse();
      }
    });
  }

  void _selectNetbar(Netbar n) {
    widget.onSelectNetbar(n);
    _collapse();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (_) => _buildOverlay(),
        child: MouseRegion(
          cursor: _isExpanded
              ? SystemMouseCursors.text
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _isExpanded ? _expandedWidth : _collapsedWidth,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: _isHovered || _isExpanded
                  ? Colors.grey.shade200
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovered || _isExpanded
                    ? Colors.grey.shade300
                    : Colors.grey.shade200,
              ),
              boxShadow: _isHovered ? AppShadows.sm : null,
            ),
            child: _isExpanded ? _buildExpanded() : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    return GestureDetector(
      onTap: _expand,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Icon(
          LucideIcons.search,
          size: 16,
          color: _isHovered ? Colors.grey.shade700 : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.escape) {
                    _collapse();
                    return KeyEventResult.handled;
                  }
                  if (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                    _selectFirst();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                decoration: const InputDecoration(
                  hintText: '搜索网吧...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          GestureDetector(
            onTap: _collapse,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(LucideIcons.x,
                  size: 14, color: Colors.grey.shade500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final asyncRes = ref.watch(netbarListProvider);
    return Positioned(
      width: 320,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(8),
          shadowColor: Colors.black.withValues(alpha: 0.2),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: asyncRes.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '加载失败: $e',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
              data: (response) {
                final results = _filterResults(response.merchants);
                if (results.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '未找到匹配的网吧',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: Colors.grey.shade100),
                  itemBuilder: (ctx, i) {
                    final n = results[i];
                    return InkWell(
                      onTap: () => _selectNetbar(n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: n.status == 'online'
                                    ? const Color(0xFF10B981)
                                    : Colors.grey.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    n.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (n.group.isNotEmpty)
                                    Text(
                                      n.group,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
