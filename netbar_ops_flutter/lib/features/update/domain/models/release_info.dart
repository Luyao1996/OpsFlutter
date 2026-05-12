class ReleaseInfo {
  final String version;
  final int buildNumber;
  final String path;
  final String md5;
  final int size;
  final bool forceUpdate;
  final bool isInstaller;
  final String changelog;
  final DateTime uploadTime;

  const ReleaseInfo({
    required this.version,
    required this.buildNumber,
    required this.path,
    required this.md5,
    required this.size,
    required this.forceUpdate,
    required this.isInstaller,
    required this.changelog,
    required this.uploadTime,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    return ReleaseInfo(
      version: json['version'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      path: json['path'] as String? ?? '',
      md5: json['md5'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      isInstaller: json['isInstaller'] as bool? ?? false,
      changelog: json['changelog'] as String? ?? '',
      uploadTime:
          DateTime.tryParse(json['uploadTime'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
