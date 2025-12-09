import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/dashboard_api.dart';
import 'widgets/stat_card.dart';
import 'widgets/trend_chart.dart';
import 'widgets/quick_actions.dart';

final dashboardStatsProvider = FutureProvider.autoDispose((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  final api = ref.read(dashboardApiProvider);
  
  // Use Future.wait to fetch both stats and trend data in parallel
  final results = await Future.wait<dynamic>([
    api.getStats(netbarId: netbar.id),
    api.getTrendData(netbarId: netbar.id),
  ]);
  
  return (stats: results[0] as DashboardStats, trend: results[1] as List<TrendDataPoint>);
});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardData = ref.watch(dashboardStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: dashboardData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade400),
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
        data: (data) => LayoutBuilder(
          builder: (context, constraints) {
            // Padding is 32 on each side, so available width for content is maxWidth - 64
            final width = constraints.maxWidth - 64; 
            const gap = 24.0;
            
            // Determine columns based on breakpoints (matching Vue: lg=1024, md=768)
            int columns;
            // Use the original constraint width for breakpoint checking
            if (constraints.maxWidth >= 1024) {
              columns = 4;
            } else if (constraints.maxWidth >= 768) {
              columns = 2;
            } else {
              columns = 1;
            }

            // Calculate item width exactly
            // Total width = columns * itemWidth + (columns - 1) * gap
            // itemWidth = (Total width - (columns - 1) * gap) / columns
            final itemWidth = (width - (columns - 1) * gap) / columns;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '概览',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '欢迎回来，今日系统运行平稳。',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Stats Grid (Using Wrap for precise width control to match manual calc)
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _buildStatItem(itemWidth, '总网吧数', data.stats.totalNetbars.toString(), 
                          '${data.stats.onlineNetbars} 个在线 / ${data.stats.totalNetbars - data.stats.onlineNetbars} 个离线',
                          LucideIcons.server, Colors.blue, null),
                      _buildStatItem(itemWidth, '终端总数', data.stats.totalDesktops.toString(), null,
                          LucideIcons.monitor, Colors.indigo, 2.4),
                      _buildStatItem(itemWidth, '在线终端', data.stats.onlineDesktops.toString(), null,
                          LucideIcons.activity, Colors.green, 12.5),
                      _buildStatItem(itemWidth, '活跃通道', '${data.stats.activeChannels}/${data.stats.totalChannels}', null,
                          LucideIcons.wifi, Colors.orange, null),
                    ],
                  ),
                  
                  const SizedBox(height: 32),

                  // Chart & Actions
                  if (columns == 4)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: itemWidth * 3 + gap * 2,
                          child: TrendChart(data: data.trend),
                        ),
                        const SizedBox(width: gap),
                        SizedBox(
                          width: itemWidth,
                          child: const QuickActions(),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        TrendChart(data: data.trend),
                        const SizedBox(height: 24),
                        const QuickActions(),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatItem(double width, String title, String value, String? subtext, IconData icon, Color color, double? trend) {
    // Aspect ratio 1.6 approx, but let content drive height or fixed height?
    // Vue uses fixed padding/height. Let's give it a min-height or let it be flexible but constrained width.
    return SizedBox(
      width: width,
      // Fixed height to ensure alignment, similar to GridView aspect ratio approach
      // but 'StatCard' is flexible. Let's fix height to match the look.
      height: 220, 
      child: StatCard(
        title: title,
        value: value,
        subtext: subtext,
        icon: icon,
        color: color,
        trend: trend,
      ),
    );
  }
}
