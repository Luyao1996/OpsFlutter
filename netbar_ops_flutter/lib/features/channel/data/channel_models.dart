/// 物理文件信息
class FileInfo {
  final int id;
  final int size;
  final String? extension;
  final String? path;

  FileInfo({
    required this.id,
    required this.size,
    this.extension,
    this.path,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      id: json['id'] ?? 0,
      size: json['size'] ?? 0,
      extension: json['extension'],
      path: json['path'],
    );
  }
}

/// 上传者信息
class UploaderInfo {
  final int id;
  final String nickname;

  UploaderInfo({required this.id, required this.nickname});

  factory UploaderInfo.fromJson(Map<String, dynamic> json) {
    return UploaderInfo(
      id: json['id'] ?? 0,
      nickname: json['nickname'] ?? '',
    );
  }
}

/// 通道资源（文件/文件夹）- 适配后端GroupFile
class ChannelFile {
  final int id;
  final String name;
  final int? parentId;
  final bool isDirectory; // 后端: is_folder
  final bool isShare;
  final bool isHide;
  final String? fullPath;
  final int? userId;
  final int? groupId;
  final int? fileId;
  final FileInfo? file;
  final UploaderInfo? user;
  final String createdAt;
  final String updatedAt;

  // 兼容旧代码的getter
  String get path => fullPath ?? '';
  String get type => file?.extension ?? '';
  int get size => file?.size ?? 0;
  String get zone => groupId == 0 ? 'HEADQUARTERS' : 'BRANCH';
  String get uploader => user?.nickname ?? '-';
  int get uploaderId => userId ?? 0;
  bool get isGlobal => groupId == 0;
  String? get content => null;

  ChannelFile({
    required this.id,
    required this.name,
    this.parentId,
    required this.isDirectory,
    required this.isShare,
    required this.isHide,
    this.fullPath,
    this.userId,
    this.groupId,
    this.fileId,
    this.file,
    this.user,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChannelFile.fromJson(Map<String, dynamic> json) {
    return ChannelFile(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      parentId: json['parent_id'],
      isDirectory: json['is_folder'] == true || json['is_folder'] == 1 || json['is_directory'] == true,
      isShare: json['is_share'] == true || json['is_share'] == 1,
      isHide: json['is_hide'] == true || json['is_hide'] == 1,
      fullPath: json['full_path'],
      userId: json['user_id'],
      groupId: json['group_id'],
      fileId: json['file_id'],
      file: json['file'] != null ? FileInfo.fromJson(json['file'] as Map<String, dynamic>) : null,
      user: json['user'] != null ? UploaderInfo.fromJson(json['user'] as Map<String, dynamic>) : null,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
    'is_folder': isDirectory,
    'is_share': isShare,
    'is_hide': isHide,
    'full_path': fullPath,
    'user_id': userId,
    'group_id': groupId,
    'file_id': fileId,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

// 说明（T8c-0）：原本位于此处的策略相关模型（MerchantBrief / GroupBrief / IpRange /
// ConfigFile / EnabledState / StartupPeriod / StartupStrategy / StartupItem / LocaleItem /
// TacticItem）已整体搬迁到 lib/features/strategy/data/strategy_models.dart，供 V1/V2 共用。
// 这里不做 export 转发：转发会让"到底该从哪个文件 import"重新变模糊，
// 需要这些模型的文件请直接 import strategy_models.dart。

/// 通道基本信息 - 保留兼容
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
