import 'dart:convert';
import '../../../core/network/api_client.dart';
import 'startup_monitor_models.dart';

/// IP范围模型（与 Web IpRange 对应）
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

/// 释放文件模型（与 Web ConfigFile 对应）
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

/// 启用状态模型（与 Web EnabledState 对应）
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

/// 启动项模型（与 Web StartupConfig 对应）
class StartupItem {
  final int id;
  final int? resourceId;
  final int? netbarId;
  final String name;
  final String? displayName; // 启动项显示名称
  final String path;
  final String zone;
  final bool enabled;
  final String? args;
  final int delay;
  final bool forceRun;
  final String? workingDir;
  final String? targetOs;
  final String? targetAreas;
  final String? targetIpRanges; // JSON string of IpRange[]
  final String? timeRange;
  final String crashAction;
  final bool runAsService;
  final bool randomProcessName;
  final String? releaseFiles; // JSON string of ConfigFile[]
  final String? disableDuration; // 'permanent' | number (days as string)
  final String? disableStrategy;
  final String? disabledAreas;
  final String? disabledIpRanges;
  final DateTime createdAt;
  final DateTime updatedAt;

  StartupItem({
    required this.id,
    this.resourceId,
    this.netbarId,
    required this.name,
    this.displayName,
    required this.path,
    required this.zone,
    required this.enabled,
    this.args,
    required this.delay,
    required this.forceRun,
    this.workingDir,
    this.targetOs,
    this.targetAreas,
    this.targetIpRanges,
    this.timeRange,
    required this.crashAction,
    required this.runAsService,
    this.randomProcessName = false,
    this.releaseFiles,
    this.disableDuration,
    this.disableStrategy,
    this.disabledAreas,
    this.disabledIpRanges,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 获取显示名称（优先使用 displayName，没有则使用 name）
  String get effectiveDisplayName => displayName?.isNotEmpty == true ? displayName! : name;

  factory StartupItem.fromJson(Map<String, dynamic> json) {
    return StartupItem(
      id: json['id'] ?? 0,
      resourceId: json['resource_id'],
      netbarId: json['netbar_id'],
      name: json['name'] ?? '',
      displayName: json['display_name'],
      path: json['path'] ?? '',
      zone: json['zone'] ?? 'HEADQUARTERS',
      enabled: json['enabled'] ?? true,
      args: json['args'],
      delay: json['delay'] ?? 0,
      forceRun: json['force_run'] ?? false,
      workingDir: json['working_dir'],
      targetOs: json['target_os'],
      targetAreas: json['target_areas'],
      targetIpRanges: json['target_ip_ranges'],
      timeRange: json['time_range'],
      crashAction: json['crash_action'] ?? 'none',
      runAsService: json['run_as_service'] ?? false,
      randomProcessName: json['random_process_name'] ?? false,
      releaseFiles: json['release_files'],
      disableDuration: json['disable_duration'],
      disableStrategy: json['disable_strategy'],
      disabledAreas: json['disabled_areas'],
      disabledIpRanges: json['disabled_ip_ranges'],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// 格式化更新时间
  String get formattedUpdateTime {
    return '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')} '
        '${updatedAt.hour.toString().padLeft(2, '0')}:${updatedAt.minute.toString().padLeft(2, '0')}';
  }

  /// 获取目标操作系统列表
  List<String> get targetOsList => targetOs?.split(',').where((s) => s.isNotEmpty).toList() ?? [];

  /// 获取目标区域列表
  List<String> get targetAreasList => targetAreas?.split(',').where((s) => s.isNotEmpty).toList() ?? [];

  /// 获取目标IP范围列表
  List<IpRange> get targetIpRangesList {
    if (targetIpRanges == null || targetIpRanges!.isEmpty) return [];
    try {
      final list = jsonDecode(targetIpRanges!) as List;
      return list.map((e) => IpRange.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取释放文件列表
  List<ConfigFile> get releaseFilesList {
    if (releaseFiles == null || releaseFiles!.isEmpty) return [];
    try {
      final list = jsonDecode(releaseFiles!) as List;
      return list.map((e) => ConfigFile.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 获取禁用状态（与 Web EnabledState 对应）
  EnabledState get enabledState {
    // 解析 duration: 'permanent' 或 数字天数
    dynamic duration;
    if (disableDuration != null && disableDuration!.isNotEmpty) {
      if (disableDuration == 'permanent') {
        duration = 'permanent';
      } else {
        duration = int.tryParse(disableDuration!) ?? disableDuration;
      }
    }

    return EnabledState(
      status: enabled,
      duration: duration,
      strategy: disableStrategy ?? 'global',
      disabledAreas: disabledAreas?.split(',').where((s) => s.isNotEmpty).toList(),
      disabledIpRanges: disabledIpRanges != null && disabledIpRanges!.isNotEmpty
          ? (() {
              try {
                final list = jsonDecode(disabledIpRanges!) as List;
                return list.map((e) => IpRange.fromJson(e)).toList();
              } catch (_) {
                return <IpRange>[];
              }
            })()
          : null,
    );
  }
}

/// 启动项 API
class StartupItemApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取启动项列表
  Future<List<StartupItem>> getAll({
    String? zone,
    bool? enabled,
    String? search,
    int? netbarId,
  }) async {
    final params = <String, dynamic>{};
    if (zone != null) params['zone'] = zone;
    if (enabled != null) params['enabled'] = enabled.toString();
    if (search != null) params['search'] = search;
    if (netbarId != null) params['netbar_id'] = netbarId.toString();

    final response = await _client.get('/startup-items', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => StartupItem.fromJson(e)).toList();
  }

  /// 获取单个启动项
  Future<StartupItem> getById(int id) async {
    final response = await _client.get('/startup-items/$id');
    return StartupItem.fromJson(response.data);
  }

  /// 创建启动项
  Future<StartupItem> create({
    int? resourceId,
    int? netbarId,
    required String name,
    String? displayName,
    required String path,
    String zone = 'HEADQUARTERS',
    bool enabled = true,
    String? args,
    int delay = 0,
    bool forceRun = false,
    String? workingDir,
    String? targetOs,
    String? targetAreas,
    List<Map<String, dynamic>>? targetIpRanges,
    String? timeRange,
    String crashAction = 'none',
    bool runAsService = false,
    bool randomProcessName = false,
    List<Map<String, dynamic>>? releaseFiles,
  }) async {
    final response = await _client.post('/startup-items', data: {
      'resource_id': resourceId,
      'netbar_id': netbarId,
      'name': name,
      'display_name': displayName,
      'path': path,
      'zone': zone,
      'enabled': enabled,
      'args': args,
      'delay': delay,
      'force_run': forceRun,
      'working_dir': workingDir,
      'target_os': targetOs,
      'target_areas': targetAreas,
      if (targetIpRanges != null) 'target_ip_ranges': jsonEncode(targetIpRanges),
      'time_range': timeRange,
      'crash_action': crashAction,
      'run_as_service': runAsService,
      'random_process_name': randomProcessName,
      if (releaseFiles != null) 'release_files': jsonEncode(releaseFiles),
    });
    return StartupItem.fromJson(response.data);
  }

  /// 更新启动项（全量更新，所有字段都发送）
  Future<StartupItem> updateFull(int id, {
    required String name,
    String? displayName,
    required String path,
    required bool enabled,
    required String args,
    required int delay,
    required bool forceRun,
    required String workingDir,
    required String targetOs,
    required String targetAreas,
    required List<Map<String, dynamic>> targetIpRanges,
    required String crashAction,
    required bool runAsService,
    required bool randomProcessName,
    required List<Map<String, dynamic>> releaseFiles,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      'display_name': displayName,
      'path': path,
      'enabled': enabled,
      'args': args,
      'delay': delay,
      'force_run': forceRun,
      'working_dir': workingDir,
      'target_os': targetOs,
      'target_areas': targetAreas,
      'target_ip_ranges': jsonEncode(targetIpRanges),
      'crash_action': crashAction,
      'run_as_service': runAsService,
      'random_process_name': randomProcessName,
      'release_files': jsonEncode(releaseFiles),
    };

    final response = await _client.put('/startup-items/$id', data: data);
    return StartupItem.fromJson(response.data);
  }

  /// 更新启动项（部分更新，只发送非null字段）
  Future<StartupItem> update(int id, {
    String? name,
    String? path,
    bool? enabled,
    String? args,
    int? delay,
    bool? forceRun,
    String? workingDir,
    String? targetOs,
    String? targetAreas,
    List<Map<String, dynamic>>? targetIpRanges,
    String? timeRange,
    String? crashAction,
    bool? runAsService,
    bool? randomProcessName,
    List<Map<String, dynamic>>? releaseFiles,
    // 禁用状态相关字段
    String? disableDuration,
    String? disableStrategy,
    String? disabledAreas,
    List<Map<String, dynamic>>? disabledIpRanges,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (path != null) data['path'] = path;
    if (enabled != null) data['enabled'] = enabled;
    if (args != null) data['args'] = args;
    if (delay != null) data['delay'] = delay;
    if (forceRun != null) data['force_run'] = forceRun;
    if (workingDir != null) data['working_dir'] = workingDir;
    if (targetOs != null) data['target_os'] = targetOs;
    if (targetAreas != null) data['target_areas'] = targetAreas;
    if (targetIpRanges != null) data['target_ip_ranges'] = jsonEncode(targetIpRanges);
    if (timeRange != null) data['time_range'] = timeRange;
    if (crashAction != null) data['crash_action'] = crashAction;
    if (runAsService != null) data['run_as_service'] = runAsService;
    if (randomProcessName != null) data['random_process_name'] = randomProcessName;
    if (releaseFiles != null) data['release_files'] = jsonEncode(releaseFiles);
    // 禁用状态
    if (disableDuration != null) data['disable_duration'] = disableDuration;
    if (disableStrategy != null) data['disable_strategy'] = disableStrategy;
    if (disabledAreas != null) data['disabled_areas'] = disabledAreas;
    if (disabledIpRanges != null) data['disabled_ip_ranges'] = jsonEncode(disabledIpRanges);

    final response = await _client.put('/startup-items/$id', data: data);
    return StartupItem.fromJson(response.data);
  }

  /// 禁用启动项（使用 EnabledState）
  Future<StartupItem> disable(int id, EnabledState state) async {
    // 将 duration 转换为字符串
    String? durationStr;
    if (state.duration != null) {
      durationStr = state.duration == 'permanent' ? 'permanent' : state.duration.toString();
    }

    return update(
      id,
      enabled: false,
      disableDuration: durationStr,
      disableStrategy: state.strategy,
      disabledAreas: state.disabledAreas?.join(','),
      disabledIpRanges: state.disabledIpRanges?.map((e) => e.toJson()).toList(),
    );
  }

  /// 启用启动项
  Future<StartupItem> enable(int id) async {
    return update(
      id,
      enabled: true,
      disableStrategy: null,
      disabledAreas: null,
    );
  }

  /// 删除启动项
  Future<void> delete(int id) async {
    await _client.delete('/startup-items/$id');
  }
}

/// 启动项监控 API（用于通道监控页）
class StartupItemMonitorApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<NetbarMonitorData>> getMonitor({int? netbarId}) async {
    final params = <String, dynamic>{};
    if (netbarId != null) params['netbar_id'] = netbarId;

    final response = await _client.get('/startup-items/monitor', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => NetbarMonitorData.fromJson(e as Map<String, dynamic>)).toList();
  }
}
