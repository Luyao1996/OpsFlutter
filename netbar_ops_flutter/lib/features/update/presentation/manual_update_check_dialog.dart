import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../domain/models/release_info.dart';
import '../domain/update_check_result.dart';
import '../providers.dart';
import '../update_navigator_key.dart';
import 'update_progress_dialog.dart';

/// 手动「检查更新」弹窗。
///
/// 与启动检查（main.dart 中 _checkUpdate）的区别：
/// - 用户主动触发，每次都强制重新拉 manifest
/// - 不论结果如何（已是最新 / 有更新 / 失败）都给用户一个明确反馈
/// - 复用 [UpdateProgressDialog] 做下载安装
///
/// 使用 [ResponsiveDialogScaffold] + [showAdaptive]：窄屏走全屏 PageRoute，
/// 宽屏走 Dialog；body 与 footer 统一布局，避免手机端写死高度引发溢出。
class ManualUpdateCheckDialog extends ConsumerStatefulWidget {
  const ManualUpdateCheckDialog({super.key});

  @override
  ConsumerState<ManualUpdateCheckDialog> createState() =>
      _ManualUpdateCheckDialogState();
}

class _ManualUpdateCheckDialogState
    extends ConsumerState<ManualUpdateCheckDialog> {
  bool _checking = true;
  UpdateCheckResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _result = null;
      _error = null;
    });
    try {
      final result = await ref.read(updateServiceProvider).check();
      if (!mounted) return;
      // 把最新 isCurrentPreview 同步到 provider，让外部 PREVIEW 标签即时刷新
      if (result.status != UpdateStatus.skipped) {
        ref.read(isPreviewProvider.notifier).state = result.isCurrentPreview;
      }
      setState(() {
        _checking = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = e.toString();
      });
    }
  }

  /// 启动下载。[release] 由调用方决定是正式版还是预览版。
  /// [isForced] 是否强制更新（用户主动点的下载一般为 false，但若启动检查的 result 本身是强制
  /// 且用户走到这里下同一个 release，仍按 result.isForced 传入以保留行为）。
  void _startDownload(ReleaseInfo release, {required bool isForced}) {
    final result = _result;
    if (result == null) return;
    final host = result.host;
    if (host == null) return;
    // 关闭本窗口（窄屏是 PageRoute，pop 后本 context 会失效）。
    // 改用全局的 updateNavigatorKey.currentContext 调起下载弹窗，避免引用已 dispose 的 context。
    Navigator.of(context).pop();
    final ctx = updateNavigatorKey.currentContext;
    if (ctx == null) return;
    showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => UpdateProgressDialog(
        release: release,
        host: host,
        isForced: isForced,
      ),
    );
  }

  /// 预览版二次确认 → 确认后下载。
  Future<void> _confirmAndStartPreview(ReleaseInfo preview) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('尝鲜预览版')),
          ],
        ),
        content: Text(
          '即将安装预览版 v${preview.version} (build ${preview.buildNumber})。\n\n'
          '预览版功能可能不稳定，仅推荐内部测试人员使用。\n'
          '安装后会一直收到预览版更新，直到该预览版被发布为正式版后将自动回到正式版轨道。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续安装'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      // 预览版主动尝鲜不强制
      _startDownload(preview, isForced: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = ref.watch(isPreviewProvider);

    return ResponsiveDialogScaffold(
      title: '检查更新',
      maxWidth: 560,
      maxHeightCap: 720,
      // 内部不再写死高度，body 自身可滚动；骨架已经包了 SingleChildScrollView。
      appBarActions: [
        if (!_checking)
          IconButton(
            tooltip: '重新检查',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _runCheck,
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCurrentVersionRow(isPreview),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _buildBody(),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildHistorySection(),
        ],
      ),
      footer: _buildFooter(),
    );
  }

  Widget _buildCurrentVersionRow(bool isPreview) {
    final result = _result;
    final localVersion = result?.localVersion ?? '';
    final localBuild = result?.localBuildNumber ?? 0;
    final versionText = localVersion.isEmpty
        ? '当前版本：未知'
        : '当前版本：v$localVersion${localBuild > 0 ? ' (build $localBuild)' : ''}';

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text(versionText),
        if (isPreview)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
            ),
            child: const Text(
              'PREVIEW',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_checking) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在检查最新版本...'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Text('检查失败：$_error',
          style: const TextStyle(color: Colors.red, height: 1.5));
    }
    final result = _result!;
    if (result.status == UpdateStatus.skipped) {
      return const Text('当前网络无法连接更新服务，请稍后再试。');
    }
    // 两区块：正式版 + 预览版（不论身份都显示）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildReleaseSection(result),
        const SizedBox(height: 16),
        _buildPreviewSection(result),
      ],
    );
  }

  /// 正式版分区
  Widget _buildReleaseSection(UpdateCheckResult result) {
    final candidate = result.availableRelease;
    return _buildVersionSection(
      icon: Icons.system_update,
      iconColor: const Color(0xFF2563EB),
      title: '正式版',
      candidate: candidate,
      noUpdateText: '已是最新正式版',
      buttonLabel: '立即更新',
      buttonColor: const Color(0xFF2563EB),
      onPressed: candidate == null
          ? null
          : () => _startDownload(candidate,
              // 仅当本次启动检查刚好就是这个正式版且强制时才强制
              isForced: result.isForced &&
                  result.latest?.buildNumber == candidate.buildNumber),
    );
  }

  /// 预览版分区
  Widget _buildPreviewSection(UpdateCheckResult result) {
    final candidate = result.availablePreview;
    return _buildVersionSection(
      icon: Icons.science_outlined,
      iconColor: const Color(0xFFEA580C),
      title: '预览版',
      candidate: candidate,
      noUpdateText: '暂无预览版',
      buttonLabel: '试试预览版',
      buttonColor: const Color(0xFFEA580C),
      tag: 'PREVIEW',
      onPressed: candidate == null ? null : () => _confirmAndStartPreview(candidate),
    );
  }

  /// 通用分区骨架
  Widget _buildVersionSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required ReleaseInfo? candidate,
    required String noUpdateText,
    required String buttonLabel,
    required Color buttonColor,
    String? tag,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Icon(icon, color: iconColor, size: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              if (tag != null) _miniChip(tag, bg: iconColor.withValues(alpha: 0.15), fg: iconColor),
            ],
          ),
          const SizedBox(height: 10),
          if (candidate == null) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    color: Color(0xFF9CA3AF), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    noUpdateText,
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'v${candidate.version} (build ${candidate.buildNumber})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '安装包大小：${(candidate.size / 1024 / 1024).toStringAsFixed(2)} MB',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            if (candidate.changelog.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                candidate.changelog,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: buttonColor),
                onPressed: onPressed,
                icon: const Icon(Icons.download, size: 18),
                label: Text(buttonLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    final localBuild = _result?.localBuildNumber ?? 0;
    final history = _result?.recentReleases ?? const <ReleaseInfo>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 18, color: Color(0xFF6B7280)),
            const SizedBox(width: 8),
            Text(
              '最近更新历史',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(width: 8),
            if (history.isNotEmpty)
              Text(
                '共 ${history.length} 条',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF9CA3AF),
                    ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_checking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('加载中...',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          )
        else if (history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('暂无历史版本',
                style: TextStyle(color: Color(0xFF9CA3AF))),
          )
        else
          ...history.map((r) => _buildHistoryItem(r, localBuild)),
      ],
    );
  }

  Widget _buildHistoryItem(ReleaseInfo r, int localBuild) {
    final isCurrent = r.buildNumber == localBuild;
    final timeText = _formatTime(r.uploadTime);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? const Color(0xFF2563EB).withValues(alpha: 0.06)
            : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF2563EB).withValues(alpha: 0.4)
              : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行 1：版本号 + tags（用 Wrap 防止窄屏溢出）
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                'v${r.version}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                '(build ${r.buildNumber})',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
              if (isCurrent)
                _miniChip('当前',
                    bg: const Color(0xFF2563EB).withValues(alpha: 0.15),
                    fg: const Color(0xFF1D4ED8)),
              if (r.forceUpdate)
                _miniChip('强制',
                    bg: Colors.red.withValues(alpha: 0.12), fg: Colors.red),
            ],
          ),
          const SizedBox(height: 4),
          // 行 2：上传时间
          Text(
            timeText,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
          if (r.changelog.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.changelog,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4B5563),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniChip(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    // 下载按钮已下沉到正式版/预览版分区，footer 只留"关闭"。
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  String _formatTime(DateTime t) {
    // 不引入新依赖；DateTime 自带的 toIso8601String 形如 2025-12-09T02:58:00.000
    // 本地展示截到分钟
    final s = t.toLocal().toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }
}

/// 入口：自适应弹出（窄屏全屏页 / 宽屏 Dialog）。
Future<void> showManualUpdateCheckDialog(BuildContext context) {
  return showAdaptive<void>(
    context,
    (_) => const ManualUpdateCheckDialog(),
    routeName: 'manual_update_check',
    barrierDismissible: false,
  );
}
