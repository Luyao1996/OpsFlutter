import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/game_models.dart';

/// 批量删除结果弹窗：成功数 + 失败明细
///
/// 与 Web 端 `showBatchFailureAlert` 对齐：仅在「成败混合」时弹出。
class BatchResultDialog extends StatelessWidget {
  final int success;
  final List<BatchDeleteFailure> failures;

  const BatchResultDialog({
    super.key,
    required this.success,
    required this.failures,
  });

  static Future<void> show(
    BuildContext context, {
    required int success,
    required List<BatchDeleteFailure> failures,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BatchResultDialog(success: success, failures: failures),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('批量删除结果', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.checkSquare,
                    size: 14, color: Color(0xFF047857)),
                const SizedBox(width: 6),
                Text(
                  '已删除 $success 个',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(LucideIcons.alertTriangle,
                    size: 14, color: AppColors.red),
                const SizedBox(width: 6),
                Text(
                  '失败 ${failures.length} 个：',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: failures.length,
                  separatorBuilder: (_, __) => const Divider(
                      height: 1, color: Color(0xFFF3F4F6)),
                  itemBuilder: (_, i) {
                    final f = failures[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f.reason,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.iosBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}
