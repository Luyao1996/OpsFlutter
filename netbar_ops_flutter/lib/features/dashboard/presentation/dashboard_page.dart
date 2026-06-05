import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/responsive/responsive.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/netbar_tabs_provider.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../netbar/presentation/netbar_selector_modal.dart';
import '../data/dashboard_api.dart';
import '../../netbar/data/netbar_api.dart';
import 'widgets/stat_card.dart';
import 'widgets/trend_chart.dart';
import 'widgets/alert_netbar_list.dart';
import 'widgets/expiring_netbar_list.dart';
import '../../../shared/widgets/app_error_view.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';

/// 时间范围枚举
enum TimeRange { days30, months12 }

/// 时间范围 Provider
final dashboardRangeProvider = StateProvider.autoDispose<TimeRange>(
  (ref) => TimeRange.days30,
);

/// 统计数据 Provider（不使用 autoDispose，让顶栏状态栏能持续访问）
/// 监听 currentNetbarProvider：网吧未就绪时保持 loading，就绪后自动加载，切换网吧时自动刷新
final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  if (netbar.id == null || netbar.id == 0) {
    // 网吧上下文未就绪，保持 loading 状态（Completer 永不完成，切换网吧时 Riverpod 自动取消并重新执行）
    await Completer<void>().future;
  }
  final api = ref.read(dashboardApiProvider);
  return api.getStats();
});

/// 趋势数据 Provider
final dashboardTrendProvider = FutureProvider.autoDispose<TrendData>((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  if (netbar.id == null || netbar.id == 0) {
    await Completer<void>().future;
  }
  final api = ref.read(dashboardApiProvider);
  return api.getTrendData();
});

/// 终端异常网吧列表（全局，跨所有网吧；不依赖当前网吧上下文）
final dashboardAlertListProvider =
    FutureProvider.autoDispose<List<Netbar>>((ref) async {
  return NetbarApi().getAlertList();
});

/// 网维即将到期网吧列表（全局，跨所有网吧）
final dashboardExpiringListProvider =
    FutureProvider.autoDispose<List<Netbar>>((ref) async {
  return NetbarApi().getExpiringList();
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
        error: (err, stack) => AppErrorView(
          error: err,
          onRetry: () => ref.invalidate(dashboardStatsProvider),
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
              columns = 3;
            } else if (constraints.maxWidth >= 768) {
              columns = 3;
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
                        onTap: () => _showNetbarSelector(context, ref),
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
                        '近7日运行终端数',
                        stats.terminal7days.toString(),
                        null,
                        LucideIcons.activity,
                        Colors.green,
                        compact: isPhone,
                      ),
                      // 手机端：异常 / 到期改为统计卡，点击打开全屏弹窗
                      if (isPhone) ...[
                        _buildStatItem(
                          itemWidth,
                          '终端异常网吧',
                          _countLabel(ref.watch(dashboardAlertListProvider)),
                          null,
                          LucideIcons.alertTriangle,
                          Colors.red,
                          compact: true,
                          onTap: () => _showAlertListDialog(context, ref),
                        ),
                        _buildStatItem(
                          itemWidth,
                          '网维即将到期',
                          _countLabel(ref.watch(dashboardExpiringListProvider)),
                          null,
                          LucideIcons.clock,
                          Colors.orange,
                          compact: true,
                          onTap: () => _showExpiringListDialog(context, ref),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 32),

                  // 终端异常 / 网维即将到期 列表区块（桌面端始终渲染；手机端隐藏，改由顶部卡片+弹窗承载）
                  _buildAlertSections(context, ref, isPhone, gap),

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
    VoidCallback? onTap,
  }) {
    final cardHeight = compact ? 120.0 : 150.0;
    final radius = BorderRadius.circular(compact ? 16 : 20);
    final card = StatCard(
      title: title,
      value: value,
      subtext: compact ? null : subtext,
      icon: icon,
      color: color,
      trend: null,
      compact: compact,
    );

    return SizedBox(
      width: width,
      height: cardHeight,
      child: ClipRRect(
        borderRadius: radius,
        child: onTap == null
            ? card
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: radius,
                  child: card,
                ),
              ),
      ),
    );
  }

  /// 构建「终端异常 / 网维即将到期」两个列表区块
  /// - 两者皆空：不渲染
  /// - 宽屏且两者皆有数据：左右平分；否则纵向堆叠
  Widget _buildAlertSections(
    BuildContext context,
    WidgetRef ref,
    bool isPhone,
    double gap,
  ) {
    // 手机端不展示底部完整列表，改由顶部统计卡 + 全屏弹窗承载
    if (isPhone) return const SizedBox.shrink();

    final alertAsync = ref.watch(dashboardAlertListProvider);
    final expiringAsync = ref.watch(dashboardExpiringListProvider);
    final alertList = alertAsync.valueOrNull ?? const <Netbar>[];
    final expiringList = expiringAsync.valueOrNull ?? const <Netbar>[];

    // 两块区域始终渲染：加载中 / 失败 / 空 / 有数据 四态均由各 widget 内部展示，
    // 不再因无数据而整块消失
    final cards = <Widget>[
      AlertNetbarList(
        netbars: alertList,
        loading: alertAsync.isLoading,
        error: alertAsync.hasError ? alertAsync.error : null,
        compact: isPhone,
        onRefresh: () => ref.invalidate(dashboardAlertListProvider),
        onTapNetbar: (n) => _openNetbarMonitor(context, ref, n),
      ),
      ExpiringNetbarList(
        netbars: expiringList,
        loading: expiringAsync.isLoading,
        error: expiringAsync.hasError ? expiringAsync.error : null,
        compact: isPhone,
        onRefresh: () => ref.invalidate(dashboardExpiringListProvider),
        onTapNetbar: (n) => _openNetbarMonitor(context, ref, n),
      ),
    ];

    final Widget section;
    if (!isPhone && !context.isNarrow && cards.length == 2) {
      // 宽屏：左右平分（crossAxisAlignment.start，高度各随内容，避免 ListView intrinsic 测量问题）
      section = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: cards[0]),
          SizedBox(width: gap),
          Expanded(child: cards[1]),
        ],
      );
    } else {
      // 窄屏 / 手机 / 仅一个：纵向堆叠
      section = Column(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            cards[i],
          ],
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: section,
    );
  }

  /// 统计卡数字：仅成功有数据时显示数量，加载中/失败均显示 '-'
  String _countLabel(AsyncValue<List<Netbar>> async) =>
      async.maybeWhen(data: (l) => l.length.toString(), orElse: () => '-');

  /// 手机端：全屏弹窗展示「终端异常网吧」完整列表
  void _showAlertListDialog(BuildContext context, WidgetRef ref) {
    showAdaptive<void>(
      context,
      (dialogContext) => Consumer(
        builder: (dialogContext, dref, _) {
          final async = dref.watch(dashboardAlertListProvider);
          return ResponsiveDialogScaffold(
            title: '终端异常网吧',
            scrollableBody: false,
            bodyPadding: const EdgeInsets.all(16),
            body: AlertNetbarList(
              netbars: async.valueOrNull ?? const <Netbar>[],
              loading: async.isLoading,
              error: async.hasError ? async.error : null,
              compact: true,
              embedded: true,
              onRefresh: () => dref.invalidate(dashboardAlertListProvider),
              onTapNetbar: (n) {
                Navigator.of(dialogContext).pop();
                _openNetbarMonitor(context, ref, n);
              },
            ),
          );
        },
      ),
      routeName: '/dialog/alert-list',
    );
  }

  /// 手机端：全屏弹窗展示「网维即将到期」完整列表
  void _showExpiringListDialog(BuildContext context, WidgetRef ref) {
    showAdaptive<void>(
      context,
      (dialogContext) => Consumer(
        builder: (dialogContext, dref, _) {
          final async = dref.watch(dashboardExpiringListProvider);
          return ResponsiveDialogScaffold(
            title: '网维即将到期',
            scrollableBody: false,
            bodyPadding: const EdgeInsets.all(16),
            body: ExpiringNetbarList(
              netbars: async.valueOrNull ?? const <Netbar>[],
              loading: async.isLoading,
              error: async.hasError ? async.error : null,
              compact: true,
              embedded: true,
              onRefresh: () => dref.invalidate(dashboardExpiringListProvider),
              onTapNetbar: (n) {
                Navigator.of(dialogContext).pop();
                _openNetbarMonitor(context, ref, n);
              },
            ),
          );
        },
      ),
      routeName: '/dialog/expiring-list',
    );
  }

  /// 打开该网吧的网吧管理（= 开标签页 + 切当前网吧 + 进监控页/终端列表）
  void _openNetbarMonitor(BuildContext context, WidgetRef ref, Netbar n) {
    final groupName =
        (n.groups != null && n.groups!.isNotEmpty) ? n.groups!.first.name : null;
    ref.read(netbarTabsProvider.notifier).openTab(
          n.id,
          n.name,
          n.status,
          subdomainFull: n.subdomainFull,
          groupName: groupName,
        );
    ref.read(currentNetbarProvider.notifier).setNetbar(
          n.id,
          n.name,
          n.status,
          subdomainFull: n.subdomainFull,
          groupName: groupName,
        );
    context.go('/monitor');
  }

  void _showNetbarSelector(BuildContext context, WidgetRef ref) {
    final tabsNotifier = ref.read(netbarTabsProvider.notifier);
    final current = ref.read(currentNetbarProvider);
    showAdaptive<void>(
      context,
      (context) => NetbarSelectorModal(
        selectedId: current.id,
        onSelect: (id, name, status, {subdomainFull, groupName}) {
          tabsNotifier.openTab(id, name, status,
              subdomainFull: subdomainFull, groupName: groupName);
          ref.read(currentNetbarProvider.notifier).setNetbar(id, name, status,
              subdomainFull: subdomainFull, groupName: groupName);
          context.go('/monitor');
        },
      ),
      routeName: '/dialog/netbar-selector',
    );
  }
}
