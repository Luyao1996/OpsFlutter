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
    final padding = compact ? 16.0 : 24.0;
    final radius = compact ? 18.0 : 24.0;
    final iconSize = compact ? 20.0 : 24.0;
    final iconPadding = compact ? 10.0 : 12.0;
    final valueFontSize = compact ? 24.0 : 30.0;
    final titleFontSize = compact ? 12.0 : 14.0;
    final trendIconSize = compact ? 12.0 : 14.0;
    final trendFontSize = compact ? 11.0 : 12.0;
    final trendPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 4);

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadows.sm,
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(iconPadding),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              if (trend != null)
                Container(
                  padding: trendPadding,
                  decoration: BoxDecoration(
                    color: trend! > 0 ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trend! > 0 ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight,
                        size: trendIconSize,
                        color: trend! > 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                      SizedBox(width: compact ? 3 : 4),
                      Text(
                        '${trend!.abs()}%',
                        style: TextStyle(
                          fontSize: trendFontSize,
                          fontWeight: FontWeight.bold,
                          color: trend! > 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
          if (subtext != null) ...[
            Container(
              margin: EdgeInsets.only(top: compact ? 8 : 12),
              padding: EdgeInsets.only(top: compact ? 8 : 12),
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade50)),
              ),
              child: Text(
                subtext!,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}
