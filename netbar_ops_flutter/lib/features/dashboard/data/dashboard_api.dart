import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

/// Dashboard统计数据
class DashboardStats {
  final int merchantTotal;     // 网吧总数
  final int merchantOffline;   // 离线网吧数
  final int terminalTotal;     // 终端总数
  final int terminal7days;     // 近7日运行终端数

  DashboardStats({
    required this.merchantTotal,
    required this.merchantOffline,
    required this.terminalTotal,
    required this.terminal7days,
  });

  /// 在线网吧数
  int get merchantOnline => merchantTotal - merchantOffline;

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    // 取 ma 数组第一个对象
    final ma = (json['ma'] as List?)?.firstOrNull as Map<String, dynamic>? ?? {};
    return DashboardStats(
      merchantTotal: _parseInt(ma['merchant_total']),
      merchantOffline: _parseInt(ma['merchant_offline']),
      terminalTotal: _parseInt(ma['terminal_total']),
      terminal7days: _parseInt(ma['terminal_7days']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// 趋势数据点（包含4个数据系列）
class TrendDataPoint {
  final String label;           // X轴标签（日期或月份）
  final int merchantTotal;      // 网吧数
  final int merchantOffline;    // 离线网吧数
  final int terminalTotal;      // 终端数
  final int terminal7days;      // 近7日运行终端数

  TrendDataPoint({
    required this.label,
    required this.merchantTotal,
    required this.merchantOffline,
    required this.terminalTotal,
    required this.terminal7days,
  });

  factory TrendDataPoint.fromJson(Map<String, dynamic> json, {bool isMonthly = false}) {
    return TrendDataPoint(
      label: isMonthly ? (json['ym'] ?? '') : (json['ymd'] ?? ''),
      merchantTotal: _parseInt(json['merchant_total']),
      merchantOffline: _parseInt(json['merchant_offline']),
      terminalTotal: _parseInt(json['terminal_total']),
      terminal7days: _parseInt(json['terminal_7days']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// 趋势数据（30天+12个月）
class TrendData {
  final List<TrendDataPoint> days30;    // 近30天数据
  final List<TrendDataPoint> months12;  // 近12个月数据

  TrendData({
    required this.days30,
    required this.months12,
  });

  factory TrendData.fromJson(Map<String, dynamic> json) {
    // 解析30天数据并反转（后端是倒序的）
    final ma30days = (json['ma30days'] as List?) ?? [];
    final days30 = ma30days
        .map((e) => TrendDataPoint.fromJson(e as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();

    // 解析12个月数据并反转（后端是倒序的）
    final ma12months = (json['ma12months'] as List?) ?? [];
    final months12 = ma12months
        .map((e) => TrendDataPoint.fromJson(e as Map<String, dynamic>, isMonthly: true))
        .toList()
        .reversed
        .toList();

    return TrendData(
      days30: days30,
      months12: months12,
    );
  }
}

/// 重启响应
class RestartResponse {
  final String message;
  final int targetCount;
  final String estimatedTime;

  RestartResponse({
    required this.message,
    required this.targetCount,
    required this.estimatedTime,
  });

  factory RestartResponse.fromJson(Map<String, dynamic> json) {
    return RestartResponse(
      message: json['message'] ?? '',
      targetCount: json['target_count'] ?? 0,
      estimatedTime: json['estimated_time'] ?? '',
    );
  }
}

/// 诊断响应
class DiagnoseResponse {
  final String message;
  final int nodeCount;
  final List<String> checkItems;
  final String estimatedTime;

  DiagnoseResponse({
    required this.message,
    required this.nodeCount,
    required this.checkItems,
    required this.estimatedTime,
  });

  factory DiagnoseResponse.fromJson(Map<String, dynamic> json) {
    return DiagnoseResponse(
      message: json['message'] ?? '',
      nodeCount: json['node_count'] ?? 0,
      checkItems: (json['check_items'] as List?)?.map((e) => e.toString()).toList() ?? [],
      estimatedTime: json['estimated_time'] ?? '',
    );
  }
}

/// Dashboard API 服务
class DashboardApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取统计数据
  Future<DashboardStats> getStats() async {
    final response = await _client.get('/home');
    return DashboardStats.fromJson(response.data ?? {});
  }

  /// 获取趋势数据
  Future<TrendData> getTrendData() async {
    final response = await _client.get('/home');
    return TrendData.fromJson(response.data ?? {});
  }

  /// 全部重启（后端未实现）
  Future<RestartResponse> restartAll() async {
    final response = await _client.post('/dashboard/restart-all');
    return RestartResponse.fromJson(response.data ?? {});
  }

  /// 网络诊断（后端未实现）
  Future<DiagnoseResponse> networkDiagnose() async {
    final response = await _client.post('/dashboard/network-diagnose');
    return DiagnoseResponse.fromJson(response.data ?? {});
  }
}

/// Provider
final dashboardApiProvider = Provider<DashboardApi>((ref) => DashboardApi());
