import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/adaptive_show.dart';
import 'netbar_selector_modal.dart';

/// 网吧选择器按钮 - 对应 Vue 的 NetbarPicker.vue
class NetbarPicker extends StatefulWidget {
  final int? selectedId;
  final String? selectedName;
  final String label;
  final Function(int id, String name, String status)? onSelect;

  const NetbarPicker({
    super.key,
    this.selectedId,
    this.selectedName,
    this.label = '当前网吧',
    this.onSelect,
  });

  @override
  State<NetbarPicker> createState() => _NetbarPickerState();
}

class _NetbarPickerState extends State<NetbarPicker> {
  bool _isHovered = false;

  void _showSelector() {
    showAdaptive<void>(
      context,
      (context) => NetbarSelectorModal(
        selectedId: widget.selectedId,
        onSelect: (id, name, status) {
          widget.onSelect?.call(id, name, status);
        },
      ),
      barrierColor: Colors.black.withValues(alpha: 0.5),
      routeName: '/dialog/netbar-selector',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showSelector,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppShadows.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 图标
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.iosBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.iosBlue.withValues(alpha: 0.1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.network, size: 18, color: AppColors.iosBlue),
              ),
              const SizedBox(width: 12),
              // 文本
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        widget.selectedName ?? '选择网吧',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
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

