import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// 网吧选项（用于复制布局时选择其他网吧）
class NetbarOption {
  final int? id;
  final String name;
  final String? domain;

  NetbarOption({this.id, required this.name, this.domain});
}

/// 机号选项
class SeatOption {
  final String id;
  final String name;

  SeatOption({required this.id, required this.name});
}

/// 桌面管理工具栏
class DesktopToolbar extends StatelessWidget {
  // 导航
  final VoidCallback onBack;

  // 筛选器
  final List<SeatOption> seatOptions;
  final String? selectedSeatId;
  final ValueChanged<String?> onSeatChanged;

  // 截图
  final bool screenshotLoading;
  final VoidCallback onScreenshot;

  // 分辨率
  final List<String> resolutionOptions;
  final String? currentResolution;
  final ValueChanged<String> onResolutionChanged;
  final ValueChanged<String>? onResolutionDelete;

  // 操作
  final VoidCallback onAddIcon;
  final VoidCallback onSave;
  final VoidCallback onForceUpdate;
  final VoidCallback? onCopyLayout;

  // 帮助
  final VoidCallback? onHelp;

  const DesktopToolbar({
    super.key,
    required this.onBack,
    required this.seatOptions,
    this.selectedSeatId,
    required this.onSeatChanged,
    required this.screenshotLoading,
    required this.onScreenshot,
    required this.resolutionOptions,
    this.currentResolution,
    required this.onResolutionChanged,
    this.onResolutionDelete,
    required this.onAddIcon,
    required this.onSave,
    required this.onForceUpdate,
    this.onCopyLayout,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFD7D9E0))),
      ),
      child: Row(
        children: [
          // Left section
          _buildLeftSection(),
          const Spacer(),
          // Right section
          _buildRightSection(),
        ],
      ),
    );
  }

  Widget _buildLeftSection() {
    return Row(
      children: [
        // Title
        const Text(
          '桌面管理',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),

        // Seat selector
        _buildDropdown<String?>(
          value: selectedSeatId,
          hint: '选择机号',
          items: seatOptions.map((s) => DropdownMenuItem(
            value: s.id,
            child: Text(s.name, style: const TextStyle(fontSize: 13)),
          )).toList(),
          onChanged: onSeatChanged,
          width: 120,
        ),
        const SizedBox(width: 8),

        // Screenshot button
        _buildGhostButton(
          label: '获取电脑截图',
          onTap: selectedSeatId != null && !screenshotLoading ? onScreenshot : null,
          loading: screenshotLoading,
        ),

        // Help button
        if (onHelp != null) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: onHelp,
            icon: Icon(LucideIcons.helpCircle, size: 18, color: Colors.grey.shade500),
            tooltip: '帮助',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ],
    );
  }

  Widget _buildRightSection() {
    return Row(
      children: [
        // Resolution selector
        if (resolutionOptions.isNotEmpty) ...[
          _buildResolutionDropdown(),
          const SizedBox(width: 8),
        ],

        // Copy layout
        if (onCopyLayout != null) ...[
          _buildGhostButton(
            label: '复制其他网吧',
            onTap: onCopyLayout,
          ),
          const SizedBox(width: 8),
        ],

        // Add icon
        _buildPrimaryButton(
          label: '添加图标',
          icon: LucideIcons.plus,
          onTap: onAddIcon,
        ),
        const SizedBox(width: 8),

        // Save
        _buildSuccessButton(
          label: '保存',
          onTap: onSave,
        ),
        const SizedBox(width: 8),

        // Force update
        _buildPrimaryButton(
          label: '强制更新桌面',
          onTap: onForceUpdate,
        ),
      ],
    );
  }

  Widget _buildResolutionDropdown() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentResolution,
          hint: Text('选择分辨率', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          isDense: true,
          onChanged: (v) {
            if (v != null) onResolutionChanged(v);
          },
          items: resolutionOptions.map((res) {
            return DropdownMenuItem<String>(
              value: res,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(res, style: const TextStyle(fontSize: 13)),
                  if (onResolutionDelete != null) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => onResolutionDelete!(res),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          icon: Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 130,
  }) {
    return Container(
      width: width,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          isExpanded: true,
          isDense: true,
          onChanged: onChanged,
          items: items,
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          icon: Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildGhostButton({
    required String label,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return SizedBox(
      height: 32,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.grey.shade600,
                ),
              )
            : Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14),
              const SizedBox(width: 4),
            ],
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

/// 分辨率切换器（固定位置）
class ResolutionSwitcher extends StatelessWidget {
  final List<String> options;
  final String? currentResolution;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onDelete;

  const ResolutionSwitcher({
    super.key,
    required this.options,
    this.currentResolution,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCDD2DF)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE1E5EF))),
            ),
            child: const Text(
              '切换分辨率',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),

          // Options
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '没有任何截图请先点击截图',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _buildDropdown(),
            ),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentResolution,
          isExpanded: true,
          isDense: true,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: options.map((res) {
            return DropdownMenuItem<String>(
              value: res,
              child: Row(
                children: [
                  Expanded(
                    child: Text(res, style: const TextStyle(fontSize: 13)),
                  ),
                  if (onDelete != null)
                    InkWell(
                      onTap: () => onDelete!(res),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: Colors.red.shade400,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ),
    );
  }
}
