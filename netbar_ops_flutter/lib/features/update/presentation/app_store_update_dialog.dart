import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../domain/models/app_store_check_result.dart';
import '../providers.dart';

/// 启动检查：已确认有新版本，弹出"前往 App Store 更新"提示。
/// [onSkip] 用户点"稍后"时回调（用于持久化"跳过此版本"）。
Future<void> showAppStoreUpdateDialog(
  BuildContext context,
  AppStoreCheckResult result, {
  VoidCallback? onSkip,
}) {
  return showAdaptive<void>(
    context,
    (_) => _AppStoreUpdateDialog(result: result, onSkip: onSkip),
    barrierDismissible: true,
  );
}

/// 手动「检查更新」：弹出带状态的检查弹窗（检查中 → 有新版 / 已是最新 / 暂时无法检查）。
Future<void> showAppStoreManualCheck(BuildContext context) {
  return showAdaptive<void>(
    context,
    (_) => const _AppStoreManualCheckDialog(),
    barrierDismissible: true,
  );
}

// ----------------------- 共享逻辑 -----------------------

/// 跳转 App Store（外部 App Store app）。失败给 SnackBar 提示。
Future<void> _openAppStore(BuildContext context, String url) async {
  if (url.isEmpty) {
    _toast(context, '请到 App Store 搜索本应用进行更新');
    return;
  }
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (context.mounted) Navigator.of(context).pop();
  } catch (_) {
    _toast(context, '打开 App Store 失败，请手动到 App Store 搜索更新');
  }
}

void _toast(BuildContext context, String msg) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Widget _versionChip(String text, bool highlight) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: highlight ? const Color(0xFFE8F0FE) : const Color(0xFFF2F3F5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
        color: highlight ? const Color(0xFF1A73E8) : Colors.black54,
      ),
    ),
  );
}

/// "有新版本"正文：版本对比 + 更新说明（不显示包体积，iOS 拿不到真实大小）。
Widget _buildUpdateBody(AppStoreCheckResult result) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          _versionChip('当前 v${result.localVersion}', false),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child:
                Icon(LucideIcons.arrowRight, size: 16, color: Colors.black38),
          ),
          _versionChip('最新 v${result.storeVersion}', true),
        ],
      ),
      if (result.releaseNotes.trim().isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('更新内容',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Text(result.releaseNotes.trim(),
            style: const TextStyle(fontSize: 13, height: 1.5)),
      ],
    ],
  );
}

Widget _footerButtons({
  required String primaryText,
  required VoidCallback onPrimary,
  String? secondaryText,
  VoidCallback? onSecondary,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        if (secondaryText != null) ...[
          Expanded(
            child: TextButton(
              onPressed: onSecondary,
              child: Text(secondaryText),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: ElevatedButton(onPressed: onPrimary, child: Text(primaryText)),
        ),
      ],
    ),
  );
}

// ----------------- 启动：直接显示"有新版" -----------------
class _AppStoreUpdateDialog extends StatelessWidget {
  final AppStoreCheckResult result;
  final VoidCallback? onSkip;
  const _AppStoreUpdateDialog({required this.result, this.onSkip});

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '发现新版本',
      maxWidth: 420,
      body: _buildUpdateBody(result),
      footer: _footerButtons(
        secondaryText: '稍后',
        onSecondary: () {
          onSkip?.call();
          Navigator.of(context).pop();
        },
        primaryText: '前往 App Store 更新',
        onPrimary: () => _openAppStore(context, result.storeUrl),
      ),
    );
  }
}

// ----------------- 手动：带状态的检查弹窗 -----------------
class _AppStoreManualCheckDialog extends ConsumerStatefulWidget {
  const _AppStoreManualCheckDialog();
  @override
  ConsumerState<_AppStoreManualCheckDialog> createState() =>
      _AppStoreManualCheckDialogState();
}

class _AppStoreManualCheckDialogState
    extends ConsumerState<_AppStoreManualCheckDialog> {
  bool _checking = true;
  AppStoreCheckResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() => _checking = true);
    final r = await ref.read(updateServiceProvider).checkAppStore();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final Widget? footer;

    if (_checking) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('正在检查更新...'),
          ],
        ),
      );
      footer = null;
    } else {
      final r = _result;
      if (r != null && r.hasUpdate) {
        body = _buildUpdateBody(r);
        footer = _footerButtons(
          secondaryText: '稍后',
          onSecondary: () => Navigator.of(context).pop(),
          primaryText: '前往 App Store 更新',
          onPrimary: () => _openAppStore(context, r.storeUrl),
        );
      } else if (r != null && r.status == AppStoreCheckStatus.upToDate) {
        body = Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.checkCircle,
                  size: 40, color: Color(0xFF34A853)),
              const SizedBox(height: 12),
              Text('已是最新版本 v${r.localVersion}'),
            ],
          ),
        );
        footer = _footerButtons(
          primaryText: '好的',
          onPrimary: () => Navigator.of(context).pop(),
        );
      } else {
        // skipped：无网 / 查不到 / 限流 / 缓存延迟
        body = const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, size: 40, color: Colors.black38),
              SizedBox(height: 12),
              Text('暂时无法检查更新',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(
                '请检查网络后重试。\n（刚在 App Store 发布的新版本可能需要数小时才能查到）',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        );
        footer = _footerButtons(
          primaryText: '好的',
          onPrimary: () => Navigator.of(context).pop(),
        );
      }
    }

    return ResponsiveDialogScaffold(
      title: '检查更新',
      maxWidth: 420,
      body: body,
      footer: footer,
    );
  }
}
