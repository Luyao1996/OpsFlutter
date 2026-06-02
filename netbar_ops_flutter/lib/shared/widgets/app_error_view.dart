import 'package:flutter/material.dart';

import '../../core/network/error_message.dart';
import '../../core/theme/app_theme.dart';

/// 统一的友好错误展示组件。
///
/// 取代各页面散落的 `Text('Error: $error')`：
/// - 图标 + [friendlyErrorMessage] 生成的中文文案；
/// - 可选「重试」按钮（[onRetry]，通常传 `() => ref.invalidate(provider)`）；
/// - 技术原文默认折叠（「查看详情」展开），方便排查但不吓用户。
///
/// [compact] 用于 modal / 小区域：更小的图标与间距。
class AppErrorView extends StatefulWidget {
  final Object? error;
  final VoidCallback? onRetry;
  final bool compact;

  const AppErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.compact = false,
  });

  @override
  State<AppErrorView> createState() => _AppErrorViewState();
}

class _AppErrorViewState extends State<AppErrorView> {
  bool _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final detail = widget.error?.toString() ?? '';

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: compact ? 36 : 56,
              color: Colors.grey.shade400,
            ),
            SizedBox(height: compact ? 8 : 16),
            Text(
              friendlyErrorMessage(widget.error),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 14 : 16,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.onRetry != null) ...[
              SizedBox(height: compact ? 12 : 20),
              ElevatedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
            if (detail.isNotEmpty) ...[
              SizedBox(height: compact ? 6 : 12),
              TextButton(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                child: Text(
                  _showDetail ? '收起详情' : '查看详情',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
              if (_showDetail)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(maxWidth: 360, maxHeight: 160),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
