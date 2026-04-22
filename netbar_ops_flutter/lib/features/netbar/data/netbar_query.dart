import 'netbar_api.dart';

/// 网吧列表排序规则（对齐 Web 端 sortRuleToOrderBy）。
///
/// 注：Web 端的 offline_recent_first / offline_far_first 依赖后端 logout_at 字段，
/// 当前 Flutter Netbar 模型未包含该字段，暂不提供该两种排序；后续若后端下发再补。
enum NetbarSort {
  idDesc,
  idAsc,
  terminalDesc,
  terminalAsc,
  statusOnlineFirst,
  statusOfflineFirst,
}

class NetbarQueryParams {
  final String keyword;
  final int? groupId;
  final int? isOnline; // null=全部, 1=在线, 0=离线
  final NetbarSort sort;
  final int page;
  final int pageSize;

  const NetbarQueryParams({
    this.keyword = '',
    this.groupId,
    this.isOnline,
    this.sort = NetbarSort.idDesc,
    this.page = 1,
    this.pageSize = 20,
  });

  NetbarQueryParams copyWith({
    String? keyword,
    int? groupId,
    bool clearGroupId = false,
    int? isOnline,
    bool clearIsOnline = false,
    NetbarSort? sort,
    int? page,
    int? pageSize,
  }) {
    return NetbarQueryParams(
      keyword: keyword ?? this.keyword,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      isOnline: clearIsOnline ? null : (isOnline ?? this.isOnline),
      sort: sort ?? this.sort,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  bool get hasActiveFilter =>
      keyword.isNotEmpty || groupId != null || isOnline != null;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetbarQueryParams &&
        other.keyword == keyword &&
        other.groupId == groupId &&
        other.isOnline == isOnline &&
        other.sort == sort &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(keyword, groupId, isOnline, sort, page, pageSize);
}

class OnlineStats {
  final int online;
  final int offline;

  const OnlineStats({this.online = 0, this.offline = 0});

  int get total => online + offline;

  Map<String, dynamic> toJson() => {'online': online, 'offline': offline};

  factory OnlineStats.fromJson(Map<String, dynamic> json) => OnlineStats(
        online: (json['online'] as num?)?.toInt() ?? 0,
        offline: (json['offline'] as num?)?.toInt() ?? 0,
      );
}

class NetbarQueryResult {
  final List<Netbar> rows;
  final int total;
  final OnlineStats stats;

  const NetbarQueryResult({
    required this.rows,
    required this.total,
    required this.stats,
  });

  static const empty = NetbarQueryResult(
    rows: [],
    total: 0,
    stats: OnlineStats(),
  );
}
