import '../../../core/network/api_client.dart';

/// 启动项分析数据
class StartupAnalysis {
  final int startupTotal;  // 启动次数
  final int startupFail;   // 失败次数
  final int durationLt1;   // 存活<1分钟
  final int durationLt10;  // 存活<10分钟
  final int durationLt20;  // 存活<20分钟

  StartupAnalysis({
    required this.startupTotal,
    required this.startupFail,
    required this.durationLt1,
    required this.durationLt10,
    required this.durationLt20,
  });

  factory StartupAnalysis.fromJson(Map<String, dynamic> json) {
    return StartupAnalysis(
      startupTotal: json['startup_total'] ?? 0,
      startupFail: json['startup_fail'] ?? 0,
      durationLt1: json['duration_lt1'] ?? 0,
      durationLt10: json['duration_lt10'] ?? 0,
      durationLt20: json['duration_lt20'] ?? 0,
    );
  }
}

/// 启动项信息
class StartupInfo {
  final int id;
  final int merchantId;
  final String path;
  final StartupAnalysis analysis;

  StartupInfo({
    required this.id,
    required this.merchantId,
    required this.path,
    required this.analysis,
  });

  factory StartupInfo.fromJson(Map<String, dynamic> json) {
    final analysisData = json['analysis'];
    return StartupInfo(
      id: json['id'] ?? 0,
      merchantId: json['merchant_id'] ?? 0,
      path: json['path'] ?? '',
      analysis: analysisData is Map<String, dynamic>
          ? StartupAnalysis.fromJson(analysisData)
          : StartupAnalysis(
              startupTotal: 0,
              startupFail: 0,
              durationLt1: 0,
              durationLt10: 0,
              durationLt20: 0,
            ),
    );
  }
}

/// 分组信息
class GroupInfo {
  final int id;
  final String name;

  GroupInfo({required this.id, required this.name});

  factory GroupInfo.fromJson(Map<String, dynamic> json) {
    return GroupInfo(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

/// 通道监控网吧数据
class ChannelMerchant {
  final int id;
  final String name;
  final int terminalCount;
  final int terminalAvg;
  final bool isOnline;
  final List<GroupInfo> groups;
  final List<StartupInfo> startups;

  ChannelMerchant({
    required this.id,
    required this.name,
    required this.terminalCount,
    required this.terminalAvg,
    required this.isOnline,
    required this.groups,
    required this.startups,
  });

  factory ChannelMerchant.fromJson(Map<String, dynamic> json) {
    final groupsList = json['groups'] as List? ?? [];
    final startupsList = json['startups'] as List? ?? [];

    return ChannelMerchant(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      terminalCount: json['terminal_count'] ?? 0,
      terminalAvg: json['terminal_avg'] ?? 0,
      isOnline: json['is_online'] == true,
      groups: groupsList
          .map((g) => GroupInfo.fromJson(g as Map<String, dynamic>))
          .toList(),
      startups: startupsList
          .map((s) => StartupInfo.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 分组名称（逗号分隔）
  String get groupNames {
    if (groups.isEmpty) return '-';
    return groups.map((g) => g.name).where((n) => n.isNotEmpty).join('、');
  }
}

/// 通道监控响应
class ChannelMonitorResponse {
  final List<ChannelMerchant> merchants;
  final int total;
  final int currentPage;
  final int lastPage;

  ChannelMonitorResponse({
    required this.merchants,
    required this.total,
    required this.currentPage,
    required this.lastPage,
  });

  factory ChannelMonitorResponse.fromJson(Map<String, dynamic> json) {
    final paginator = json['paginator'] as Map<String, dynamic>? ?? {};
    final dataList = paginator['data'] as List? ?? [];

    return ChannelMonitorResponse(
      merchants: dataList
          .map((m) => ChannelMerchant.fromJson(m as Map<String, dynamic>))
          .toList(),
      total: paginator['total'] ?? 0,
      currentPage: paginator['current_page'] ?? 1,
      lastPage: paginator['last_page'] ?? 1,
    );
  }
}

/// 通道监控 API
class ChannelMonitorApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取通道监控数据
  Future<ChannelMonitorResponse> getChannelMonitor({
    int page = 1,
    int size = 20,
    String type = 'merchant',
    String? keyword,
    String? isOnline, // '1' 在线, '0' 离线, '' 全部
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'size': size,
      'type': type,
    };
    if (keyword != null && keyword.isNotEmpty) {
      params['keyword'] = keyword;
    }
    if (isOnline != null && isOnline.isNotEmpty) {
      params['is_online'] = isOnline;
    }

    final response = await _client.get('/channel', queryParameters: params);
    return ChannelMonitorResponse.fromJson(response.data ?? {});
  }
}
