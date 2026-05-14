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

  PlatformSnapshot({
    required this.platform,
    required this.available,
    this.unhealthy = false,
    this.staleSince,
    this.stoppedAt,
    this.ts,
  });

  factory PlatformSnapshot.fromJson(Map<String, dynamic> json, String platform) {
    return PlatformSnapshot(
      platform: platform,
      available: json['available'] == true,
      unhealthy: json['unhealthy'] == true,
      staleSince: json['stale_since']?.toString(),
      stoppedAt: json['stopped_at']?.toString(),
      ts: json['ts'] is num ? (json['ts'] as num).toInt() : null,
    );
  }
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

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
