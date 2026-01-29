import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/utils/icon_loader.dart';
import '../../data/desktop_api.dart';
import '../../data/desktop_model.dart';

class DesktopIconWidget extends StatelessWidget {
  final DesktopIcon icon;
  final bool isLocked;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final bool showActions;
  final bool isSelected;

  const DesktopIconWidget({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.showActions,
    this.isLocked = false,
    required this.onDelete,
    required this.onEdit,
  });

  /// 获取图标显示名称（兼容新旧模型）
  String get _displayName => icon.label.isNotEmpty ? icon.label : icon.config.name;

  /// 获取图标URL（兼容新旧模型）
  String? get _iconUrl => icon.iconUrl ?? icon.config.iconUrl;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: 88,
        height: 96,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.12) : Colors.transparent,
          border: isSelected
              ? Border.all(color: Colors.blue.withOpacity(0.35))
              : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2F8CFF), Color(0xFF2D76FF)],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2F4C83FF),
                          blurRadius: 8,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _buildIconGraphic(),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isLocked && showActions)
              Positioned(
                top: 2,
                right: 2,
                child: Row(
                  children: [
                    _cornerButton(
                      iconData: LucideIcons.edit3,
                      color: Colors.blue,
                      onTap: onEdit,
                    ),
                    const SizedBox(width: 4),
                    _cornerButton(
                      iconData: LucideIcons.x,
                      color: Colors.red,
                      onTap: onDelete,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconGraphic() {
    final path = _iconUrl;
    if (path != null && path.isNotEmpty) {
      // 处理 data URL
      if (path.startsWith('data:')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.expand(
            child: Image.network(
              path,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _buildDefaultText(),
            ),
          ),
        );
      }

      // 使用 DesktopApi 处理 URL，避免重复 /api
      final url = DesktopApi().getBackgroundUrl(path);
      if (url.isEmpty) {
        return _buildDefaultText();
      }

      // 使用支持 ICO 格式的 NetworkIconImage
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: NetworkIconImage(
            url: url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildDefaultText(),
          ),
        ),
      );
    }

    return _buildDefaultText();
  }

  Widget _buildDefaultText() {
    final name = _displayName;
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _cornerButton({
    required IconData iconData,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Icon(iconData, size: 10, color: Colors.white),
      ),
    );
  }
}
