import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtext;
  final IconData icon;
  final Color color;
  final double? trend;
  final bool compact;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtext,
    required this.icon,
    required this.color,
    this.trend,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 10.0 : 16.0;
    final iconSize = compact ? 14.0 : 20.0;
    final iconPadding = compact ? 5.0 : 8.0;
    final valueFontSize = compact ? 18.0 : 24.0;
    final titleFontSize = compact ? 10.0 : 12.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        boxShadow: AppShadows.sm,
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 顶部图标
          Container(
            padding: EdgeInsets.all(iconPadding),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: iconSize),
          ),
          // 底部数值
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtext != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtext!,
                  style: TextStyle(
                    fontSize: compact ? 8 : 10,
                    color: Colors.grey.shade400,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
