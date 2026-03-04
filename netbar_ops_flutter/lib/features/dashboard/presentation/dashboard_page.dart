import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/responsive/responsive.dart';
import '../data/dashboard_api.dart';
import 'widgets/stat_card.dart';
import 'widgets/trend_chart.dart';

/// 时间范围枚举
enum TimeRange { days30, months12 }

/// 时间范围 Provider
final dashboardRangeProvider = StateProvider.autoDispose<TimeRange>(
  (ref) => TimeRange.days30,
);

/// 统计数据 Provider（不使用 autoDispose，让顶栏状态栏能持续访问）
final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final api = ref.read(dashboardApiProvider);
  return api.getStats();
});

/// 趋势数据 Provider
final dashboardTrendProvider = FutureProvider.autoDispose<TrendData>((ref) async {
  final api = ref.read(dashboardApiProvider);
  return api.getTrendData();
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardStats = ref.watch(dashboardStatsProvider);
    final pagePadding = context.isPhone
        ? 16.0
        : (context.isNarrow ? 24.0 : 32.0);

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: dashboardStats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.alertTriangle,
                size: 48,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 16),
              Text('加载失败: $err', style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.refresh(dashboardStatsProvider),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (DashboardStats stats) => LayoutBuilder(
          builder: (context, constraints) {
            final isPhone = context.isPhone;
            final width = (constraints.maxWidth - pagePadding * 2).clamp(
              0.0,
              double.infinity,
            );
            final gap = isPhone ? 12.0 : 24.0;

            // Determine columns based on breakpoints
            int columns;
            if (isPhone) {
              columns = 2;
            } else if (constraints.maxWidth >= 1024) {
              columns = 4;
            } else if (constraints.maxWidth >= 768) {
              columns = 2;
            } else {
              columns = 1;
            }

            final itemWidth = (width - (columns - 1) * gap) / columns;
            final chartAndActionsHeight = isPhone ? 350.0 : 500.0;

            return SingleChildScrollView(
              padding: EdgeInsets.all(pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '概览',
                        style: TextStyle(
                          fontSize: context.isPhone ? 22 : 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '欢迎回来，今日系统运行平稳。',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Stats Grid - 4个卡片
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _buildStatItem(
                        itemWidth,
                        '网吧数',
                        stats.merchantTotal.toString(),
                        '${stats.merchantOffline} 个离线 / ${stats.merchantOnline} 个在线',
                        LucideIcons.server,
                        Colors.indigo,
                        compact: isPhone,
                      ),
                      _buildStatItem(
                        itemWidth,
                        '离线网吧数',
                        stats.merchantOffline.toString(),
                        null,
                        LucideIcons.serverOff,
                        Colors.grey,
                        compact: isPhone,
                      ),
                      _buildStatItem(
                        itemWidth,
                        '终端数',
                        stats.terminalTotal.toString(),
                        null,
                        LucideIcons.monitor,
                        Colors.orange,
                        compact: isPhone,
                      ),
                      _buildStatItem(
                        itemWidth,
                        '近7日运行终端数',
                        stats.terminal7days.toString(),
                        null,
                        LucideIcons.activity,
                        Colors.green,
                        compact: isPhone,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Chart
                  SizedBox(
                    height: chartAndActionsHeight,
                    child: const TrendChart(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatItem(
    double width,
    String title,
    String value,
    String? subtext,
    IconData icon,
    Color color, {
    required bool compact,
  }) {
    final cardHeight = compact ? 120.0 : 150.0;

    return SizedBox(
      width: width,
      height: cardHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        child: StatCard(
          title: title,
          value: value,
          subtext: compact ? null : subtext,
          icon: icon,
          color: color,
          trend: null,
          compact: compact,
        ),
      ),
    );
  }
}
