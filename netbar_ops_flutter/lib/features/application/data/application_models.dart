import 'dart:convert';

/// 应用中心 / 应用策略数据模型
/// 字段与解析逻辑对齐 toolboxPage：
///   - AppCenterDialog.vue mapLibApp/mapRefApp（应用卡片）
///   - PolicyConfigDialog.vue policyToParams（策略参数回填）

int _toInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool _toBool(dynamic v) => v == true || v == 1 || v == '1';

/// 后端列表三态解包：paginator.data / list / 直接数组。
/// 对齐 web 端 utils extractList（res.data?.paginator?.data || res.data?.list || res.data）。
/// [preferKeys] 优先取指定键（如 'areas'、'versions'、'applications'）。
List<Map<String, dynamic>> extractList(
  dynamic data, {
  List<String> preferKeys = const [],
}) {
  List<Map<String, dynamic>> cast(dynamic l) =>
      (l as List).whereType<Map<String, dynamic>>().toList();
  if (data is List) return cast(data);
  if (data is Map<String, dynamic>) {
    for (final k in preferKeys) {
      if (data[k] is List) return cast(data[k]);
    }
    final pag = data['paginator'];
    if (pag is Map && pag['data'] is List) return cast(pag['data']);
    if (data['list'] is List) return cast(data['list']);
    if (data['data'] is List) return cast(data['data']);
  }
  return const [];
}

/// 分页总数：paginator.total，取不到回退当前页条数
int extractTotal(dynamic data, int fallback) {
  if (data is Map<String, dynamic>) {
    final pag = data['paginator'];
    if (pag is Map) {
      final t = _toIntOrNull(pag['total']);
      if (t != null) return t;
    }
    final t = _toIntOrNull(data['total']);
    if (t != null) return t;
  }
  return fallback;
}

/// 应用分类（GET /application-category type=1）
class AppCategory {
  final int id;
  final String name;

  const AppCategory({required this.id, required this.name});

  factory AppCategory.fromJson(Map<String, dynamic> json) =>
      AppCategory(id: _toInt(json['id']), name: json['name'] ?? '');
}

/// 应用中心卡片项（应用库应用 / 已添加引用的统一视图）
class AppCenterItem {
  final int applicationId;
  final String name;
  final String desc;
  final String icon; // icon_url，空串=无图标
  final String tag; // 默认版本号，否则分类名
  bool added; // 是否已添加到当前分组
  int? refId; // 引用记录 id（取消添加用）
  bool busy; // 添加/移除请求进行中

  AppCenterItem({
    required this.applicationId,
    required this.name,
    required this.desc,
    required this.icon,
    required this.tag,
    required this.added,
    this.refId,
    this.busy = false,
  });

  /// 应用库应用 → 卡片项（对齐 mapLibApp）。
  /// [addedMap]: applicationId → 引用记录 id（添加接口未返回 id 时为 null），
  /// 用于标记「已添加」。
  factory AppCenterItem.fromLibrary(
    Map<String, dynamic> json,
    Map<int, int?> addedMap,
  ) {
    final id = _toInt(json['id']);
    return AppCenterItem(
      applicationId: id,
      name: json['name'] ?? '',
      desc: json['description'] ?? '',
      icon: json['icon_url'] ?? '',
      tag: _defaultVersionTag(json),
      added: addedMap.containsKey(id),
      refId: addedMap[id],
    );
  }

  /// 引用记录（嵌套 application）→ 卡片项（对齐 mapRefApp）
  factory AppCenterItem.fromReference(Map<String, dynamic> json) {
    final app = json['application'] is Map<String, dynamic>
        ? json['application'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AppCenterItem(
      applicationId: _toIntOrNull(json['application_id']) ?? _toInt(app['id']),
      name: app['name'] ?? '',
      desc: app['description'] ?? '',
      icon: app['icon_url'] ?? '',
      tag: _defaultVersionTag(app),
      added: true,
      refId: _toIntOrNull(json['id']),
    );
  }

  /// 标签：默认版本号 → 第一个版本号 → 分类名（对齐 web defVer 逻辑）
  static String _defaultVersionTag(Map<String, dynamic> app) {
    final versions = app['versions'];
    if (versions is List && versions.isNotEmpty) {
      final def = versions.firstWhere(
        (v) => v is Map && _toBool(v['is_default']),
        orElse: () => versions.first,
      );
      if (def is Map && def['version'] != null) return '${def['version']}';
    }
    final cat = app['category'];
    if (cat is Map && cat['name'] != null) return '${cat['name']}';
    return '';
  }
}

/// 应用版本（GET /application/{id}/versions）
class AppVersion {
  final int id;
  final String version;

  const AppVersion({required this.id, required this.version});

  factory AppVersion.fromJson(Map<String, dynamic> json) =>
      AppVersion(id: _toInt(json['id']), version: '${json['version'] ?? ''}');
}

/// 策略生效机号区域（GET /application-policy/areas 列表项）
class PolicyArea {
  final int id;
  final String key; // area_key，缺省退回 id 字符串
  final int? policyId;
  final List<String> area; // 机号段数组，如 ['001-025', '033-257']
  final String label;

  const PolicyArea({
    required this.id,
    required this.key,
    this.policyId,
    required this.area,
    required this.label,
  });

  factory PolicyArea.fromJson(Map<String, dynamic> json) {
    final rawArea = json['area'];
    final area = rawArea is List
        ? rawArea.map((e) => '$e').toList()
        : (rawArea != null && '$rawArea'.isNotEmpty ? ['$rawArea'] : <String>[]);
    return PolicyArea(
      id: _toInt(json['id']),
      key: '${json['area_key'] ?? json['id']}',
      policyId: _toIntOrNull(json['policy_id']),
      area: area,
      label: (json['label'] as String?)?.isNotEmpty == true
          ? json['label'] as String
          : area.join('，'),
    );
  }
}

/// 生效时段（HH:mm:ss）
class PolicyPeriod {
  final String start;
  final String end;

  const PolicyPeriod({required this.start, required this.end});
}

/// 策略参数（右侧表单，对应一条 application-policy 的可编辑字段）
class PolicyParams {
  int? versionId; // application_version_id，必选
  String parameter; // 执行参数
  int delay; // 延迟启动（秒）
  bool isRandomName;
  bool isForcedOn;
  List<PolicyPeriod> period; // 空 = 全天
  int strategyMode; // 0 = 直接启动
  List<String> systems; // win7 / win10 / win11
  String server; // 服务端终端 id（字符串，空=未选）

  PolicyParams({
    this.versionId,
    this.parameter = '',
    this.delay = 0,
    this.isRandomName = false,
    this.isForcedOn = false,
    List<PolicyPeriod>? period,
    this.strategyMode = 0,
    List<String>? systems,
    this.server = '',
  })  : period = period ?? [],
        systems = systems ?? [];

  /// 策略对象（详情 / by-area 同结构）→ 表单参数。
  /// 对齐 PolicyConfigDialog.vue policyToParams：
  ///   - feature_config 可能是 JSON 字符串
  ///   - period 兼容数组 / 单对象两种形态
  factory PolicyParams.fromPolicyJson(Map<String, dynamic> p) {
    dynamic fc = p['feature_config'];
    if (fc is String) {
      try {
        fc = jsonDecode(fc);
      } catch (_) {
        fc = const <String, dynamic>{};
      }
    }
    final fcMap = fc is Map<String, dynamic> ? fc : const <String, dynamic>{};

    final periods = <PolicyPeriod>[];
    final rawPeriod = p['period'];
    if (rawPeriod is List) {
      for (final x in rawPeriod) {
        if (x is Map && x['start'] != null && x['end'] != null) {
          periods.add(PolicyPeriod(start: '${x['start']}', end: '${x['end']}'));
        }
      }
    } else if (rawPeriod is Map && rawPeriod['start'] != null) {
      periods.add(PolicyPeriod(
        start: '${rawPeriod['start']}',
        end: '${rawPeriod['end'] ?? ''}',
      ));
    }

    final rawSystems = fcMap['systems'] ?? fcMap['system'];
    final systems = rawSystems is List
        ? rawSystems.map((e) => '$e').toList()
        : <String>[];

    final strategy = p['strategy'];
    final strategyMode =
        strategy is Map ? _toInt(strategy['mode']) : 0;

    return PolicyParams(
      versionId: _toIntOrNull(p['application_version_id']),
      parameter: '${p['parameter'] ?? ''}',
      delay: _toInt(p['delay']),
      isRandomName: _toBool(p['is_random_name']),
      isForcedOn: _toBool(p['is_forced_on']),
      period: periods,
      strategyMode: strategyMode,
      systems: systems,
      server: '${fcMap['server'] ?? ''}',
    );
  }
}

/// 策略保存请求（新建/更新共用，转 multipart 由 api 层负责）
class PolicyPayload {
  final int? groupId;
  final int applicationId;
  final int versionId;
  final String parameter;
  final int strategyMode;
  final List<PolicyPeriod> period;
  final int delay;
  final bool isRandomName;
  final bool isForcedOn;
  final List<String> systems;
  final String server;
  final List<int> merchantIds;
  final int? areaId; // 单网吧时传选中区域 id

  const PolicyPayload({
    required this.groupId,
    required this.applicationId,
    required this.versionId,
    required this.parameter,
    required this.strategyMode,
    required this.period,
    required this.delay,
    required this.isRandomName,
    required this.isForcedOn,
    required this.systems,
    required this.server,
    required this.merchantIds,
    this.areaId,
  });
}

/// 策略「服务端」选择项（GET /terminals?mode=1,2 原始 JSON 的轻量视图）。
/// 名称/IP 取值对齐 PolicyConfigDialog.vue:163-166。
class ServerTerminal {
  final int id;
  final String name;
  final String ip;
  final int mode; // 1=主服务器 2=副主机

  const ServerTerminal({
    required this.id,
    required this.name,
    required this.ip,
    required this.mode,
  });

  factory ServerTerminal.fromJson(Map<String, dynamic> json) {
    final mode = _toInt(json['mode'], 1);
    final rawName = '${json['name'] ?? ''}';
    return ServerTerminal(
      id: _toInt(json['id']),
      name: rawName.isNotEmpty ? rawName : (mode == 2 ? '副主机' : '主服务器'),
      ip: '${json['ip'] ?? json['host'] ?? json['terminal_ip'] ?? ''}',
      mode: mode,
    );
  }
}
