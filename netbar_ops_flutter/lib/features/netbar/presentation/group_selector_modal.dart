import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../data/group_api.dart';

/// 分组列表 Provider
final groupListProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final api = NetbarGroupApi();
  final groups = await api.getAll();
  return groups.map((g) => g.name).toList();
});

/// 分组选择弹窗 - 对应 Vue 的 GroupSelectorModal.vue
class GroupSelectorModal extends ConsumerStatefulWidget {
  final String selectedGroup;
  final Function(String group)? onSelect;

  const GroupSelectorModal({
    super.key,
    required this.selectedGroup,
    this.onSelect,
  });

  @override
  ConsumerState<GroupSelectorModal> createState() => _GroupSelectorModalState();
}

class _GroupSelectorModalState extends ConsumerState<GroupSelectorModal> {
  String _searchQuery = '';
  List<String>? _cachedGroups;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _loadCache();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  Future<void> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList('ops_pro_group_cache');
    if (cached != null && mounted) {
      setState(() => _cachedGroups = cached);
    }
  }

  Future<void> _saveCache(List<String> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ops_pro_group_cache', groups);
  }

  void _handleSelect(String group) {
    widget.onSelect?.call(group);
    Navigator.of(context).pop();
  }

  List<String> _filterGroups(List<String> groups) {
    if (_searchQuery.isEmpty) return groups;
    final q = _searchQuery.toLowerCase();
    return groups.where((g) => g.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupListProvider);

    return ResponsiveDialogScaffold(
      title: '选择分组',
      maxWidth: 500,
      maxHeight: 600,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          _buildSearch(),
          Expanded(child: _buildContent(groupsAsync)),
        ],
      ),
      footer: _buildFooter(groupsAsync),
    );
  }

  Widget _buildSearch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: '搜索分组名称...',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  prefixIcon: Icon(LucideIcons.search, size: 18, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RefreshButton(onRefresh: () => ref.invalidate(groupListProvider)),
        ],
      ),
    );
  }

  Widget _buildContent(AsyncValue<List<String>> groupsAsync) {
    return groupsAsync.when(
      loading: () => _buildLoading(),
      error: (err, _) => _buildError(err.toString()),
      data: (groups) {
        _saveCache(groups);
        final filtered = _filterGroups(groups);
        return _buildGroupList(filtered);
      },
    );
  }

  Widget _buildLoading() {
    // 有缓存时显示缓存数据
    if (_cachedGroups != null && _cachedGroups!.isNotEmpty) {
      return _buildGroupList(_filterGroups(_cachedGroups!));
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32, height: 32,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.iosBlue),
          ),
          const SizedBox(height: 12),
          Text('加载中...', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(fontSize: 14, color: Colors.red.shade500)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(groupListProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(List<String> groups) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groups.length + 1, // +1 for "全部分组"
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildGroupItem('全部分组', isAll: true);
        }
        return _buildGroupItem(groups[index - 1]);
      },
    );
  }

  Widget _buildGroupItem(String group, {bool isAll = false}) {
    final isSelected = isAll
        ? (widget.selectedGroup == '全部分组' || widget.selectedGroup.isEmpty)
        : widget.selectedGroup == group;

    return _HoverableGroupItem(
      group: group,
      isSelected: isSelected,
      isAll: isAll,
      onTap: () => _handleSelect(group),
    );
  }

  Widget _buildFooter(AsyncValue<List<String>> groupsAsync) {
    final count = groupsAsync.whenOrNull(data: (g) => _filterGroups(g).length) ?? 0;
    return Row(
      children: [
        Text('共 $count 个分组', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const Spacer(),
        Text('Esc 关闭', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
      ],
    );
  }
}

/// 刷新按钮
class _RefreshButton extends StatefulWidget {
  final VoidCallback onRefresh;
  const _RefreshButton({required this.onRefresh});

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleRefresh() {
    _controller.repeat();
    widget.onRefresh();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _controller.stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _handleRefresh,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
            color: _isHovered ? Colors.grey.shade50 : Colors.white,
          ),
          child: RotationTransition(
            turns: _controller,
            child: Icon(
              LucideIcons.rotateCw,
              size: 18,
              color: _isHovered ? AppColors.iosBlue : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 可悬停的分组项
class _HoverableGroupItem extends StatefulWidget {
  final String group;
  final bool isSelected;
  final bool isAll;
  final VoidCallback onTap;

  const _HoverableGroupItem({
    required this.group,
    required this.isSelected,
    required this.isAll,
    required this.onTap,
  });

  @override
  State<_HoverableGroupItem> createState() => _HoverableGroupItemState();
}

class _HoverableGroupItemState extends State<_HoverableGroupItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppColors.iosBlue.withValues(alpha: 0.05)
                : _isHovered ? Colors.grey.shade50 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.iosBlue.withValues(alpha: 0.2)
                  : _isHovered ? Colors.grey.shade200 : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? AppColors.iosBlue
                      : (widget.isAll ? const Color(0xFFDBEAFE) : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.isAll ? LucideIcons.folderOpen : LucideIcons.folder,
                  size: 20,
                  color: widget.isSelected
                      ? Colors.white
                      : (widget.isAll ? AppColors.iosBlue : Colors.grey.shade500),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.group,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.isSelected ? AppColors.iosBlue : Colors.grey.shade900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.isSelected)
                Icon(LucideIcons.check, size: 18, color: AppColors.iosBlue),
            ],
          ),
        ),
      ),
    );
  }
}

