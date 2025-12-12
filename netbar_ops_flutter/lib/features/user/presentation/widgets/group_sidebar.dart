import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/user_mock_data.dart';

class GroupSidebar extends StatelessWidget {
  final List<UserGroup> groups;
  final int? selectedGroupId;
  final ValueChanged<int> onSelectGroup;
  final VoidCallback onAddGroup;

  const GroupSidebar({
    super.key,
    required this.groups,
    required this.selectedGroupId,
    required this.onSelectGroup,
    required this.onAddGroup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
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
                  onTap: onAddGroup,
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
              child: const TextField(
                decoration: InputDecoration(
                  hintText: '搜索小组...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: Icon(LucideIcons.search, size: 14, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10), // Vertically center text
                  isDense: true,
                ),
                style: TextStyle(fontSize: 13),
              ),
            ),
          ),

          // All Members Item
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: InkWell(
              onTap: () => onSelectGroup(0), // 0 代表所有成员
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: selectedGroupId == 0 ? Colors.blue.shade50 : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.user, 
                      size: 16, 
                      color: selectedGroupId == 0 ? AppColors.iosBlue : Colors.grey.shade600
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '所有成员',
                      style: TextStyle(
                        fontSize: 14,
                        color: selectedGroupId == 0 ? AppColors.iosBlue : Colors.grey.shade700,
                        fontWeight: selectedGroupId == 0 ? FontWeight.w500 : FontWeight.normal,
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
                final isSelected = selectedGroupId == group.id;
                return InkWell(
                  onTap: () => onSelectGroup(group.id),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.folder, 
                          size: 16, 
                          color: isSelected ? AppColors.iosBlue : Colors.grey.shade400
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            group.name,
                            style: TextStyle(
                              fontSize: 14, // Match Vue font size
                              color: isSelected ? AppColors.iosBlue : Colors.grey.shade700,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
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
