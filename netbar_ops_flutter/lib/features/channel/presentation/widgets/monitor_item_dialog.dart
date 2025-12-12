import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../data/startup_monitor_models.dart';

class MonitorItemDialog extends StatelessWidget {
  final StartupItemStats item;
  final String netbarName;
  final VoidCallback onClose;

  const MonitorItemDialog({
    super.key,
    required this.item,
    required this.netbarName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final failureRate = item.failureRate;
    final shortLifeRate = item.shortLifeRate;

    Color badgeBg;
    Color badgeFg;
    IconData badgeIcon;
    if (failureRate > 10 || shortLifeRate > 50) {
      badgeBg = Colors.red.shade50;
      badgeFg = Colors.red.shade600;
      badgeIcon = LucideIcons.xCircle;
    } else if (failureRate > 0 || shortLifeRate > 20) {
      badgeBg = Colors.amber.shade50;
      badgeFg = Colors.amber.shade700;
      badgeIcon = LucideIcons.alertTriangle;
    } else {
      badgeBg = Colors.green.shade50;
      badgeFg = Colors.green.shade600;
      badgeIcon = LucideIcons.checkCircle2;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(badgeIcon, color: badgeFg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.path,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildTag(netbarName, Colors.grey.shade100,
                                Colors.grey.shade700),
                            const SizedBox(width: 8),
                            Text(
                              '更新于: ${item.lastUpdated}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: LucideIcons.play,
                      label: '启动次数',
                      value: item.launchCount.toString(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: LucideIcons.alertTriangle,
                      label: '失败次数',
                      value: item.failureCount.toString(),
                      isAlert: item.failureCount > 0,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '存活时长分布',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  _buildProgressRow(
                    label: '小于 1 分钟 (闪退风险)',
                    value: item.survival1min,
                    rate: item.launchCount == 0
                        ? 0
                        : item.survival1min / item.launchCount,
                    highlight: shortLifeRate > 20,
                    color: Colors.red.shade500,
                  ),
                  const SizedBox(height: 10),
                  _buildProgressRow(
                    label: '小于 10 分钟',
                    value: item.survival10min,
                    rate: item.launchCount == 0
                        ? 0
                        : item.survival10min / item.launchCount,
                    color: Colors.blue.shade400,
                  ),
                  const SizedBox(height: 10),
                  _buildProgressRow(
                    label: '小于 20 分钟',
                    value: item.survival20min,
                    rate: item.launchCount == 0
                        ? 0
                        : item.survival20min / item.launchCount,
                    color: Colors.blue.shade300,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onClose,
                  child: const Text('关闭'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    bool isAlert = false,
  }) {
    final bg = isAlert ? Colors.red.shade50 : Colors.grey.shade50;
    final fg = isAlert ? Colors.red.shade600 : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: fg),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isAlert ? Colors.red.shade700 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow({
    required String label,
    required int value,
    required double rate,
    required Color color,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$value 次',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: rate.clamp(0, 1),
            backgroundColor: Colors.grey.shade200,
            valueColor:
                AlwaysStoppedAnimation<Color>(highlight ? Colors.red : color),
          ),
        ),
      ],
    );
  }
}
