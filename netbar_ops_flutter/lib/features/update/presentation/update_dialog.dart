import 'package:flutter/material.dart';

import '../domain/update_check_result.dart';
import 'changelog_view.dart';
import 'update_progress_dialog.dart';

/// 更新提示弹窗。强制更新场景下不可关闭。
/// 用户点"立即更新" → 关闭本弹窗，外部触发下载进度弹窗。
class UpdateDialog extends StatelessWidget {
  final UpdateCheckResult result;

  const UpdateDialog({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final latest = result.latest!;
    final sizeMb = (latest.size / 1024 / 1024).toStringAsFixed(2);

    return PopScope(
      canPop: !result.isForced,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              result.isForced ? Icons.warning_amber_rounded : Icons.system_update,
              color: result.isForced ? Colors.orange : Colors.blue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(result.isForced ? '需要更新' : '发现新版本'),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final currentChip = _versionChip(
                      '当前',
                      'v${result.localVersion.isEmpty ? '?' : result.localVersion}',
                      Colors.grey,
                    );
                    final latestChip = _versionChip(
                      '最新',
                      'v${latest.version}',
                      Theme.of(context).colorScheme.primary,
                    );
                    // 宽屏（PC / 平板）一行横排；窄屏（手机）竖排，箭头朝下。
                    if (constraints.maxWidth >= 400) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: currentChip),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, size: 16),
                          const SizedBox(width: 8),
                          Flexible(child: latestChip),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        currentChip,
                        const SizedBox(height: 6),
                        Icon(
                          Icons.arrow_downward,
                          size: 16,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 6),
                        latestChip,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '安装包大小：$sizeMb MB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Text(
                  '更新内容',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ChangelogView(logs: result.aggregatedChangelogs),
              ],
            ),
          ),
        ),
        actions: [
          if (!result.isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('稍后再说'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop(true);
              showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => UpdateProgressDialog(
                  release: latest,
                  host: result.host!,
                  isForced: result.isForced,
                ),
              );
            },
            icon: const Icon(Icons.download),
            label: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Widget _versionChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: color),
      ),
    );
  }
}

/// 入口辅助函数：外部调用。
Future<void> showUpdateDialog(
    BuildContext context, UpdateCheckResult result) async {
  if (!result.hasUpdate) return;
  await showDialog<bool>(
    context: context,
    barrierDismissible: !result.isForced,
    builder: (_) => UpdateDialog(result: result),
  );
}
