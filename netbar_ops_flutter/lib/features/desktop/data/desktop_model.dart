import 'dart:convert';

class DesktopIconConfig {
  final String exePath;
  final String name;
  final String args;
  final String workDir;
  final String? iconPath;

  DesktopIconConfig({
    required this.exePath,
    required this.name,
    this.args = '',
    this.workDir = '',
    this.iconPath,
  });

  factory DesktopIconConfig.fromJson(Map<String, dynamic> json) {
    return DesktopIconConfig(
      exePath: json['exePath']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      args: json['args']?.toString() ?? '',
      workDir: json['workDir']?.toString() ?? '',
      iconPath: json['iconPath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'exePath': exePath,
        'name': name,
        if (args.isNotEmpty) 'args': args,
        if (workDir.isNotEmpty) 'workDir': workDir,
        if (iconPath != null && iconPath!.isNotEmpty) 'iconPath': iconPath,
      };
}

class DesktopIcon {
  final String id;
  final String name;
  final DesktopIconConfig config;
  double x;
  double y;

  DesktopIcon({
    required this.id,
    required this.name,
    required this.config,
    required this.x,
    required this.y,
  });

  factory DesktopIcon.fromJson(Map<String, dynamic> json) {
    return DesktopIcon(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      config: DesktopIconConfig.fromJson(json),
      x: double.tryParse(json['x']?.toString() ?? '0') ?? 0,
      y: double.tryParse(json['y']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        ...config.toJson(),
        'x': x.round(),
        'y': y.round(),
      };
}

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

  factory BackgroundConfig.fromLayout(Map<String, dynamic> json) {
    return BackgroundConfig(
      url: json['background_url']?.toString() ?? '',
      mode: json['background_mode']?.toString().toLowerCase() ?? 'center',
      delay: int.tryParse(json['background_delay']?.toString() ?? '10') ?? 10,
      locked: json['lock_icons'] == true,
    );
  }
}

class DesktopLayout {
  int? id;
  int? netbarId;
  int? baseLayoutId;
  String name;
  String resolution;
  BackgroundConfig background;
  List<DesktopIcon> icons;
  bool lockIcons;

  DesktopLayout({
    this.id,
    this.netbarId,
    this.baseLayoutId,
    required this.name,
    required this.resolution,
    required this.background,
    required this.icons,
    this.lockIcons = false,
  });

  bool get isGlobal => netbarId == null;
  bool get isOverride => netbarId != null && baseLayoutId != null;

  factory DesktopLayout.fromJson(Map<String, dynamic> json) {
    final iconsJson = json['icons'];
    List<dynamic> iconList = [];
    if (iconsJson is List) {
      iconList = iconsJson;
    } else if (iconsJson is String) {
      // icons stored as JSON string
      try {
        iconList = List.from((iconsJson.isNotEmpty ? jsonDecode(iconsJson) : []) as List);
      } catch (_) {
        iconList = [];
      }
    }
    return DesktopLayout(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id'] ?? ''}'),
      netbarId: json['netbar_id'] is int
          ? json['netbar_id'] as int
          : int.tryParse('${json['netbar_id'] ?? ''}'),
      baseLayoutId: json['base_layout_id'] is int
          ? json['base_layout_id'] as int
          : int.tryParse('${json['base_layout_id'] ?? ''}'),
      name: json['name']?.toString() ?? '',
      resolution: json['resolution']?.toString() ?? '1920*1080',
      background: BackgroundConfig.fromLayout(json),
      icons: iconList.map((e) => DesktopIcon.fromJson(e as Map<String, dynamic>)).toList(),
      lockIcons: json['lock_icons'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (netbarId != null) 'netbar_id': netbarId,
      if (baseLayoutId != null) 'base_layout_id': baseLayoutId,
      'name': name,
      'resolution': resolution,
      'background_url': background.url,
      'background_mode': background.mode,
      'background_delay': background.delay,
      'lock_icons': lockIcons,
      'icons': icons.map((e) => e.toJson()).toList(),
    };
  }
}
