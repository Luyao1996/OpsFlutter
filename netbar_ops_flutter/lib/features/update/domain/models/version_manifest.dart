import 'release_info.dart';

class PlatformManifest {
  final int minSupportedBuild;
  final List<ReleaseInfo> releases; // 按 buildNumber 降序
  // 当前预览版（最多一条）。release 命令默认写入这里，
  // release-preview-promote 命令把它移入 releases。
  final ReleaseInfo? preview;

  const PlatformManifest({
    required this.minSupportedBuild,
    required this.releases,
    this.preview,
  });

  ReleaseInfo? get latest => releases.isEmpty ? null : releases.first;

  /// 返回 buildNumber 严格大于 localBuild 的所有版本（已按 buildNumber 降序）。
  List<ReleaseInfo> changelogsSince(int localBuild) {
    return releases.where((r) => r.buildNumber > localBuild).toList();
  }

  factory PlatformManifest.fromJson(Map<String, dynamic> json) {
    final list = (json['releases'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseInfo.fromJson)
        .toList();
    // 兜底再排一次（防止服务端没排好）
    list.sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
    final previewRaw = json['preview'];
    return PlatformManifest(
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 1,
      releases: list,
      preview: previewRaw is Map<String, dynamic>
          ? ReleaseInfo.fromJson(previewRaw)
          : null,
    );
  }
}

class VersionManifest {
  final PlatformManifest? android;
  final PlatformManifest? windows;

  const VersionManifest({this.android, this.windows});

  PlatformManifest? forPlatform(String platform) {
    switch (platform) {
      case 'android':
        return android;
      case 'windows':
        return windows;
    }
    return null;
  }

  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      android: json['android'] is Map<String, dynamic>
          ? PlatformManifest.fromJson(json['android'] as Map<String, dynamic>)
          : null,
      windows: json['windows'] is Map<String, dynamic>
          ? PlatformManifest.fromJson(json['windows'] as Map<String, dynamic>)
          : null,
    );
  }
}
