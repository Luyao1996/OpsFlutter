import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../features/netbar/presentation/netbar_selector_modal.dart';
import '../providers/netbar_tabs_provider.dart';

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

  void _openNewTab() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: NetbarSelectorModal(
          selectedId: ref.read(netbarTabsProvider).activeTabId,
          onSelect: (id, name, status, {String? subdomainFull, String? groupName}) {
            ref.read(netbarTabsProvider.notifier).openTab(id, name, status, subdomainFull: subdomainFull);
          },
        ),
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
        // 标签页列表（可滚动，内部Tab可缩小）
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabCount = tabsState.tabs.length;
              final addButtonWidth = 36.0; // 添加按钮宽度
              final availableWidth = constraints.maxWidth - addButtonWidth;
              final minTabWidth = 130.0;
              final totalMinWidth = tabCount * (minTabWidth + 2); // 2 for margin

              // 如果空间足够所有Tab以最小宽度显示，不需要滚动
              final needsScroll = totalMinWidth > availableWidth;

              if (!needsScroll && tabCount > 0) {
                // 不需要滚动，Tab可以压缩或扩展
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ...tabsState.tabs.map((tab) => Flexible(
                      child: _buildTab(
                        tab,
                        tabsState.activeTabId,
                        flexible: true,
                        canClose: tabsState.tabs.length > 1,
                      ),
                    )),
                    _buildAddButton(),
                  ],
                );
              }

              // 需要滚动
              return SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ...tabsState.tabs.map((tab) => _buildTab(
                      tab,
                      tabsState.activeTabId,
                      flexible: false,
                      canClose: tabsState.tabs.length > 1,
                    )),
                    _buildAddButton(),
                  ],
                ),
              );
            },
          ),
        ),
        // 右箭头
        if (_showRightArrow) _buildScrollButton(isLeft: false),
      ],
    );
  }

  Widget _buildScrollButton({required bool isLeft}) {
    return _HoverableScrollButton(
      isLeft: isLeft,
      onTap: isLeft ? _scrollLeft : _scrollRight,
    );
  }

  Widget _buildTab(OpenedNetbarTab tab, int? activeTabId, {bool flexible = false, required bool canClose}) {
    final isActive = tab.id == activeTabId;

    return _HoverableTab(
      isActive: isActive,
      onTap: () => ref.read(netbarTabsProvider.notifier).switchToTab(tab.id),
      onClose: () => ref.read(netbarTabsProvider.notifier).closeTab(tab.id),
      tab: tab,
      flexible: flexible,
      canClose: canClose,
    );
  }

  Widget _buildAddButton() {
    return _HoverableAddButton(onTap: _openNewTab);
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
  final OpenedNetbarTab tab;
  final bool flexible;
  final bool canClose;

  const _HoverableTab({
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.tab,
    this.flexible = false,
    this.canClose = true,
  });

  @override
  State<_HoverableTab> createState() => _HoverableTabState();
}

class _HoverableTabState extends State<_HoverableTab> {
  bool _isHovered = false;
  bool _isCloseHovered = false;

  static const Color _activeTabColor = Color(0xFF07C160);
  static const double _minTabWidth = 130.0;

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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          constraints: BoxConstraints(minWidth: widget.flexible ? _minTabWidth : 0),
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
              // 网吧名称
              Flexible(
                child: Text(
                  widget.tab.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? Colors.white : Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
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
    );
  }
}

/// 带 Hover 效果的添加按钮
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
