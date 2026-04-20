import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/user_mock_data.dart';

class GroupSidebar extends StatefulWidget {
  final List<UserGroup> groups;
  final int? selectedGroupId;
  final ValueChanged<int> onSelectGroup;
  final VoidCallback onAddGroup;
  final String groupSearchQuery;
  final ValueChanged<String> onGroupSearchChanged;
  final ValueChanged<UserGroup>? onDeleteGroup;
  final double? width;

  const GroupSidebar({
    super.key,
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectGroup,
    required this.onAddGroup,
    required this.groupSearchQuery,
    required this.onGroupSearchChanged,
    this.onDeleteGroup,
    this.width = 240,
  });

  @override
  State<GroupSidebar> createState() => _GroupSidebarState();
}

class _GroupSidebarState extends State<GroupSidebar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.groupSearchQuery);
  }

  @override
  void didUpdateWidget(covariant GroupSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupSearchQuery != widget.groupSearchQuery && _searchController.text != widget.groupSearchQuery) {
      _searchController.text = widget.groupSearchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final groups = query.isEmpty
        ? widget.groups
        : widget.groups.where((g) => g.name.toLowerCase().contains(query)).toList();

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '用户分组',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                InkWell(
                  onTap: widget.onAddGroup,
                  borderRadius: BorderRadius.circular(4),
                  child: const Icon(LucideIcons.plus, size: 18, color: Colors.grey),
                ),
              ],
            ),
          ),
          
          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: widget.onGroupSearchChanged,
                decoration: const InputDecoration(
                  hintText: '搜索小组...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: Icon(LucideIcons.search, size: 14, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10), // Vertically center text
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),

          // All Members Item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: InkWell(
              onTap: () => widget.onSelectGroup(0), // 0 代表所有成员
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: widget.selectedGroupId == 0 ? Colors.blue.shade50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.user, 
                      size: 16, 
                      color: widget.selectedGroupId == 0 ? AppColors.iosBlue : Colors.grey.shade600
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '所有成员',
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.selectedGroupId == 0 ? AppColors.iosBlue : Colors.grey.shade700,
                        fontWeight: widget.selectedGroupId == 0 ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Group List Label
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 16, 8),
            child: Text(
              '小组列表',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),

          // Group List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                if (group.id == 0) return const SizedBox.shrink(); // Skip 'All Members' if it's in the list
                final isSelected = widget.selectedGroupId == group.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => widget.onSelectGroup(group.id),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.folder,
                                  size: 16,
                                  color: isSelected ? AppColors.iosBlue : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    group.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isSelected ? AppColors.iosBlue : Colors.grey.shade700,
                                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // 分组21不显示操作按钮（对标 Vue 端 UserPage.vue 第 45 行 group.id !== 21）
                      if (widget.onDeleteGroup != null && group.id != 21)
                        PopupMenuButton<String>(
                          tooltip: '更多',
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            LucideIcons.moreHorizontal,
                            size: 16,
                            color: Colors.grey.shade500,
                          ),
                          onSelected: (value) {
                            if (value == 'delete') widget.onDeleteGroup?.call(group);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                                  const SizedBox(width: 10),
                                  const Text('删除分组'),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
