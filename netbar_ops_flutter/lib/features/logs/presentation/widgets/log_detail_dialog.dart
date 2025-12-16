import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../data/log_types.dart';

class LogDetailDialog extends StatelessWidget {
  final LogEntry log;

  const LogDetailDialog({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final levelConf = levelConfig[log.level]!;
    final levelColor = levelConf['color'] as Color;
    final levelBg = levelConf['bg'] as Color;
    final levelLabel = levelConf['label'] as String;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width - 32).clamp(0.0, 640.0);
    final dialogMaxHeight = (screenSize.height - 48).clamp(0.0, 700.0);

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: dialogMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50.withOpacity(0.3),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: levelBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: levelColor.withOpacity(0.1),
                              ),
                            ),
                            child: Text(
                              levelLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: levelColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'ID: ${log.id}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.action,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.x,
                        size: 20,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Grid Info
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final useSingleColumn = constraints.maxWidth < 520;
                        final cardWidth = useSingleColumn
                            ? constraints.maxWidth
                            : (constraints.maxWidth - 16) / 2;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            _buildInfoCard(
                              icon: LucideIcons.user,
                              label: '操作人',
                              content: Text.rich(
                                TextSpan(
                                  text: log.user.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: ' (${log.user.role})',
                                      style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              width: cardWidth,
                            ),
                            _buildInfoCard(
                              icon: LucideIcons.clock,
                              label: '操作时间',
                              content: Text(
                                log.timestamp,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              width: cardWidth,
                            ),
                            _buildInfoCard(
                              icon: LucideIcons.mapPin,
                              label: '来源 IP',
                              content: Text(
                                log.ip,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              width: cardWidth,
                            ),
                            _buildInfoCard(
                              icon: LucideIcons.activity,
                              label: '所属模块',
                              content: Text(
                                moduleLabels[log.module]!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              width: cardWidth,
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    // Changes (Mocked logic for now as model doesn't have changes list yet, assuming simple payload)
                    if (log.details != null) ...[
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.globe,
                                    size: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '技术详情 (Payload)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              color: const Color(0xFF111827), // bg-gray-900
                              child: SelectableText(
                                log.details.toString(),
                                style: const TextStyle(
                                  color: Color(0xFFF3F4F6), // text-gray-100
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50.withOpacity(0.5),
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade200),
                  foregroundColor: Colors.grey.shade700,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required Widget content,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 2),
              ],
            ),
            child: Icon(icon, size: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 2),
                content,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
