import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/adaptive_show.dart';
import 'group_selector_modal.dart';

/// 分组选择器按钮 - 对应 Vue 的 GroupPicker.vue
class GroupPicker extends StatefulWidget {
  final String selectedGroup;
  final Function(String group)? onSelect;
  final String label;

  const GroupPicker({
    super.key,
    this.selectedGroup = '全部分组',
    this.onSelect,
    this.label = '当前分组',
  });

  @override
  State<GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<GroupPicker> {
  bool _isHovered = false;

  void _openModal() {
    showAdaptive<void>(
      context,
      (context) => GroupSelectorModal(
        selectedGroup: widget.selectedGroup,
        onSelect: widget.onSelect,
      ),
      barrierColor: Colors.black.withValues(alpha: 0.5),
      routeName: '/dialog/group-selector',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _openModal,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: AppShadows.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: _isHovered 
                      ? AppColors.iosBlue.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.folderOpen,
                  size: 18,
                  color: _isHovered ? AppColors.iosBlue : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 12),
              // 文本
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          widget.selectedGroup.isEmpty ? '全部分组' : widget.selectedGroup,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _isHovered ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          LucideIcons.chevronDown,
                          size: 14,
                          color: _isHovered ? Colors.grey.shade600 : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

