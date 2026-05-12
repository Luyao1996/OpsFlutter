import 'release_info.dart';

class PlatformManifest {
  final int minSupportedBuild;
  final List<ReleaseInfo> releases; // 按 buildNumber 降序

  const PlatformManifest({
    required this.minSupportedBuild,
    required this.releases,
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
    return PlatformManifest(
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 1,
      releases: list,
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
