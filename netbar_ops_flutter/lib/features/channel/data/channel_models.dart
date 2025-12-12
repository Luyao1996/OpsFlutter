/// 通道资源（文件/文件夹）
class ChannelFile {
  final int id;
  final String name;
  final String path;
  final int? parentId;
  final bool isDirectory;
  final String type;
  final int size;
  final String zone; // HEADQUARTERS, BRANCH, PUBLIC
  final String uploader;
  final int uploaderId;
  final bool isGlobal;
  final String? content;
  final String createdAt;
  final String updatedAt;

  ChannelFile({
    required this.id,
    required this.name,
    required this.path,
    required this.parentId,
    required this.isDirectory,
    required this.type,
    required this.size,
    required this.zone,
    required this.uploader,
    required this.uploaderId,
    required this.isGlobal,
    this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChannelFile.fromJson(Map<String, dynamic> json) {
    return ChannelFile(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      parentId: json['parent_id'],
      isDirectory: json['is_directory'] ?? false,
      type: json['type'] ?? '',
      size: json['size'] ?? 0,
      zone: json['zone'] ?? 'PUBLIC',
      uploader: json['uploader'] ?? '-',
      uploaderId: json['uploader_id'] ?? 0,
      isGlobal: json['is_global'] ?? false,
      content: json['content'],
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

/// 启动项（简化版，与页面字段对应）
class StartupItem {
  final int id;
  final String name;
  final String path;
  final String zone;
  final int? netbarId;
  final bool enabled;
  final String? args;
  final int? delay;
  final bool forceRun;
  final String? workingDir;
  final String? targetOs;
  final String? targetAreas;
  final String? timeRange;
  final String crashAction;
  final bool runAsService;
  final String updatedAt;

  StartupItem({
    required this.id,
    required this.name,
    required this.path,
    required this.zone,
    this.netbarId,
    required this.enabled,
    this.args,
    this.delay,
    required this.forceRun,
    this.workingDir,
    this.targetOs,
    this.targetAreas,
    this.timeRange,
    this.crashAction = 'none',
    required this.runAsService,
    required this.updatedAt,
  });

  factory StartupItem.fromJson(Map<String, dynamic> json) {
    return StartupItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      zone: json['zone'] ?? 'PUBLIC',
      netbarId: json['netbar_id'],
      enabled: json['enabled'] ?? true,
      args: json['args'],
      delay: json['delay'],
      forceRun: json['force_run'] ?? false,
      workingDir: json['working_dir'],
      targetOs: json['target_os'],
      targetAreas: json['target_areas'],
      timeRange: json['time_range'],
      crashAction: json['crash_action'] ?? 'none',
      runAsService: json['run_as_service'] ?? false,
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }
}

/// 通道基本信息
class Channel {
  final int id;
  final String name;
  final String code;
  final String type;
  final int bandwidth;
  final int status;
  final String? description;

  Channel({
    required this.id,
    required this.name,
    required this.code,
    required this.type,
    required this.bandwidth,
    required this.status,
    this.description,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      type: json['type'] ?? '',
      bandwidth: json['bandwidth'] is int
          ? json['bandwidth']
          : int.tryParse(json['bandwidth']?.toString() ?? '') ?? 0,
      status: json['status'] ?? 0,
      description: json['description'],
    );
  }
}
