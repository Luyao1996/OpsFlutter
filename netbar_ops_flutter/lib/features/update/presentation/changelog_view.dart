import 'package:flutter/material.dart';

import '../domain/models/release_info.dart';

/// 聚合 changelog 显示：本地~最新之间所有版本的更新说明。
class ChangelogView extends StatelessWidget {
  final List<ReleaseInfo> logs;

  const ChangelogView({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Text('（无更新说明）');
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in logs) ...[
          Row(
            children: [
              Text(
                'v${r.version}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(r.uploadTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (r.forceUpdate) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    '强制',
                    style: TextStyle(fontSize: 10, color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            r.changelog,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  String _formatDate(DateTime t) {
    final local = t.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
