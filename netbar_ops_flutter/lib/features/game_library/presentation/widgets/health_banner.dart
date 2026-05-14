import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../data/game_constants.dart';
import '../../data/game_models.dart';
import '../../utils/formatter.dart';

/// 平台健康提示条：当 snapshot.unhealthy == true 时展示
class HealthBanner extends StatelessWidget {
  final List<String> unhealthyPlatforms;
  final Map<String, PlatformSnapshot> snapshots;

  const HealthBanner({
    super.key,
    required this.unhealthyPlatforms,
    required this.snapshots,
  });

  @override
  Widget build(BuildContext context) {
    if (unhealthyPlatforms.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFCD34D)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(LucideIcons.alertTriangle, size: 14, color: Color(0xFFB45309)),
          const Text(
            '部分平台数据陈旧',
            style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
          ),
          for (final p in unhealthyPlatforms) _chip(p),
        ],
      ),
    );
  }

  Widget _chip(String platform) {
    final s = snapshots[platform];
    final stale = formatStale(s?.staleSince);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFFCD34D)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        stale.isNotEmpty
            ? '${kPlatformLabel[platform] ?? platform} · $stale'
            : (kPlatformLabel[platform] ?? platform),
        style: const TextStyle(fontSize: 11, color: Color(0xFFB45309)),
      ),
    );
  }
}
