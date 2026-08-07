import 'package:flutter/material.dart';

import '../../core/cache/offline_status.dart';
import '../../core/theme/app_theme.dart';

/// 全局离线提示条：网络不可达时出现在顶栏下方，恢复后自动消失。
///
/// 必须存在的理由：离线时页面照常渲染数据，但那是最近一次缓存（最长 3 天前），
/// 没有这条提示，用户会把旧的终端在线状态当成实时状态误操作。
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OfflineStatus.instance.offline,
      builder: (context, offline, _) {
        if (!offline) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: AppColors.orange.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 13,
                color: AppColors.orange,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '离线模式 · 展示最近一次缓存数据，新增/修改类操作暂不可用',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.orange.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
