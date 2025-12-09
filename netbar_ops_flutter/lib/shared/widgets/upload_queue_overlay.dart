import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../providers/upload_queue_provider.dart';

class UploadQueueOverlay extends ConsumerWidget {
  const UploadQueueOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(uploadQueueProvider);
    final notifier = ref.read(uploadQueueProvider.notifier);

    if (state.tasks.isEmpty) return const SizedBox.shrink();

    final completed = state.tasks.where((t) => t.status == UploadStatus.success).length;
    final total = state.tasks.length;
    final totalProgress = state.tasks.isEmpty
        ? 0
        : (state.tasks.map((t) => t.progress).fold<int>(0, (a, b) => a + b) / total).round();

    return Positioned(
      right: 16,
      bottom: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, notifier, state, total, completed),
              if (state.isMinimized)
                _buildSummary(totalProgress, completed, total)
              else
                _buildList(ref),
              if (!state.isMinimized)
                _buildFooter(notifier, completed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, UploadQueueNotifier notifier, UploadQueueState state, int total, int completed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF2563EB)]),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.upload, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Text('上传队列', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
            child: Text('$completed/$total', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
          const Spacer(),
          IconButton(
            tooltip: state.isMinimized ? '展开' : '收起',
            onPressed: notifier.toggleMinimize,
            icon: Icon(state.isMinimized ? LucideIcons.chevronUp : LucideIcons.chevronDown, color: Colors.white, size: 18),
          ),
          IconButton(
            tooltip: '清除已完成',
            onPressed: notifier.clearCompleted,
            icon: const Icon(LucideIcons.x, color: Colors.white, size: 18),
          ),
          IconButton(
            tooltip: '取消所有上传',
            onPressed: notifier.clearAll,
            icon: const Icon(LucideIcons.trash2, color: Colors.white, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(int totalProgress, int completed, int total) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('总进度', style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text('$completed/$total 完成', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: totalProgress / 100,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(WidgetRef ref) {
    final state = ref.watch(uploadQueueProvider);
    final notifier = ref.read(uploadQueueProvider.notifier);
    return SizedBox(
      height: 260,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: state.tasks.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final item = state.tasks[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildStatusIcon(item),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item.relativePath ?? item.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (item.status != UploadStatus.uploading)
                      IconButton(
                        onPressed: () => notifier.remove(item.id),
                        icon: Icon(LucideIcons.x, size: 16, color: Colors.grey.shade400),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatSize(item.size), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    Text(
                      item.status == UploadStatus.error
                          ? (item.error ?? '上传失败')
                          : item.status == UploadStatus.success
                              ? '完成'
                              : '${item.progress}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: item.status == UploadStatus.error
                            ? Colors.red.shade500
                            : item.status == UploadStatus.success
                                ? Colors.green.shade600
                                : const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progressValue(item),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(
                      item.status == UploadStatus.error
                          ? Colors.red.shade400
                          : item.status == UploadStatus.success
                              ? Colors.green.shade500
                              : const Color(0xFF3B82F6),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIcon(UploadTask item) {
    Color bg;
    Color fg;
    IconData icon;
    switch (item.status) {
      case UploadStatus.success:
        bg = Colors.green.shade100;
        fg = Colors.green.shade600;
        icon = LucideIcons.checkCircle2;
        break;
      case UploadStatus.error:
        bg = Colors.red.shade100;
        fg = Colors.red.shade600;
        icon = LucideIcons.alertCircle;
        break;
      case UploadStatus.uploading:
      case UploadStatus.pending:
      default:
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade600;
        icon = item.isDirectory ? LucideIcons.folder : LucideIcons.file;
        break;
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Center(child: Icon(icon, color: fg, size: 16)),
    );
  }

  Widget _buildFooter(UploadQueueNotifier notifier, int completed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (completed > 0)
            TextButton(
              onPressed: notifier.clearCompleted,
              child: const Text('清除已完成'),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: notifier.clearAll,
            icon: const Icon(LucideIcons.trash2, size: 14, color: Colors.red),
            label: const Text('取消全部', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  double _progressValue(UploadTask item) {
    if (item.status == UploadStatus.success) return 1;
    if (item.status == UploadStatus.error) return 0;
    return (item.progress.clamp(0, 100)) / 100;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
