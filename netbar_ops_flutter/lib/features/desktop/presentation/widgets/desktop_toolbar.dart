import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/desktop_model.dart';

class DesktopToolbar extends StatelessWidget {
  final List<DesktopLayout>? layouts;
  final DesktopLayout? currentLayout;
  final ValueChanged<DesktopLayout?>? onLayoutChanged;
  final String resolution;
  final ValueChanged<String> onResolutionChanged;
  final bool lockIcons;
  final ValueChanged<bool> onLockIconsChanged;
  final double scale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback onAlignGrid;
  final VoidCallback onAddIcon;
  final VoidCallback onBackgroundSettings;
  final VoidCallback onSave;
  final VoidCallback onBack;
  final VoidCallback? onRefresh;
  final VoidCallback? onDeleteLayout;

  const DesktopToolbar({
    super.key,
    this.layouts,
    this.currentLayout,
    this.onLayoutChanged,
    required this.resolution,
    required this.onResolutionChanged,
    required this.lockIcons,
    required this.onLockIconsChanged,
    required this.scale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onAlignGrid,
    required this.onAddIcon,
    required this.onBackgroundSettings,
    required this.onSave,
    required this.onBack,
    this.onRefresh,
    this.onDeleteLayout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          // Left block
          _buildGhostButton(icon: LucideIcons.arrowLeft, onTap: onBack),
          const SizedBox(width: 12),
          const Text('桌面管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(width: 12),
          _buildGhostButton(icon: LucideIcons.layoutGrid, onTap: onAlignGrid, tooltip: '对齐网格'),
          const SizedBox(width: 12),
          _buildZoomGroup(),
          const SizedBox(width: 12),
          _buildGhostButton(icon: LucideIcons.rotateCcw, onTap: onResetZoom, tooltip: '重置'),
          const Spacer(),
          // Right block
          _buildResolutionDropdown(),
          const SizedBox(width: 12),
          Row(
            children: [
              Checkbox(
                value: lockIcons,
                onChanged: (v) => onLockIconsChanged(v ?? false),
                activeColor: AppColors.iosBlue,
                visualDensity: VisualDensity.compact,
              ),
              const Text('锁定', style: TextStyle(fontSize: 13)),
            ],
          ),
          const SizedBox(width: 8),
          _buildGhostButton(icon: LucideIcons.image, onTap: onBackgroundSettings, tooltip: '桌面背景'),
          const SizedBox(width: 8),
          _buildGhostButton(icon: LucideIcons.plus, onTap: onAddIcon, label: '添加图标'),
          const SizedBox(width: 12),
          _buildPrimaryButton(),
        ],
      ),
    );
  }

  Widget _buildGhostButton({required IconData icon, required VoidCallback onTap, String? label, String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.grey.shade700,
          backgroundColor: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          minimumSize: const Size(40, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 18),
        label: label != null
            ? Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildZoomGroup() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          _buildSquareButton(LucideIcons.minus, onZoomOut),
          SizedBox(
            width: 56,
            child: Text(
              '${(scale * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _buildSquareButton(LucideIcons.plus, onZoomIn),
        ],
      ),
    );
  }

  Widget _buildSquareButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildResolutionDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: resolution,
          onChanged: (v) => onResolutionChanged(v!),
          items: const [
            DropdownMenuItem(value: '1920*1080', child: Text('1920*1080')),
            DropdownMenuItem(value: '2560*1440', child: Text('2560*1440')),
            DropdownMenuItem(value: '3840*2160', child: Text('3840*2160')),
          ],
          style: const TextStyle(fontSize: 14, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildLayoutDropdown() {
    // Deprecated in current UI; kept for compatibility if needed later.
    return const SizedBox.shrink();
  }

  Widget _buildPrimaryButton() {
    return ElevatedButton.icon(
      onPressed: onSave,
      icon: const Icon(LucideIcons.save, size: 16),
      label: const Text('保存配置'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}
