import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/dashboard_api.dart';
import '../dashboard_page.dart';

class TrendChart extends ConsumerWidget {
  const TrendChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRange = ref.watch(dashboardRangeProvider);
    final trendAsync = ref.watch(dashboardTrendProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.sm,
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 手机端上下排列，桌面端左右排列
          if (isMobile) ...[
            Text(
              '终端在线趋势',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '近 ${selectedRange == TimeRange.months12 ? '12个月' : '30天'} 数据监控',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                _buildRangeDropdown(ref, selectedRange),
              ],
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '终端在线趋势',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '近 ${selectedRange == TimeRange.months12 ? '12个月' : '30天'} 数据监控',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                _buildRangeDropdown(ref, selectedRange),
              ],
            ),
          ],
          SizedBox(height: isMobile ? 8 : 16),
          // 图例
          _buildLegend(),
          SizedBox(height: isMobile ? 8 : 16),
          Expanded(
            child: trendAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('加载失败: $err')),
              data: (trendData) {
                final data = selectedRange == TimeRange.months12
                    ? trendData.months12
                    : trendData.days30;

                if (data.isEmpty) {
                  return const Center(child: Text('暂无数据'));
                }

                return SfCartesianChart(
                  plotAreaBorderWidth: 0,
                  zoomPanBehavior: ZoomPanBehavior(
                    enablePanning: true,
                    enablePinching: true,
                    zoomMode: ZoomMode.x,
                  ),
                  primaryXAxis: CategoryAxis(
                    majorGridLines: const MajorGridLines(width: 0),
                    axisLine: const AxisLine(width: 0),
                    majorTickLines: const MajorTickLines(width: 0),
                    labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: isMobile ? 10 : 11),
                    labelRotation: data.length > 15 ? 45 : 0,
                    labelIntersectAction: AxisLabelIntersectAction.rotate45,
                    autoScrollingDelta: isMobile ? 10 : null,
                    autoScrollingMode: AutoScrollingMode.end,
                  ),
                  primaryYAxis: NumericAxis(
                    axisLine: const AxisLine(width: 0),
                    majorTickLines: const MajorTickLines(width: 0),
                    majorGridLines: MajorGridLines(
                      width: 1,
                      color: Colors.grey.shade200,
                      dashArray: const [4, 4],
                    ),
                    labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                  axes: <ChartAxis>[
                    NumericAxis(
                      name: 'secondaryYAxis',
                      opposedPosition: true,
                      axisLine: const AxisLine(width: 0),
                      majorTickLines: const MajorTickLines(width: 0),
                      majorGridLines: const MajorGridLines(width: 0),
                      labelStyle: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                  tooltipBehavior: TooltipBehavior(
                    enable: true,
                    shared: true,
                    header: '',
                    canShowMarker: true,
                    builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
                      if (data is! TrendDataPoint) return const SizedBox();
                      final item = data;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTooltipRow(Colors.indigo, '网吧数', item.merchantTotal),
                            _buildTooltipRow(Colors.grey, '离线网吧数', item.merchantOffline),
                            _buildTooltipRow(Colors.orange, '终端数', item.terminalTotal),
                            _buildTooltipRow(Colors.green, '近7日运行终端数', item.terminal7days),
                          ],
                        ),
                      );
                    },
                  ),
                  series: <CartesianSeries>[
                    // 网吧数 - 柱状图（蓝色）
                    ColumnSeries<TrendDataPoint, String>(
                      name: '网吧数',
                      dataSource: data,
                      xValueMapper: (TrendDataPoint d, _) => _formatLabel(d.label),
                      yValueMapper: (TrendDataPoint d, _) => d.merchantTotal,
                      color: Colors.indigo.withOpacity(0.8),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      width: 0.6,
                      spacing: 0.2,
                    ),
                    // 离线网吧数 - 柱状图（灰色）
                    ColumnSeries<TrendDataPoint, String>(
                      name: '离线网吧数',
                      dataSource: data,
                      xValueMapper: (TrendDataPoint d, _) => _formatLabel(d.label),
                      yValueMapper: (TrendDataPoint d, _) => d.merchantOffline,
                      color: Colors.grey.shade400,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      width: 0.6,
                      spacing: 0.2,
                    ),
                    // 终端数 - 折线图（橙色）
                    SplineAreaSeries<TrendDataPoint, String>(
                      name: '终端数',
                      dataSource: data,
                      xValueMapper: (TrendDataPoint d, _) => _formatLabel(d.label),
                      yValueMapper: (TrendDataPoint d, _) => d.terminalTotal,
                      yAxisName: 'secondaryYAxis',
                      color: Colors.orange,
                      borderColor: Colors.orange,
                      borderWidth: 2,
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.withOpacity(0.3),
                          Colors.orange.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      markerSettings: const MarkerSettings(
                        isVisible: false,
                      ),
                    ),
                    // 近7日运行终端数 - 折线图（绿色）
                    SplineAreaSeries<TrendDataPoint, String>(
                      name: '近7日运行终端数',
                      dataSource: data,
                      xValueMapper: (TrendDataPoint d, _) => _formatLabel(d.label),
                      yValueMapper: (TrendDataPoint d, _) => d.terminal7days,
                      yAxisName: 'secondaryYAxis',
                      color: Colors.green,
                      borderColor: Colors.green,
                      borderWidth: 2,
                      gradient: LinearGradient(
                        colors: [
                          Colors.green.withOpacity(0.3),
                          Colors.green.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      markerSettings: const MarkerSettings(
                        isVisible: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 时间范围下拉框
  Widget _buildRangeDropdown(WidgetRef ref, TimeRange selectedRange) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TimeRange>(
          value: selectedRange,
          isDense: true,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
          items: const [
            DropdownMenuItem(
              value: TimeRange.days30,
              child: Text('最近30天'),
            ),
            DropdownMenuItem(
              value: TimeRange.months12,
              child: Text('最近12个月'),
            ),
          ],
          onChanged: (newValue) {
            if (newValue != null) {
              ref.read(dashboardRangeProvider.notifier).state = newValue;
            }
          },
        ),
      ),
    );
  }

  /// 格式化X轴标签
  String _formatLabel(String label) {
    // 日期格式: 2025-01-28 -> 01-28
    // 月份格式: 2025-01 -> 01月
    if (label.length == 10) {
      // 日期格式
      return label.substring(5); // MM-DD
    } else if (label.length == 7) {
      // 月份格式
      return '${label.substring(5)}月'; // MM月
    }
    return label;
  }

  /// 构建图例
  Widget _buildLegend() {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _buildLegendItem(Colors.indigo, '网吧数', isBar: true),
        _buildLegendItem(Colors.grey.shade400, '离线网吧数', isBar: true),
        _buildLegendItem(Colors.orange, '终端数', isBar: false),
        _buildLegendItem(Colors.green, '近7日运行终端数', isBar: false),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label, {required bool isBar}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isBar ? 12 : 16,
          height: isBar ? 12 : 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(isBar ? 2 : 1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildTooltipRow(Color color, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
