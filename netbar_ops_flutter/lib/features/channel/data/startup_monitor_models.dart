class StartupItemStats {
  final String id;
  final String name;
  final String path;
  final int launchCount;
  final int failureCount;
  final int survival1min;
  final int survival10min;
  final int survival20min;
  final String lastUpdated;
  final String? icon;
  final List<dynamic> analysis;

  const StartupItemStats({
    required this.id,
    required this.name,
    required this.path,
    required this.launchCount,
    required this.failureCount,
    required this.survival1min,
    required this.survival10min,
    required this.survival20min,
    required this.lastUpdated,
    this.icon,
    this.analysis = const [],
  });

  /// 从 /channel 接口的 startups 数组解析
  /// 结构: {id, merchant_id, path, analysis}
  factory StartupItemStats.fromJson(Map<String, dynamic> json) {
    final path = json['path'] ?? '';
    // 从 path 中提取文件名作为 name
    String name = json['name'] ?? '';
    if (name.isEmpty && path.isNotEmpty) {
      final segments = path.split(RegExp(r'[/\\]'));
      name = segments.isNotEmpty ? segments.last : path;
    }

    // 解析 analysis 数组中的统计数据（如果有）
    final analysisList = json['analysis'] as List? ?? [];
    int launchCount = 0;
    int failureCount = 0;
    int survival1min = 0;
    int survival10min = 0;
    int survival20min = 0;

    // analysis 可能包含启动分析数据，后续根据实际结构调整
    for (final item in analysisList) {
      if (item is Map<String, dynamic>) {
        launchCount += (item['launch_count'] ?? 0) as int;
        failureCount += (item['failure_count'] ?? 0) as int;
        survival1min += (item['survival_1min'] ?? 0) as int;
        survival10min += (item['survival_10min'] ?? 0) as int;
        survival20min += (item['survival_20min'] ?? 0) as int;
      }
    }

    return StartupItemStats(
      id: (json['id'] ?? '').toString(),
      name: name,
      path: path,
      launchCount: launchCount,
      failureCount: failureCount,
      survival1min: survival1min,
      survival10min: survival10min,
      survival20min: survival20min,
      lastUpdated: json['last_updated']?.toString() ?? '',
      icon: json['icon'],
      analysis: analysisList,
    );
  }

  double get failureRate => launchCount == 0 ? 0 : failureCount / launchCount * 100;
  double get shortLifeRate => launchCount == 0 ? 0 : survival1min / launchCount * 100;
}

class NetbarMonitorData {
  final int id;
  final String name;
  final String group;
  final String status; // online | offline
  final int terminalCount;
  final int terminalAvg;
  final List<StartupItemStats> items;

  const NetbarMonitorData({
    required this.id,
    required this.name,
    required this.group,
    required this.status,
    required this.terminalCount,
    this.terminalAvg = 0,
    required this.items,
  });

  /// 从 /channel 接口解析
  /// 结构: {id, name, terminal_count, terminal_avg, is_online, groups, startups}
  factory NetbarMonitorData.fromJson(Map<String, dynamic> json) {
    // 从 startups 数组解析启动项
    final startupsJson = json['startups'] as List? ?? [];

    // 从 groups 数组取第一个分组的名称
    String groupName = '默认分组';
    final groups = json['groups'] as List?;
    if (groups != null && groups.isNotEmpty) {
      final firstGroup = groups.first;
      if (firstGroup is Map<String, dynamic>) {
        groupName = firstGroup['name'] ?? '默认分组';
      }
    }

    // is_online 是布尔值
    final isOnline = json['is_online'] == true;

    return NetbarMonitorData(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      group: groupName,
      status: isOnline ? 'online' : 'offline',
      terminalCount: json['terminal_count'] ?? 0,
      terminalAvg: json['terminal_avg'] ?? 0,
      items: startupsJson
          .map((e) => StartupItemStats.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  bool get hasAbnormal =>
      items.any((i) => i.failureRate > 10 || i.shortLifeRate > 50);
}
