import '../../../core/network/api_client.dart';

/// 网吧程序更新进度记录 API —— 对齐 toolboxPage `api/updateStatus.js`。
///
/// 数据来源：网吧本地服务端（Go）主动上报，云端按 (商户, round_id) 归并：
/// - 状态只前进不后退：pending < updating < success/failed
/// - 时间字段只补不覆盖，本次为 0 的不会清空已有值
/// - 老版本客户端不上报，后台显示「未上报」（status:'none'），属预期状态

/// 后端数值可能下发 int / String / double 三种形态，统一收口
int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

/// 后端布尔可能下发 bool / int / 字符串三种形态，统一收口
bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v?.toString().toLowerCase();
  return s == '1' || s == 'true';
}

/// 单条更新记录（paginator.data 元素）。
/// 字段名以 Web 端 UpdateRecordDialog.vue 模板实际取的 row.xxx 为准。
class UpdateStatusRow {
  final int merchantId;
  final String merchantName;
  final List<String> groupNames;
  final bool isOnline;
  final int offlineDays;

  /// 'none' | 'pending' | 'updating' | 'success' | 'failed'（大小写不敏感，
  /// 解析时统一转小写；'none' = 老版本客户端未上报，是预期状态而非异常）
  final String status;
  final String version;

  /// 以下时间均为 unix 秒；该带的字段没带时后端存 0，展示层按约定显示 --
  final int expectedAt;
  final int startedAt;
  final int finishedAt;

  /// 云端收到上报的时间（「疑似卡住」判定用的是它，不是 started_at）
  final int reportedAt;

  /// 失败原因
  final String msg;

  /// 疑似卡住 / 该轮记录已过期（判定由后端算好，前端只展示）
  final bool isSuspect;
  final bool isStale;

  /// 未上报的行 round_id 为空串，行唯一键需补 merchant_id
  final String roundId;

  UpdateStatusRow({
    required this.merchantId,
    required this.merchantName,
    required this.groupNames,
    required this.isOnline,
    required this.offlineDays,
    required this.status,
    required this.version,
    required this.expectedAt,
    required this.startedAt,
    required this.finishedAt,
    required this.reportedAt,
    required this.msg,
    required this.isSuspect,
    required this.isStale,
    required this.roundId,
  });

  factory UpdateStatusRow.fromJson(Map<String, dynamic> json) {
    return UpdateStatusRow(
      merchantId: _asInt(json['merchant_id']),
      merchantName: (json['merchant_name'] ?? '').toString(),
      groupNames: (json['group_names'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      isOnline: _asBool(json['is_online']),
      offlineDays: _asInt(json['offline_days']),
      status: (json['status'] ?? '').toString().toLowerCase(),
      version: (json['version'] ?? '').toString(),
      expectedAt: _asInt(json['expected_at']),
      startedAt: _asInt(json['started_at']),
      finishedAt: _asInt(json['finished_at']),
      reportedAt: _asInt(json['reported_at']),
      msg: (json['msg'] ?? '').toString(),
      isSuspect: _asBool(json['is_suspect']),
      isStale: _asBool(json['is_stale']),
      roundId: (json['round_id'] ?? '').toString(),
    );
  }
}

/// 全量口径的状态计数（不随筛选变化）
class UpdateStatusSummary {
  final int total;
  final int none;
  final int pending;
  final int updating;
  final int success;
  final int failed;
  final int suspect;
  final int stale;

  const UpdateStatusSummary({
    this.total = 0,
    this.none = 0,
    this.pending = 0,
    this.updating = 0,
    this.success = 0,
    this.failed = 0,
    this.suspect = 0,
    this.stale = 0,
  });

  factory UpdateStatusSummary.fromJson(Map<String, dynamic> json) {
    return UpdateStatusSummary(
      total: _asInt(json['total']),
      none: _asInt(json['none']),
      pending: _asInt(json['pending']),
      updating: _asInt(json['updating']),
      success: _asInt(json['success']),
      failed: _asInt(json['failed']),
      suspect: _asInt(json['suspect']),
      stale: _asInt(json['stale']),
    );
  }
}

/// GET /update-status 返回：data.paginator（Laravel 分页器）+ summary + suspectMinutes
class UpdateStatusListResponse {
  final List<UpdateStatusRow> rows;
  final int total;
  final int perPage;
  final int currentPage;
  final int lastPage;
  final UpdateStatusSummary summary;

  /// 「疑似卡住」判定阈值（分钟），只用于提示文案，判定本身在行的 is_suspect
  final int suspectMinutes;

  UpdateStatusListResponse({
    required this.rows,
    required this.total,
    required this.perPage,
    required this.currentPage,
    required this.lastPage,
    required this.summary,
    required this.suspectMinutes,
  });

  factory UpdateStatusListResponse.fromJson(Map<String, dynamic> json) {
    final paginator = json['paginator'];
    final pMap = paginator is Map
        ? Map<String, dynamic>.from(paginator)
        : <String, dynamic>{};
    final list = pMap['data'];
    final rows = list is List
        ? list
            .whereType<Map>()
            .map((e) => UpdateStatusRow.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <UpdateStatusRow>[];
    final summaryRaw = json['summary'];
    return UpdateStatusListResponse(
      rows: rows,
      total: pMap.containsKey('total') ? _asInt(pMap['total']) : rows.length,
      perPage: _asInt(pMap['per_page']),
      currentPage: _asInt(pMap['current_page']),
      lastPage: _asInt(pMap['last_page']),
      summary: summaryRaw is Map
          ? UpdateStatusSummary.fromJson(Map<String, dynamic>.from(summaryRaw))
          : const UpdateStatusSummary(),
      suspectMinutes: _asInt(json['suspectMinutes']),
    );
  }
}

class UpdateStatusApi {
  final ApiClient _client = ApiClient.instance;

  /// 查询更新记录列表。
  ///
  /// [status] 是筛选的唯一入口，可选值：
  /// none | pending | updating | success | failed | suspect | stale。
  /// suspect / stale 在行数据里是布尔字段 is_suspect / is_stale，
  /// 但查询时并非独立参数，同样传给 status（后端不认 is_suspect=1 这种参数名，
  /// 会静默忽略返回全量）。
  Future<UpdateStatusListResponse> getUpdateStatusList({
    int page = 1,
    int size = 50,
    String keyword = '',
    String status = '',
  }) async {
    final params = <String, dynamic>{
      'page': page,
      // 每页条数的参数名后端未明确（返回里是 per_page，项目其它接口用 size），
      // 两个都带上，后端认哪个都能生效，多余的那个会被忽略
      'size': size,
      'per_page': size,
    };
    final kw = keyword.trim();
    if (kw.isNotEmpty) params['keyword'] = kw;
    if (status.isNotEmpty) params['status'] = status;

    final response = await _client.get('/update-status', queryParameters: params);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      return UpdateStatusListResponse.fromJson(data);
    }
    return UpdateStatusListResponse.fromJson(const {});
  }
}
