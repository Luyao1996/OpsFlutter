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
  });

  factory StartupItemStats.fromJson(Map<String, dynamic> json) {
    return StartupItemStats(
      id: (json['id'] ?? '').toString(),
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      launchCount: json['launch_count'] ?? 0,
      failureCount: json['failure_count'] ?? 0,
      survival1min: json['survival_1min'] ?? 0,
      survival10min: json['survival_10min'] ?? 0,
      survival20min: json['survival_20min'] ?? 0,
      lastUpdated: json['last_updated']?.toString() ?? '',
      icon: json['icon'],
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
  final List<StartupItemStats> items;

  const NetbarMonitorData({
    required this.id,
    required this.name,
    required this.group,
    required this.status,
    required this.terminalCount,
    required this.items,
  });

  factory NetbarMonitorData.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List? ?? [];
    return NetbarMonitorData(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      group: json['group'] ?? '默认分组',
      status: (json['status'] ?? 0) == 1 ? 'online' : 'offline',
      terminalCount: json['terminal_count'] ?? 0,
      items: itemsJson.map((e) => StartupItemStats.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  bool get hasAbnormal =>
      items.any((i) => i.failureRate > 10 || i.shortLifeRate > 50);
}
