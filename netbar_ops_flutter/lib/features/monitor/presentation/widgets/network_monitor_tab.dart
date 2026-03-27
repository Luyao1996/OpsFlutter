import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../../shared/providers/app_providers.dart';

class NetworkMonitorTab extends ConsumerStatefulWidget {
  final String seatId;
  const NetworkMonitorTab({super.key, required this.seatId});

  @override
  ConsumerState<NetworkMonitorTab> createState() => _NetworkMonitorTabState();
}

class _NetworkMonitorTabState extends ConsumerState<NetworkMonitorTab> {
  late List<_ChartData> _uploadData;
  late List<_ChartData> _downloadData;
  late Timer _timer;
  int _timeCounter = 0;
  bool _fetching = false;

  // 累计流量
  double _uploadTotal = 0;
  double _downloadTotal = 0;

  @override
  void initState() {
    super.initState();
    _uploadData = List.generate(60, (index) => _ChartData(index, 0));
    _downloadData = List.generate(60, (index) => _ChartData(index, 0));
    // 立即获取一次
    _fetchRealtime();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchRealtime());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _fetchRealtime() async {
    if (_fetching) {
      debugPrint('[NetworkMonitorTab] 跳过：上一次请求还在进行中');
      return;
    }
    if (!mounted) {
      debugPrint('[NetworkMonitorTab] 跳过：widget 已销毁');
      return;
    }
    _fetching = true;
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      debugPrint('[NetworkMonitorTab] _fetchRealtime seatId=${widget.seatId}, domain=$domain');
      if (domain.isEmpty) {
        debugPrint('[NetworkMonitorTab] domain 为空，跳过');
        return;
      }

      final data = await api.getHardwareRealtime(widget.seatId, domain: domain);
      if (!mounted) return;

      debugPrint('[NetworkMonitorTab] 返回数据 keys: ${data.keys.toList()}');
      final networkList = data['network'] as List? ?? [];
      debugPrint('[NetworkMonitorTab] network 列表长度: ${networkList.length}');
      if (networkList.isNotEmpty) {
        final net = networkList[0] as Map<String, dynamic>;
        debugPrint('[NetworkMonitorTab] network[0]: $net');
        // upload_speed / download_speed 单位: bytes/s → 转换为 KB/s 用于图表
        final upload = (net['upload_speed'] as num? ?? 0).toDouble() / 1024;
        final download = (net['download_speed'] as num? ?? 0).toDouble() / 1024;

        _timeCounter++;
        _uploadData.removeAt(0);
        _uploadData.add(_ChartData(_timeCounter, upload));
        _downloadData.removeAt(0);
        _downloadData.add(_ChartData(_timeCounter, download));

        _uploadTotal = (net['upload_total'] as num? ?? 0).toDouble();
        _downloadTotal = (net['download_total'] as num? ?? 0).toDouble();
      }
      setState(() {});
    } catch (e) {
      debugPrint('[NetworkMonitorTab] 请求失败: $e');
    } finally {
      _fetching = false;
    }
  }

  String _formatBytes(double bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes.toInt()} B';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Info Cards
              Row(
                children: [
                  Expanded(
                    child: _buildInfoCard(
                      '实时下载速度',
                      '${(_downloadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                      Colors.green,
                      compact: isNarrow,
                      subtitle: '累计: ${_formatBytes(_downloadTotal)}',
                    ),
                  ),
                  SizedBox(width: isNarrow ? 12 : 16),
                  Expanded(
                    child: _buildInfoCard(
                      '实时上传速度',
                      '${(_uploadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                      Colors.blue,
                      compact: isNarrow,
                      subtitle: '累计: ${_formatBytes(_uploadTotal)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Chart
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: SfCartesianChart(
                    title: const ChartTitle(text: '网络流量监控 (KB/s)', textStyle: TextStyle(fontSize: 14)),
                    legend: const Legend(isVisible: true, position: LegendPosition.top),
                    primaryXAxis: const NumericAxis(
                      isVisible: false,
                    ),
                    primaryYAxis: const NumericAxis(
                      title: AxisTitle(text: '速率 (KB/s)'),
                    ),
                    series: <CartesianSeries<_ChartData, int>>[
                      AreaSeries<_ChartData, int>(
                        dataSource: _downloadData,
                        xValueMapper: (_ChartData data, _) => data.time,
                        yValueMapper: (_ChartData data, _) => data.value,
                        name: '下载',
                        color: Colors.green.withOpacity(0.2),
                        borderColor: Colors.green,
                        borderWidth: 2,
                      ),
                      AreaSeries<_ChartData, int>(
                        dataSource: _uploadData,
                        xValueMapper: (_ChartData data, _) => data.time,
                        yValueMapper: (_ChartData data, _) => data.value,
                        name: '上传',
                        color: Colors.blue.withOpacity(0.2),
                        borderColor: Colors.blue,
                        borderWidth: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(String title, String value, Color color, {required bool compact, String? subtitle}) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 12 : 13, color: Colors.grey.shade500),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: compact ? 10 : 11, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartData {
  _ChartData(this.time, this.value);
  final int time;
  final double value;
}
