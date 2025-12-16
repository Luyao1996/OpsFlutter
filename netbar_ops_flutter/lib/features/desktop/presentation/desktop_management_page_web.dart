import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import 'desktop_management_page_impl.dart';

class DesktopManagementPage extends StatelessWidget {
  const DesktopManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobileWeb = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobileWeb) {
      return Scaffold(
        backgroundColor: AppColors.iosBg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.monitor,
                  size: 56,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 12),
                const Text(
                  '桌面管理仅支持桌面端',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '请在 Windows/macOS/Linux 或桌面浏览器上使用该功能',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/dashboard'),
                  child: const Text('返回概览'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const DesktopManagementPageImpl();
  }
}

