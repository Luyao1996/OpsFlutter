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

/// 商户简要信息（启动项关联）
class MerchantBrief {
  final int id;
  final String name;
  final int terminalCount;
  final List<GroupBrief>? groups;

  MerchantBrief({
    required this.id,
    required this.name,
    required this.terminalCount,
    this.groups,
  });

  factory MerchantBrief.fromJson(Map<String, dynamic> json) {
    return MerchantBrief(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      terminalCount: json['terminal_count'] ?? 0,
      groups: (json['groups'] as List?)?.map((e) => GroupBrief.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

/// 分组简要信息
class GroupBrief {
  final int id;
  final String name;

  GroupBrief({required this.id, required this.name});

  factory GroupBrief.fromJson(Map<String, dynamic> json) {
    return GroupBrief(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }
}

/// IP范围模型
class IpRange {
  final String start;
  final String end;

  IpRange({required this.start, required this.end});

  factory IpRange.fromJson(Map<String, dynamic> json) {
    return IpRange(
      start: json['start'] ?? '',
      end: json['end'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

/// 释放文件模型
class ConfigFile {
  final String path;
  final String? content;

  ConfigFile({required this.path, this.content});

  factory ConfigFile.fromJson(Map<String, dynamic> json) {
    return ConfigFile(
      path: json['path'] ?? '',
      content: json['content'],
    );
  }

  Map<String, dynamic> toJson() => {'path': path, 'content': content};
}

/// 启用状态模型
class EnabledState {
  final bool status;
  final dynamic duration; // 'permanent' | number (days)
  final String strategy; // 'global' | 'specific'
  final List<String>? disabledAreas;
  final List<IpRange>? disabledIpRanges;

  EnabledState({
    required this.status,
    this.duration,
    this.strategy = 'global',
    this.disabledAreas,
    this.disabledIpRanges,
  });

  factory EnabledState.fromJson(Map<String, dynamic> json) {
    return EnabledState(
      status: json['status'] ?? true,
      duration: json['duration'],
      strategy: json['strategy'] ?? 'global',
      disabledAreas: json['disabled_areas'] != null
          ? List<String>.from(json['disabled_areas'])
          : null,
      disabledIpRanges: json['disabled_ip_ranges'] != null
          ? (json['disabled_ip_ranges'] as List).map((e) => IpRange.fromJson(e)).toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'duration': duration,
    'strategy': strategy,
    if (disabledAreas != null) 'disabled_areas': disabledAreas,
    if (disabledIpRanges != null) 'disabled_ip_ranges': disabledIpRanges?.map((e) => e.toJson()).toList(),
  };

  bool get isPermanent => duration == 'permanent';
  int? get durationDays => duration is int ? duration : null;
}

/// 启动项生效时段
class StartupPeriod {
  final String start; // HH:mm:ss
  final String end;   // HH:mm:ss

  StartupPeriod({required this.start, required this.end});

  factory StartupPeriod.fromJson(Map<String, dynamic> json) {
    return StartupPeriod(
      start: json['start']?.toString() ?? '',
      end: json['end']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

/// 启动项执行策略
class StartupStrategy {
  final String mode; // '0': 不限制, '1': 检测到进程存在时启动, '2': 检测到进程不存在时启动
  final String name; // 策略名称/进程名

  StartupStrategy({this.mode = '0', this.name = ''});

  factory StartupStrategy.fromJson(Map<String, dynamic> json) {
    return StartupStrategy(
      mode: json['mode']?.toString() ?? '0',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'mode': mode, 'name': name};
}

/// 启动项 - 适配后端Startup
class StartupItem {
  final int id;
  final int? groupFileId;
  final int? merchantId;
  final int? creatorGroupId;
  final String? enabledAt;
  final String? disabledAt;
  final MerchantBrief? merchant;
  final String createdAt;
  final String updatedAt;

  // 启动配置字段
  final String? startupPath;
  final String? parameter;
  final int? startupDelay;
  final bool isRandomName;
  final bool isForcedOn;
  final List<StartupPeriod> period;
  final StartupStrategy strategy;

  // 兼容旧代码的getter
  String get name => merchant?.name ?? '未知';
  String? get displayName => null;
  String get effectiveDisplayName => displayName ?? name;
  String get path => startupPath ?? '';
  String get zone => 'BRANCH';
  int? get netbarId => merchantId;
  bool get enabled => disabledAt == null;
  String? get args => parameter;
  int? get delay => startupDelay;
  bool get forceRun => isForcedOn;
  String? get workingDir => null;
  String? get targetOs => null;
  String? get targetAreas => null;
  String? get timeRange => null;
  String get crashAction => 'none';
  bool get runAsService => false;
  bool get randomProcessName => isRandomName;

  EnabledState get enabledState => EnabledState(status: enabled);
  List<String> get targetOsList =>
      (targetOs != null && targetOs!.isNotEmpty) ? targetOs!.split(',') : [];
  List<String> get targetAreasList =>
      (targetAreas != null && targetAreas!.isNotEmpty) ? targetAreas!.split(',') : [];
  List<IpRange> get targetIpRangesList => [];
  List<ConfigFile> get releaseFilesList => [];

  StartupItem({
    required this.id,
    this.groupFileId,
    this.merchantId,
    this.creatorGroupId,
    this.enabledAt,
    this.disabledAt,
    this.merchant,
    required this.createdAt,
    required this.updatedAt,
    this.startupPath,
    this.parameter,
    this.startupDelay,
    this.isRandomName = false,
    this.isForcedOn = false,
    this.period = const [],
    StartupStrategy? strategy,
  }) : strategy = strategy ?? StartupStrategy();

  factory StartupItem.fromJson(Map<String, dynamic> json) {
    return StartupItem(
      id: json['id'] ?? 0,
      groupFileId: json['group_file_id'],
      merchantId: json['merchant_id'],
      creatorGroupId: json['creator_group_id'],
      enabledAt: json['enabled_at'],
      disabledAt: json['disabled_at'],
      merchant: json['merchant'] != null ? MerchantBrief.fromJson(json['merchant'] as Map<String, dynamic>) : null,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      startupPath: json['path'],
      parameter: json['parameter'],
      startupDelay: json['delay'] is int ? json['delay'] : int.tryParse(json['delay']?.toString() ?? ''),
      isRandomName: json['is_random_name'] == true || json['is_random_name'] == 1,
      isForcedOn: json['is_forced_on'] == true || json['is_forced_on'] == 1,
      period: (json['period'] as List?)?.map((e) => StartupPeriod.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      strategy: json['strategy'] != null ? StartupStrategy.fromJson(json['strategy'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_file_id': groupFileId,
    'merchant_id': merchantId,
    'creator_group_id': creatorGroupId,
    'enabled_at': enabledAt,
    'disabled_at': disabledAt,
    'path': startupPath,
    'parameter': parameter,
    'delay': startupDelay,
    'is_random_name': isRandomName,
    'is_forced_on': isForcedOn,
    'period': period.map((e) => e.toJson()).toList(),
    'strategy': strategy.toJson(),
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

/// 本地化文件项
class LocaleItem {
  final int? id;
  final int? groupFileId;
  final int? fileId;
  final String path;
  final String? content;
  final String? hash;
  final int? size;
  final bool isDisable;

  LocaleItem({
    this.id,
    this.groupFileId,
    this.fileId,
    required this.path,
    this.content,
    this.hash,
    this.size,
    this.isDisable = false,
  });

  factory LocaleItem.fromJson(Map<String, dynamic> json) {
    return LocaleItem(
      id: json['id'],
      groupFileId: json['group_file_id'],
      fileId: json['file_id'],
      path: json['path']?.toString() ?? '',
      content: json['content']?.toString(),
      hash: json['hash']?.toString(),
      size: json['size'] is int ? json['size'] : int.tryParse(json['size']?.toString() ?? ''),
      isDisable: json['is_disable'] == true || json['is_disable'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (groupFileId != null) 'group_file_id': groupFileId,
    if (fileId != null) 'file_id': fileId,
    'path': path,
    if (content != null) 'content': content,
  };
}

/// 策略项 - 适配后端 Tactic（包装 startup + locales + area + merchant）
class TacticItem {
  final int id;
  final int? groupId;
  final int? creatorGroupId;
  final MerchantBrief? merchant;
  final StartupItem? startup;
  final List<LocaleItem> locales;
  final List<String> area;
  final String createdAt;
  final String updatedAt;

  // 便捷 getter - 从嵌套的 startup 中取值
  String get name => merchant?.name ?? '未知';
  String get effectiveDisplayName => startup?.startupPath ?? name;
  String get path => startup?.startupPath ?? '';
  bool get enabled => startup?.enabled ?? true;
  int? get startupId => startup?.id;
  int? get merchantId => merchant?.id;
  EnabledState get enabledState => startup?.enabledState ?? EnabledState(status: true);

  TacticItem({
    required this.id,
    this.groupId,
    this.creatorGroupId,
    this.merchant,
    this.startup,
    this.locales = const [],
    this.area = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory TacticItem.fromJson(Map<String, dynamic> json) {
    return TacticItem(
      id: json['id'] ?? 0,
      groupId: json['group_id'],
      creatorGroupId: json['creator_group_id'],
      merchant: json['merchant'] != null
          ? MerchantBrief.fromJson(json['merchant'] as Map<String, dynamic>)
          : null,
      startup: json['startup'] != null
          ? StartupItem.fromJson(json['startup'] as Map<String, dynamic>)
          : null,
      locales: (json['locales'] as List?)
              ?.map((e) => LocaleItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      area: (json['area'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          [],
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_id': groupId,
    'creator_group_id': creatorGroupId,
    if (startup != null) 'startup': startup!.toJson(),
    'locales': locales.map((e) => e.toJson()).toList(),
    'area': area,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

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
