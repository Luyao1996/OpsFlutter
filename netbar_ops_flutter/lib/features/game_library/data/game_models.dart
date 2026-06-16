import 'game_constants.dart';

/// 游戏列表 item（来自 /lists 接口 platforms.<p>.items.<gid>）
class GameItem {
  final int gid;
  final String? name;
  final String? friendlyName;
  final int sizeBytes;
  final int localVersion;
  final int cloudVersion;
  final String? category;
  final int? popularity;
  final int? idcUpdateTs;
  final String? localPath;
  final String platform;
  /// 上一次启动时间（秒级 unix 时间戳），用于「闲置游戏」筛选；无则为 null
  final int? lastLaunchTs;

  GameItem({
    required this.gid,
    required this.platform,
    this.name,
    this.friendlyName,
    this.sizeBytes = 0,
    this.localVersion = 0,
    this.cloudVersion = 0,
    this.category,
    this.popularity,
    this.idcUpdateTs,
    this.localPath,
    this.lastLaunchTs,
  });

  String get rowKey => '$platform:$gid';

  /// local_path 非空视为已安装
  bool get isInstalled => localPath != null && localPath!.isNotEmpty;

  /// story 平台特殊：local_version > 0 也算已安装
  bool get isInstalledIncludingStory =>
      isInstalled || (platform == kPlatformStory && localVersion > 0);

  /// icafe8 / goodgame 的 cloud_version == 0xFFFFFFFF 标记废弃
  bool get isDeprecated {
    if (platform != kPlatformIcafe8 && platform != kPlatformGoodgame) {
      return false;
    }
    return cloudVersion == 0xFFFFFFFF;
  }

  /// 是否系统/补丁/资源类（仅 icafe8）
  bool get isSystemCategory {
    if (platform != kPlatformIcafe8 || category == null) return false;
    final c = category!;
    return c.contains('系统') || c.contains('补丁') || c.contains('资源');
  }

  /// 是否可更新：已安装 + cloud_version > local_version 且都 > 0 且未废弃
  bool get isUpgradable {
    if (!isInstalled) return false;
    if (cloudVersion == 0xFFFFFFFF) return false;
    return cloudVersion > 0 && localVersion > 0 && cloudVersion > localVersion;
  }

  GameRowState get rowState {
    if (isDeprecated) return GameRowState.deprecated;
    if (isUpgradable) return GameRowState.upgrade;
    if (isInstalledIncludingStory) return GameRowState.installed;
    return GameRowState.pending;
  }

  /// 是否受保护分类 = 网吧本地应用 || 平台对应的系统/PNP 分类
  bool get isProtectedCategory {
    final c = category;
    if (c == null || c.isEmpty) return false;
    if (c == kProtectedCatLocalApp) return true;
    final list = kProtectedCatsByPlatform[platform];
    return list != null && list.contains(c);
  }

  factory GameItem.fromJson(Map<String, dynamic> json, String platform) {
    return GameItem(
      gid: _toInt(json['gid']),
      platform: platform,
      name: json['name']?.toString(),
      friendlyName: json['friendly_name']?.toString(),
      sizeBytes: _toInt(json['size_bytes']),
      localVersion: _toInt(json['local_version']),
      cloudVersion: _toInt(json['cloud_version']),
      category: json['category']?.toString(),
      popularity: json['popularity'] is num
          ? (json['popularity'] as num).toInt()
          : null,
      idcUpdateTs: json['idc_update_ts'] is num
          ? (json['idc_update_ts'] as num).toInt()
          : null,
      localPath: json['local_path']?.toString(),
      lastLaunchTs: json['last_launch_ts'] is num
          ? (json['last_launch_ts'] as num).toInt()
          : null,
    );
  }
}

/// 下载任务（来自 /downloading 接口 platforms.<p>.items.<gid>）
class DownloadTask {
  final int gid;
  final String platform;
  final String? name;
  final String? seat;
  final int status;
  final int? statusRaw;
  final int downloadedBytes;
  final int totalBytes;
  final int speed; // 字节/秒
  final int etaMs;
  final double percent;

  DownloadTask({
    required this.gid,
    required this.platform,
    required this.status,
    this.name,
    this.seat,
    this.statusRaw,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.etaMs = 0,
    this.percent = 0,
  });

  String get rowKey => '$platform:$gid';

  factory DownloadTask.fromJson(Map<String, dynamic> json, String platform) {
    return DownloadTask(
      gid: _toInt(json['gid']),
      platform: platform,
      name: json['name']?.toString(),
      seat: json['seat']?.toString(),
      status: _toInt(json['status']),
      statusRaw: json['status_raw'] is num
          ? (json['status_raw'] as num).toInt()
          : null,
      downloadedBytes: _toInt(json['downloaded_bytes']),
      totalBytes: _toInt(json['total_bytes']),
      speed: _toInt(json['speed']),
      etaMs: _toInt(json['eta_ms']),
      percent: (json['percent'] is num)
          ? (json['percent'] as num).toDouble()
          : 0.0,
    );
  }
}

/// 平台快照（来自 platforms.<p>，含 available + 健康字段 + items）
class PlatformSnapshot {
  final String platform;
  final bool available;
  final bool unhealthy;
  final String? staleSince; // RFC3339
  final String? stoppedAt;
  final int? ts;

  /// 该平台游戏盘盘符（来自 platforms.<p>.disk）。
  /// 后端形如 {"R":"R","T":"T"}；解析为去重大写的单字母列表，如 ['R','T']。
  /// 仅 /lists 接口下发；/downloading 不带此字段（合并快照时用 withDisk 保留）。
  final List<String> disk;

  PlatformSnapshot({
    required this.platform,
    required this.available,
    this.unhealthy = false,
    this.staleSince,
    this.stoppedAt,
    this.ts,
    this.disk = const [],
  });

  /// 仅替换 disk 字段：合并 lists/downloading 快照时，保留 lists 的 disk 用
  /// （downloading 响应无 disk，直接覆盖会把盘符冲没）。
  PlatformSnapshot withDisk(List<String> d) => PlatformSnapshot(
        platform: platform,
        available: available,
        unhealthy: unhealthy,
        staleSince: staleSince,
        stoppedAt: stoppedAt,
        ts: ts,
        disk: d,
      );

  factory PlatformSnapshot.fromJson(Map<String, dynamic> json, String platform) {
    return PlatformSnapshot(
      platform: platform,
      available: json['available'] == true,
      unhealthy: json['unhealthy'] == true,
      staleSince: json['stale_since']?.toString(),
      stoppedAt: json['stopped_at']?.toString(),
      ts: json['ts'] is num ? (json['ts'] as num).toInt() : null,
      disk: _parseDiskLetters(json['disk']),
    );
  }
}

/// 磁盘容量信息（来自 GET /game_library/disk_info）。
/// 接口响应以带冒号的盘符为 key（"R:"），顶层另有 ts；此模型对应单个盘符的 value。
class DiskInfo {
  /// 盘符首字母大写，如 "R"
  final String letter;
  final int availableBytes;
  final int totalBytes;
  final String volumeLabel;
  final bool isSsd;

  /// 非空表示该盘不可用（如 "3, The system cannot find the path specified."）
  final String err;

  const DiskInfo({
    required this.letter,
    this.availableBytes = 0,
    this.totalBytes = 0,
    this.volumeLabel = '',
    this.isSsd = false,
    this.err = '',
  });

  /// 是否可用：无错误且总量为正
  bool get usable => err.isEmpty && totalBytes > 0;

  /// 已用比例 0..1（不可用时为 0）
  double get usedRatio {
    if (!usable) return 0;
    final r = 1 - availableBytes / totalBytes;
    if (r < 0) return 0;
    if (r > 1) return 1;
    return r;
  }

  /// 可用（剩余）比例 0..1
  double get freeRatio => usable ? (1 - usedRatio) : 0;

  factory DiskInfo.fromJson(String letter, Map<String, dynamic> json) {
    return DiskInfo(
      letter: letter,
      availableBytes: _toInt(json['available_bytes']),
      totalBytes: _toInt(json['total_bytes']),
      volumeLabel: json['volume_label']?.toString() ?? '',
      isSsd: json['is_ssd'] == true,
      err: json['err']?.toString() ?? '',
    );
  }
}

/// 解析 platforms.<p>.disk 为去重大写单字母盘符列表。
/// 兼容三种后端形态：map {"R":"R"} 取 key / 数组 ["R"] / 逗号字符串 "R,T"。
List<String> _parseDiskLetters(dynamic raw) {
  final set = <String>{};
  void add(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) return;
    final c = s[0].toUpperCase();
    final code = c.codeUnitAt(0);
    if (code >= 0x41 && code <= 0x5A) set.add(c); // 仅 A-Z
  }

  if (raw is Map) {
    raw.forEach((k, _) => add(k)); // key 即盘符
  } else if (raw is List) {
    for (final v in raw) {
      add(v);
    }
  } else if (raw is String) {
    for (final part in raw.split(',')) {
      add(part);
    }
  }
  final list = set.toList()..sort();
  return list;
}

/// /lists 解析结果聚合
class GameLibraryListsResult {
  final List<GameItem> games;
  final Map<String, PlatformSnapshot> snapshots;

  GameLibraryListsResult({required this.games, required this.snapshots});
}

/// /downloading 解析结果聚合
class GameLibraryDownloadingResult {
  final List<DownloadTask> tasks;
  final Map<String, PlatformSnapshot> snapshots;

  GameLibraryDownloadingResult({required this.tasks, required this.snapshots});
}

/// 写接口（do_download / cancle_download / top_download）统一响应
class GameOpResult {
  /// 是否 HTTP 成功
  final bool ok;
  final int status;
  /// 每个 gid 的结果字符串：'ok' / 'already_downloading' / 'rejected: not owner' / 'not_in_progress' / 'err:...'
  final Map<int, String> results;
  /// do_download 时若自动取消了旧任务，会附带
  final CancelledTask? cancelled;
  final String? error;

  GameOpResult({
    required this.ok,
    required this.status,
    this.results = const {},
    this.cancelled,
    this.error,
  });
}

class CancelledTask {
  final String platform;
  final int gid;
  final String? result;
  CancelledTask({required this.platform, required this.gid, this.result});

  factory CancelledTask.fromJson(Map<String, dynamic> json) => CancelledTask(
        platform: json['platform']?.toString() ?? '',
        gid: _toInt(json['gid']),
        result: json['result']?.toString(),
      );
}

/// 回收策略（与后端 cfg.Recycle 对齐）
/// 注意：freeThresholdUi 是 UI 语义"占用%"；API 字段 free_threshold 是"剩余%"；
/// 100-X 反转规则只在 GameLibraryApi.saveRecyclePlan / 从 /config 拉取时统一做。
class RecyclePlan {
  final bool enabled;
  /// UI 视角"占用%" (0..100)；null 表示未填写
  final int? freeThresholdUi;
  /// ≥0；null 表示未填写
  final int? retainDays;
  /// Go time.Weekday: Sun=0..Sat=6
  final List<int> weekdays;
  /// "HH:MM"
  final String time;
  /// bitmask: 1=删从未启动 / 2=删云端下架；默认 3
  final int delFlags;
  /// 后端 platforms map：icafe8/cloud 可开；goodgame/story 服务端强制 false
  final Map<String, bool> platforms;

  const RecyclePlan({
    required this.enabled,
    this.freeThresholdUi,
    this.retainDays,
    this.weekdays = const [],
    this.time = RecycleDefaults.time,
    this.delFlags = RecycleDefaults.delFlags,
    this.platforms = const {},
  });

  static const RecyclePlan empty = RecyclePlan(enabled: false);

  RecyclePlan copyWith({
    bool? enabled,
    int? freeThresholdUi,
    Object? retainDays = _sentinel,
    List<int>? weekdays,
    String? time,
    int? delFlags,
    Map<String, bool>? platforms,
  }) {
    return RecyclePlan(
      enabled: enabled ?? this.enabled,
      freeThresholdUi: freeThresholdUi ?? this.freeThresholdUi,
      retainDays: identical(retainDays, _sentinel)
          ? this.retainDays
          : retainDays as int?,
      weekdays: weekdays ?? this.weekdays,
      time: time ?? this.time,
      delFlags: delFlags ?? this.delFlags,
      platforms: platforms ?? this.platforms,
    );
  }

  /// 从 GET /game_library/config 返回体的 .recycle 节点解析；同时把 free_threshold 由 API 剩余% 反转为 UI 占用%
  /// 同时返回 timer_active（如有），用于 enabled 兜底
  static RecyclePlan fromConfigJson(Map<String, dynamic> root) {
    final r = root['recycle'];
    final timerActive = root['timer_active'];
    if (r is! Map) {
      return RecyclePlan(enabled: timerActive == true);
    }
    final m = r.cast<String, dynamic>();
    final platformsRaw = m['platforms'];
    final platforms = <String, bool>{};
    if (platformsRaw is Map) {
      platformsRaw.forEach((k, v) {
        platforms[k.toString()] = v == true;
      });
    }
    final anyOn = platforms.values.any((v) => v);
    int? freeThrUi;
    final ftRaw = m['free_threshold'];
    if (ftRaw is num) freeThrUi = 100 - ftRaw.toInt();
    int? rd;
    final rdRaw = m['retain_days'];
    if (rdRaw is num) rd = rdRaw.toInt();
    final weekdaysRaw = m['weekdays'];
    final weekdays = <int>[];
    if (weekdaysRaw is List) {
      for (final w in weekdaysRaw) {
        if (w is num) weekdays.add(w.toInt());
      }
    }
    final timeRaw = m['time']?.toString();
    final delFlagsRaw = m['del_flags'];
    return RecyclePlan(
      enabled: timerActive is bool ? timerActive : anyOn,
      freeThresholdUi: freeThrUi,
      retainDays: rd,
      weekdays: weekdays,
      time: (timeRaw != null && timeRaw.isNotEmpty)
          ? timeRaw
          : RecycleDefaults.time,
      delFlags: delFlagsRaw is num ? delFlagsRaw.toInt() : RecycleDefaults.delFlags,
      platforms: platforms,
    );
  }
}

const _sentinel = Object();

/// 批量删除结果（成功数 + 失败明细）
class BatchDeleteResult {
  final int success;
  final List<BatchDeleteFailure> failures;
  const BatchDeleteResult({required this.success, required this.failures});
}

class BatchDeleteFailure {
  final String name;
  final String reason;
  const BatchDeleteFailure({required this.name, required this.reason});
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
