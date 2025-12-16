import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/storage/token_store.dart';
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
                      icon.name,
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
    final path = icon.config.iconPath;
    if (path != null && path.isNotEmpty) {
      ImageProvider? provider;
      final token = TokenStore.getToken();

      if (path.startsWith('http')) {
        provider = NetworkImage(_appendToken(path, token));
      } else if (path.startsWith('/resources/')) {
        provider = NetworkImage(_appendToken('${AppConfig.baseUrl}$path', token));
      } else if (path.contains('://')) {
        provider = NetworkImage(_appendToken(path, token));
      } else if (path.isNotEmpty) {
        provider = NetworkImage(_appendToken(_normalizeUrl(path), token));
      }

      if (provider == null) {
        return const Icon(LucideIcons.monitor, color: Colors.white, size: 20);
      }

      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const Icon(
              LucideIcons.monitor,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    return Text(
      icon.name.isNotEmpty ? icon.name[0] : '?',
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

String _normalizeUrl(String url) {
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('data:')) {
    return url;
  }
  final base = AppConfig.baseUrl.endsWith('/')
      ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
      : AppConfig.baseUrl;
  if (url.startsWith('/')) return '$base$url';
  return '$base/$url';
}

String _appendToken(String url, String? token) {
  if (token == null || token.isEmpty || url.contains('token=')) return url;
  final sep = url.contains('?') ? '&' : '?';
  return '$url${sep}token=$token';
}
