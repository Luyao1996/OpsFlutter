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

  /// 本地 buildNumber（用于 UI 显示）
  final int localBuildNumber;

  const UpdateCheckResult({
    required this.status,
    this.latest,
    this.aggregatedChangelogs = const [],
    this.host,
    this.localBuildNumber = 0,
  });

  bool get hasUpdate =>
      status == UpdateStatus.optional || status == UpdateStatus.forced;
  bool get isForced => status == UpdateStatus.forced;

  factory UpdateCheckResult.skipped() =>
      const UpdateCheckResult(status: UpdateStatus.skipped);

  factory UpdateCheckResult.upToDate(int localBuild) =>
      UpdateCheckResult(status: UpdateStatus.upToDate, localBuildNumber: localBuild);
}
