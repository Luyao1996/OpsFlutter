/// iOS App Store 更新检查结果（轻量模型）。
///
/// 与 [UpdateCheckResult]（Android/Windows 的 manifest+下载安装）完全分开：
/// iOS 不能自己下载安装 IPA（Apple 审核 2.5.2），只能"查 App Store 版本 + 跳转"，
/// 因此本模型【不携带】任何 download path / md5 / size，只有版本号与跳转链接。
enum AppStoreCheckStatus {
  /// 有新版本可更新
  updateAvailable,

  /// 已是最新
  upToDate,

  /// 跳过（无网 / 查不到 / 限流 / 解析失败），一律静默处理
  skipped,
}

class AppStoreCheckResult {
  final AppStoreCheckStatus status;

  /// 本机当前版本（CFBundleShortVersionString，如 1.0.0）
  final String localVersion;

  /// App Store 上的最新版本
  final String storeVersion;

  /// 跳转 App Store 的链接（优先用 iTunes Lookup 返回的 trackViewUrl）
  final String storeUrl;

  /// 本次版本的更新说明（releaseNotes，可空）
  final String releaseNotes;

  const AppStoreCheckResult({
    required this.status,
    this.localVersion = '',
    this.storeVersion = '',
    this.storeUrl = '',
    this.releaseNotes = '',
  });

  bool get hasUpdate => status == AppStoreCheckStatus.updateAvailable;

  factory AppStoreCheckResult.skipped() =>
      const AppStoreCheckResult(status: AppStoreCheckStatus.skipped);

  factory AppStoreCheckResult.upToDate(
    String localVersion, {
    String storeVersion = '',
  }) =>
      AppStoreCheckResult(
        status: AppStoreCheckStatus.upToDate,
        localVersion: localVersion,
        storeVersion: storeVersion,
      );

  factory AppStoreCheckResult.update({
    required String localVersion,
    required String storeVersion,
    required String storeUrl,
    required String releaseNotes,
  }) =>
      AppStoreCheckResult(
        status: AppStoreCheckStatus.updateAvailable,
        localVersion: localVersion,
        storeVersion: storeVersion,
        storeUrl: storeUrl,
        releaseNotes: releaseNotes,
      );
}
