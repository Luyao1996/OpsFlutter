import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

class NetworkMonitorTab extends StatefulWidget {
  const NetworkMonitorTab({super.key});

  @override
  State<NetworkMonitorTab> createState() => _NetworkMonitorTabState();
}

class _NetworkMonitorTabState extends State<NetworkMonitorTab> {
  late List<_ChartData> _uploadData;
  late List<_ChartData> _downloadData;
  late Timer _timer;
  int _timeCounter = 0;

  @override
  void initState() {
    super.initState();
    _uploadData = List.generate(60, (index) => _ChartData(index, 0));
    _downloadData = List.generate(60, (index) => _ChartData(index, 0));
    _timer = Timer.periodic(const Duration(seconds: 1), _updateDataSource);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _updateDataSource(Timer timer) {
    _timeCounter++;
    final random = math.Random();
    
    // Simulate traffic (in KB/s)
    double upload = random.nextDouble() * 500;
    double download = random.nextDouble() * 2000 + 500;

    _uploadData.removeAt(0);
    _uploadData.add(_ChartData(_timeCounter, upload));
    
    _downloadData.removeAt(0);
    _downloadData.add(_ChartData(_timeCounter, download));

    setState(() {});
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
              if (isNarrow)
                Column(
                  children: [
                    _buildInfoCard(
                      '实时下载速度',
                      '${(_downloadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                      Colors.green,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      '实时上传速度',
                      '${(_uploadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                      Colors.blue,
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoCard(
                        '实时下载速度',
                        '${(_downloadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoCard(
                        '实时上传速度',
                        '${(_uploadData.last.value / 1024).toStringAsFixed(2)} MB/s',
                        Colors.blue,
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

  Widget _buildInfoCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
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
          Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
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
