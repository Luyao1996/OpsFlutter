import 'models/release_info.dart';

enum UpdateStatus {
  /// 跳过本次检查（无网/解析失败/不支持的平台等）
  skipped,

  /// 已是最新
  upToDate,

  /// 有可选更新
  optional,

  /// 强制更新（不可跳过）
  forced,
}

class UpdateCheckResult {
  final UpdateStatus status;
  final ReleaseInfo? latest;

  /// 本地 build < latest.build 之间所有版本的 changelog（已按 buildNumber 降序）
  final List<ReleaseInfo> aggregatedChangelogs;

  /// 命中的 OSS 公共下载域名（apk/exe 拼接此前缀使用）
  final String? host;

  /// 本地版本号（pubspec.yaml 中 version: 字段冒号前部分，用于 UI 显示）
  final String localVersion;

  /// 本地 buildNumber（pubspec.yaml 中 version: 字段 + 后的整数，用于版本比较和 UI 显示）
  final int localBuildNumber;

  const UpdateCheckResult({
    required this.status,
    this.latest,
    this.aggregatedChangelogs = const [],
    this.host,
    this.localVersion = '',
    this.localBuildNumber = 0,
  });

  bool get hasUpdate =>
      status == UpdateStatus.optional || status == UpdateStatus.forced;
  bool get isForced => status == UpdateStatus.forced;

  factory UpdateCheckResult.skipped() =>
      const UpdateCheckResult(status: UpdateStatus.skipped);

  factory UpdateCheckResult.upToDate(String localVersion, int localBuild) =>
      UpdateCheckResult(
        status: UpdateStatus.upToDate,
        localVersion: localVersion,
        localBuildNumber: localBuild,
      );
}
