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

  /// 本机当前是否运行的是预览版（local.build == manifest.preview.buildNumber）。
  /// 检查失败/跳过时为 false。
  final bool isCurrentPreview;

  /// 最近 N 条正式版（按 uploadTime 倒序）。供"检查更新"弹窗展示更新历史。
  /// 检查失败/跳过时为空。
  final List<ReleaseInfo> recentReleases;

  /// 不论当前身份，可升级的正式版候选。
  /// = (releases[0].buildNumber > local.build) ? releases[0] : null
  /// 供手动「检查更新」弹窗使用，让正式版/预览版用户都能看到正式版更新选项。
  final ReleaseInfo? availableRelease;

  /// 不论当前身份，可升级的预览版候选。
  /// = (preview != null && preview.buildNumber > local.build) ? preview : null
  /// 供手动「检查更新」弹窗使用，让正式版用户也能主动尝鲜预览版。
  final ReleaseInfo? availablePreview;

  const UpdateCheckResult({
    required this.status,
    this.latest,
    this.aggregatedChangelogs = const [],
    this.host,
    this.localVersion = '',
    this.localBuildNumber = 0,
    this.isCurrentPreview = false,
    this.recentReleases = const [],
    this.availableRelease,
    this.availablePreview,
  });

  bool get hasUpdate =>
      status == UpdateStatus.optional || status == UpdateStatus.forced;
  bool get isForced => status == UpdateStatus.forced;

  factory UpdateCheckResult.skipped() =>
      const UpdateCheckResult(status: UpdateStatus.skipped);

  factory UpdateCheckResult.upToDate(
    String localVersion,
    int localBuild, {
    String? host,
    bool isCurrentPreview = false,
    List<ReleaseInfo> recentReleases = const [],
    ReleaseInfo? availableRelease,
    ReleaseInfo? availablePreview,
  }) =>
      UpdateCheckResult(
        status: UpdateStatus.upToDate,
        host: host,
        localVersion: localVersion,
        localBuildNumber: localBuild,
        isCurrentPreview: isCurrentPreview,
        recentReleases: recentReleases,
        availableRelease: availableRelease,
        availablePreview: availablePreview,
      );
}
