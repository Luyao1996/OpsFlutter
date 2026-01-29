import 'dart:convert';

/// 图标类型枚举
enum IconType {
  file,   // 打开程序
  dir,    // 打开文件夹
  url,    // 打开网址
  image,  // 打开图片
}

extension IconTypeExtension on IconType {
  String get value {
    switch (this) {
      case IconType.file: return 'file';
      case IconType.dir: return 'dir';
      case IconType.url: return 'url';
      case IconType.image: return 'image';
    }
  }

  int get intValue {
    switch (this) {
      case IconType.file: return 1;
      case IconType.dir: return 2;
      case IconType.url: return 3;
      case IconType.image: return 4;
    }
  }

  String get label {
    switch (this) {
      case IconType.file: return '打开程序';
      case IconType.dir: return '打开文件夹';
      case IconType.url: return '打开网址';
      case IconType.image: return '打开图片';
    }
  }

  static IconType fromString(String? value) {
    if (value == null) return IconType.file;
    switch (value.toLowerCase()) {
      case 'file':
      case 'program':
      case 'exe':
      case 'app':
      case 'launch':
      case '1':
        return IconType.file;
      case 'dir':
      case 'folder':
      case 'directory':
      case '2':
        return IconType.dir;
      case 'url':
      case 'website':
      case 'http':
      case 'https':
      case 'link':
      case '3':
        return IconType.url;
      case 'image':
      case 'img':
      case 'picture':
      case '4':
        return IconType.image;
      default:
        return IconType.file;
    }
  }

  static IconType fromInt(int? value) {
    switch (value) {
      case 1: return IconType.file;
      case 2: return IconType.dir;
      case 3: return IconType.url;
      case 4: return IconType.image;
      default: return IconType.file;
    }
  }
}

/// 图标位置
class IconPosition {
  double x;
  double y;

  IconPosition({this.x = 0, this.y = 0});

  factory IconPosition.fromJson(Map<String, dynamic> json) {
    return IconPosition(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'x': x.round(), 'y': y.round()};

  IconPosition copyWith({double? x, double? y}) {
    return IconPosition(x: x ?? this.x, y: y ?? this.y);
  }
}

/// 关联文件项
class FileItem {
  final String? id;
  final String? url;
  final String? hash;
  final bool isDefault;

  FileItem({this.id, this.url, this.hash, this.isDefault = false});

  factory FileItem.fromJson(Map<String, dynamic> json) {
    final pivot = json['pivot'] as Map<String, dynamic>?;
    return FileItem(
      id: json['id']?.toString(),
      url: json['url']?.toString(),
      hash: json['hash']?.toString(),
      isDefault: (pivot?['is_default'] == 1) || (json['is_default'] == 1),
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (url != null) 'url': url,
    if (hash != null) 'hash': hash,
    'is_default': isDefault ? 1 : 0,
  };
}

/// 图标配置
class DesktopIconConfig {
  IconType type;
  String path;           // 文件路径或URL
  String parameter;      // 启动参数（仅file类型有效）/ 或者是URL（url类型）
  String name;           // 显示名称
  String? iconClass;     // CSS图标类
  String? iconUrl;       // 图标URL
  String? groupFileId;   // 服务器文件组ID
  String? fileId;        // 选中的文件ID
  List<FileItem> files;  // 关联的文件列表
  String? hash;          // 文件hash

  DesktopIconConfig({
    this.type = IconType.file,
    this.path = '',
    this.parameter = '',
    this.name = '',
    this.iconClass,
    this.iconUrl,
    this.groupFileId,
    this.fileId,
    List<FileItem>? files,
    this.hash,
  }) : files = files ?? [];

  factory DesktopIconConfig.fromJson(Map<String, dynamic> json) {
    // 解析类型
    IconType type = IconType.file;
    if (json['type'] != null) {
      if (json['type'] is int) {
        type = IconTypeExtension.fromInt(json['type'] as int);
      } else {
        type = IconTypeExtension.fromString(json['type']?.toString());
      }
    }

    // 解析files列表
    List<FileItem> files = [];
    if (json['files'] is List) {
      files = (json['files'] as List)
          .map((e) => FileItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return DesktopIconConfig(
      type: type,
      path: json['path']?.toString() ?? json['exePath']?.toString() ?? '',
      parameter: json['parameter']?.toString() ?? json['args']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      iconClass: json['iconClass']?.toString(),
      iconUrl: json['iconUrl']?.toString() ?? json['iconPath']?.toString(),
      groupFileId: json['group_file_id']?.toString(),
      fileId: json['file_id']?.toString(),
      files: files,
      hash: json['hash']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'path': path,
    'parameter': parameter,
    'args': parameter, // 兼容字段
    'name': name,
    if (iconClass != null && iconClass!.isNotEmpty) 'iconClass': iconClass,
    if (iconUrl != null && iconUrl!.isNotEmpty) 'iconUrl': iconUrl,
    if (groupFileId != null && groupFileId!.isNotEmpty) 'group_file_id': groupFileId,
    'file_id': fileId != null && fileId!.isNotEmpty ? int.tryParse(fileId!) ?? 0 : 0,
    if (files.isNotEmpty) 'files': files.map((e) => e.toJson()).toList(),
    if (hash != null && hash!.isNotEmpty) 'hash': hash,
  };

  DesktopIconConfig copyWith({
    IconType? type,
    String? path,
    String? parameter,
    String? name,
    String? iconClass,
    String? iconUrl,
    String? groupFileId,
    String? fileId,
    List<FileItem>? files,
    String? hash,
  }) {
    return DesktopIconConfig(
      type: type ?? this.type,
      path: path ?? this.path,
      parameter: parameter ?? this.parameter,
      name: name ?? this.name,
      iconClass: iconClass ?? this.iconClass,
      iconUrl: iconUrl ?? this.iconUrl,
      groupFileId: groupFileId ?? this.groupFileId,
      fileId: fileId ?? this.fileId,
      files: files ?? List.from(this.files),
      hash: hash ?? this.hash,
    );
  }
}

/// 桌面图标
class DesktopIcon {
  String id;
  String label;
  String? iconClass;
  String? iconUrl;
  Map<String, IconPosition> positions;  // 每个分辨率的位置
  DesktopIconConfig config;

  DesktopIcon({
    required this.id,
    required this.label,
    this.iconClass,
    this.iconUrl,
    Map<String, IconPosition>? positions,
    required this.config,
  }) : positions = positions ?? {};

  /// 获取指定分辨率的位置，如果不存在则返回默认位置
  IconPosition getPosition(String resolution) {
    return positions[resolution] ?? IconPosition();
  }

  /// 设置指定分辨率的位置
  void setPosition(String resolution, IconPosition position) {
    positions[resolution] = position;
  }

  /// 更新所有分辨率的位置（同步移动）
  void updateAllPositions(double dx, double dy) {
    for (final key in positions.keys) {
      positions[key]!.x += dx;
      positions[key]!.y += dy;
    }
  }

  factory DesktopIcon.fromJson(Map<String, dynamic> json) {
    // 解析positions
    Map<String, IconPosition> positions = {};
    if (json['positions'] is Map) {
      final posMap = json['positions'] as Map<String, dynamic>;
      posMap.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          positions[key] = IconPosition.fromJson(value);
        }
      });
    }

    // 兼容旧数据：coord 或 x/y
    if (positions.isEmpty) {
      final coord = json['coord'] as Map<String, dynamic>?;
      final x = (coord?['x'] ?? json['x'] as num?)?.toDouble() ?? 0;
      final y = (coord?['y'] ?? json['y'] as num?)?.toDouble() ?? 0;
      // 使用默认分辨率
      positions['1920 x 1080'] = IconPosition(x: x, y: y);
    }

    // 解析config
    DesktopIconConfig config;
    if (json['config'] is Map<String, dynamic>) {
      config = DesktopIconConfig.fromJson(json['config'] as Map<String, dynamic>);
    } else {
      config = DesktopIconConfig.fromJson(json);
    }

    return DesktopIcon(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? json['name']?.toString() ?? '',
      iconClass: json['class']?.toString() ?? json['iconClass']?.toString(),
      iconUrl: json['iconUrl']?.toString(),
      positions: positions,
      config: config,
    );
  }

  Map<String, dynamic> toJson([String? currentResolution]) {
    // 获取当前分辨率的坐标作为 coord
    Map<String, dynamic>? coord;
    if (currentResolution != null && positions.containsKey(currentResolution)) {
      coord = positions[currentResolution]!.toJson();
    } else if (positions.isNotEmpty) {
      coord = positions.values.first.toJson();
    }

    return {
      'id': id,
      'label': label,
      if (iconClass != null && iconClass!.isNotEmpty) 'class': iconClass,
      if (iconUrl != null && iconUrl!.isNotEmpty) 'iconUrl': iconUrl,
      'positions': positions.map((k, v) => MapEntry(k, v.toJson())),
      if (coord != null) 'coord': coord,
      'config': config.toJson(),
    };
  }

  DesktopIcon copyWith({
    String? id,
    String? label,
    String? iconClass,
    String? iconUrl,
    Map<String, IconPosition>? positions,
    DesktopIconConfig? config,
  }) {
    return DesktopIcon(
      id: id ?? this.id,
      label: label ?? this.label,
      iconClass: iconClass ?? this.iconClass,
      iconUrl: iconUrl ?? this.iconUrl,
      positions: positions ?? Map.from(this.positions.map((k, v) => MapEntry(k, v.copyWith()))),
      config: config ?? this.config.copyWith(),
    );
  }
}

/// 背景配置
class BackgroundConfig {
  String url;
  int delay;
  String mode; // center, stretch, tile
  bool locked;

  BackgroundConfig({
    this.url = '',
    this.delay = 10,
    this.mode = 'center',
    this.locked = false,
  });

  factory BackgroundConfig.fromJson(Map<String, dynamic> json) {
    return BackgroundConfig(
      url: json['background_url']?.toString() ?? json['bgImg']?.toString() ?? '',
      mode: json['background_mode']?.toString().toLowerCase() ?? 'center',
      delay: int.tryParse(json['background_delay']?.toString() ?? '10') ?? 10,
      locked: json['lock_icons'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'background_url': url,
    'background_mode': mode,
    'background_delay': delay,
    'lock_icons': locked,
  };

  BackgroundConfig copyWith({
    String? url,
    int? delay,
    String? mode,
    bool? locked,
  }) {
    return BackgroundConfig(
      url: url ?? this.url,
      delay: delay ?? this.delay,
      mode: mode ?? this.mode,
      locked: locked ?? this.locked,
    );
  }
}

/// 桌面布局
class DesktopLayout {
  int? id;
  int? netbarId;      // 后端: merchant_id
  int? groupId;
  int? fileId;        // 背景图片文件ID
  String? fileUrl;    // 背景图片URL
  int? baseLayoutId;
  String name;
  String resolution;  // 格式: "1920 x 1080"
  BackgroundConfig background;
  List<DesktopIcon> icons;
  bool lockIcons;
  bool forceUpdate;

  DesktopLayout({
    this.id,
    this.netbarId,
    this.groupId,
    this.fileId,
    this.fileUrl,
    this.baseLayoutId,
    required this.name,
    required this.resolution,
    required this.background,
    required this.icons,
    this.lockIcons = false,
    this.forceUpdate = false,
  });

  bool get isGlobal => netbarId == null;
  bool get isOverride => netbarId != null && baseLayoutId != null;

  /// 生成配置JSON（后端存储格式）
  Map<String, dynamic> get configurationMap {
    return {
      'detail': icons.map((e) => e.toJson(resolution)).toList(),
    };
  }

  String get configurationJson => jsonEncode(configurationMap);

  factory DesktopLayout.fromJson(Map<String, dynamic> json) {
    // 解析 configuration 字段
    Map<String, dynamic> config = {};
    final configJson = json['configuration'];
    if (configJson is String && configJson.isNotEmpty) {
      try {
        config = jsonDecode(configJson) as Map<String, dynamic>;
      } catch (_) {}
    } else if (configJson is Map<String, dynamic>) {
      config = configJson;
    }

    // 解析图标列表
    List<DesktopIcon> icons = [];
    final detail = config['detail'] ?? config['icons'] ?? json['icons'];
    if (detail is List) {
      icons = detail
          .map((e) => DesktopIcon.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // 背景配置
    final bgUrl = config['background_url']?.toString() ??
        json['background_url']?.toString() ??
        json['file_url']?.toString() ??
        '';
    final bgMode = config['background_mode']?.toString() ??
        json['background_mode']?.toString() ??
        'center';
    final bgDelay = int.tryParse(
        (config['background_delay'] ?? json['background_delay'] ?? '10').toString()) ?? 10;
    final lockIcons = config['lock_icons'] == true || json['lock_icons'] == true;

    return DesktopLayout(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id'] ?? ''}'),
      netbarId: json['merchant_id'] is int
          ? json['merchant_id'] as int
          : int.tryParse('${json['merchant_id'] ?? ''}'),
      groupId: json['group_id'] is int
          ? json['group_id'] as int
          : int.tryParse('${json['group_id'] ?? ''}'),
      fileId: json['file_id'] is int
          ? json['file_id'] as int
          : int.tryParse('${json['file_id'] ?? ''}'),
      // 如果 file_url 不存在但 file_id 存在，根据 file_id 构建 URL
      fileUrl: json['file_url']?.toString() ??
          (json['file_id'] != null ? '/resource/file/${json['file_id']}' : null),
      baseLayoutId: json['base_layout_id'] is int
          ? json['base_layout_id'] as int
          : int.tryParse('${json['base_layout_id'] ?? ''}'),
      name: config['name']?.toString() ?? json['name']?.toString() ?? '',
      resolution: json['resolution']?.toString() ?? '1920 x 1080',
      background: BackgroundConfig(
        url: bgUrl,
        mode: bgMode,
        delay: bgDelay,
        locked: lockIcons,
      ),
      icons: icons,
      lockIcons: lockIcons,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (netbarId != null) 'merchant_id': netbarId,
      if (groupId != null) 'group_id': groupId,
      if (baseLayoutId != null) 'base_layout_id': baseLayoutId,
      'name': name,
      'resolution': resolution,
      'configuration': configurationJson,
      'lock_icons': lockIcons,
    };
  }

  DesktopLayout copyWith({
    int? id,
    int? netbarId,
    int? groupId,
    int? fileId,
    String? fileUrl,
    int? baseLayoutId,
    String? name,
    String? resolution,
    BackgroundConfig? background,
    List<DesktopIcon>? icons,
    bool? lockIcons,
    bool? forceUpdate,
  }) {
    return DesktopLayout(
      id: id ?? this.id,
      netbarId: netbarId ?? this.netbarId,
      groupId: groupId ?? this.groupId,
      fileId: fileId ?? this.fileId,
      fileUrl: fileUrl ?? this.fileUrl,
      baseLayoutId: baseLayoutId ?? this.baseLayoutId,
      name: name ?? this.name,
      resolution: resolution ?? this.resolution,
      background: background ?? this.background.copyWith(),
      icons: icons ?? this.icons.map((e) => e.copyWith()).toList(),
      lockIcons: lockIcons ?? this.lockIcons,
      forceUpdate: forceUpdate ?? this.forceUpdate,
    );
  }
}

/// 分辨率设置
class ResolutionSettings {
  final int width;
  final int height;
  final int columns;
  final int startX;
  final int startY;
  final int gapX;
  final int gapY;

  const ResolutionSettings({
    required this.width,
    required this.height,
    this.columns = 6,
    this.startX = 24,
    this.startY = 24,
    this.gapX = 96,
    this.gapY = 110,
  });

  factory ResolutionSettings.fromResolution(String resolution) {
    final parts = resolution.split(RegExp(r'[x*×]')).map((s) => s.trim()).toList();
    final width = int.tryParse(parts[0]) ?? 1920;
    final height = int.tryParse(parts.length > 1 ? parts[1] : '1080') ?? 1080;
    return ResolutionSettings(
      width: width,
      height: height,
      columns: (width / 120).floor(),
    );
  }

  String get label => '$width x $height';

  IconPosition getDefaultPosition(int index) {
    final col = index % columns;
    final row = index ~/ columns;
    return IconPosition(
      x: (startX + col * gapX).toDouble(),
      y: (startY + row * gapY).toDouble(),
    );
  }
}
