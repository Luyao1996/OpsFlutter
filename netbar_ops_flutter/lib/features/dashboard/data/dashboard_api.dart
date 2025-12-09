import '../../../core/network/api_client.dart';

/// 仪表盘统计
class DashboardStats {
  final int totalNetbars;
  final int onlineNetbars;
  final int totalDesktops;
  final int onlineDesktops;
  final int totalChannels;
  final int activeChannels;
  final int totalUsers;
  final int vipDays;
  final int serverUptime;

  DashboardStats({
    required this.totalNetbars,
    required this.onlineNetbars,
    required this.totalDesktops,
    required this.onlineDesktops,
    required this.totalChannels,
    required this.activeChannels,
    required this.totalUsers,
    required this.vipDays,
    required this.serverUptime,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalNetbars: json['total_netbars'] ?? 0,
      onlineNetbars: json['online_netbars'] ?? 0,
      totalDesktops: json['total_desktops'] ?? 0,
      onlineDesktops: json['online_desktops'] ?? 0,
      totalChannels: json['total_channels'] ?? 0,
      activeChannels: json['active_channels'] ?? 0,
      totalUsers: json['total_users'] ?? 0,
      vipDays: json['vip_days'] ?? 0,
      serverUptime: json['server_uptime'] ?? 0,
    );
  }
}

/// 趋势数据点
class TrendDataPoint {
  final String date;
  final int terminals;

  TrendDataPoint({required this.date, required this.terminals});

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
    return TrendDataPoint(
      date: json['date'] ?? '',
      terminals: json['terminals'] ?? 0,
    );
  }
}

/// Dashboard API 服务
class DashboardApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取统计数据
  Future<DashboardStats> getStats({int? netbarId}) async {
    final params = <String, dynamic>{};
    if (netbarId != null) params['netbar_id'] = netbarId;
    final response = await _client.get('/dashboard', queryParameters: params);
    return DashboardStats.fromJson(response.data);
  }

  /// 获取趋势数据
  Future<List<TrendDataPoint>> getTrendData({int? netbarId}) async {
    final params = <String, dynamic>{};
    if (netbarId != null) params['netbar_id'] = netbarId;
    final response = await _client.get(
      '/dashboard/trend',
      queryParameters: params,
    );
    final list = response.data as List? ?? [];
    return list.map((e) => TrendDataPoint.fromJson(e)).toList();
  }
}

