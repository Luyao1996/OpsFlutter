import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';

class LogStatsData {
  final int total;
  final double successRate;
  final int warning;
  final int error;

  LogStatsData({
    required this.total,
    required this.successRate,
    required this.warning,
    required this.error,
  });
}

class LogStats extends StatelessWidget {
  final LogStatsData data;

  const LogStats({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive grid logic
        int crossAxisCount = 4;
        if (constraints.maxWidth < 800) crossAxisCount = 2;
        if (constraints.maxWidth < 500) crossAxisCount = 1;

        // Calculate width for each item based on spacing
        final width = constraints.maxWidth;
        final spacing = 16.0;
        final itemWidth = (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: _buildStatCard('日志总数', data.total.toString(), LucideIcons.fileText, Colors.blue),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatCard('操作成功率', '${data.successRate.toStringAsFixed(1)}%', LucideIcons.activity, Colors.green),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatCard('安全警告', data.warning.toString(), LucideIcons.shieldAlert, Colors.orange),
            ),
            SizedBox(
              width: itemWidth,
              child: _buildStatCard('异常操作', data.error.toString(), LucideIcons.alertCircle, Colors.red),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
