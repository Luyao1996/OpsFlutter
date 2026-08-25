// 策略（Tactic）数据模型 —— T8c-0 从 features/channel/data/channel_models.dart 整体搬迁而来，
// 供 V1（通道管理页 / 资源管理页）与 V2（通道管理V2）共用。搬迁时逻辑一字未改，
// 只在文末标注的位置做了 T8c-0 明确列出的扩展（TacticItem.merchants / group / isPlaceholder）。
// GroupBrief 一并搬来：它在 channel_models.dart 里的唯一使用者就是 MerchantBrief。
// 注意：features/netbar/data/netbar_api.dart 另有一个同名 GroupBrief（结构相同但类型不同），
// 两者互不通用，跨模块传递时不要直接互相赋值。

/// 策略形态（T8c-2 新增）。
///
/// 对齐 web StrategyAddDialog.vue:286 `variant: 'netbar' | 'public'`：
///   - [private] 网吧私有策略 → /tactic，**有**生效区域，merchants 为嵌套键形
///   - [public]  程序公共策略 → /public-tactic，**无**生效区域（web hasArea=false，
///               StrategyAddDialog.vue:292），merchants 为扁平键形且编辑先发
///               delete_merchants[]
///
/// 【V1 隔离约定】共享层的两个表单弹窗都以 `variant = StrategyVariant.private`
/// 为默认值：V1 两个旧页面（通道管理页 / 资源管理页）不传该参数，走的仍是
/// 改动前的全部代码路径，行为一字未变。新增差异只允许写成
/// `if (variant == StrategyVariant.public) { ... }` 的**附加**分支，
/// 禁止改动 private 默认路径上的既有逻辑。
enum StrategyVariant {
  /// 网吧私有策略（V1 唯一形态）
  private,

  /// 程序公共策略
  public,
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
///
/// T8c-0：mode 是三值，解析/序列化两端都必须原样保留，**任何地方都不许把 '2' 降级成 '0'**。
/// web StrategyAddDialog.vue:1172-1180 的回填是 `mode !== '1'` 就一律置成 always(0)，
/// 于是"编辑一条 mode=2 的策略"会静默把它改写成 mode=0 —— 这是数据破坏级 bug，不复刻。
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
  final String? disableIn; // 禁用到期时间（临时禁用时有值，格式为 ISO8601 时间字符串）
  final bool isDisable; // 是否禁用（后端 is_disable 字段）
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
  bool get enabled => !isDisable; // 使用 is_disable 判断启用状态
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
    this.disableIn,
    this.isDisable = false,
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
      disableIn: json['disable_in'],
      isDisable: json['is_disable'] == true || json['is_disable'] == 1,
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
    'disable_in': disableIn,
    'is_disable': isDisable,
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

  // ===== T8c-0 新增 =====
  /// 公共策略（/public-tactic）的生效网吧列表。
  /// 私有策略（/tactic）没有这个字段，恒为空列表。
  final List<MerchantBrief> merchants;

  /// 公共策略所属分组（后端 group 字段）。私有策略为 null。
  final GroupBrief? group;

  /// 占位行标记：私有策略列表里"该网吧一条策略都没有"时产出的空行
  /// （对齐 web NetbarStrategyDialog.vue:355-363，后端 tactic id 为 null）。
  /// 占位行没有真实策略，UI 必须据此禁掉删除/编辑/启禁用等按钮——
  /// web 在这里有 `DELETE /tactic/null` 的 bug，我们不复刻。
  final bool isPlaceholder;

  // 便捷 getter - 从嵌套的 startup 中取值
  String get name => merchant?.name ?? '未知';
  /// 从路径中提取程序名作为显示名
  String get effectiveDisplayName {
    final p = startup?.startupPath ?? '';
    if (p.isEmpty) return name;
    // 处理 Windows 和 Unix 风格路径
    final lastSlash = p.lastIndexOf('\\');
    final lastForwardSlash = p.lastIndexOf('/');
    final lastSep = lastSlash > lastForwardSlash ? lastSlash : lastForwardSlash;
    if (lastSep >= 0 && lastSep < p.length - 1) {
      return p.substring(lastSep + 1);
    }
    return p;
  }
  String get path => startup?.startupPath ?? '';
  bool get enabled => startup?.enabled ?? true;
  int? get startupId => startup?.id;
  int? get merchantId => merchant?.id;
  EnabledState get enabledState => startup?.enabledState ?? EnabledState(status: true);

  // 兼容旧 StartupItem getter
  String get zone => startup?.zone ?? 'BRANCH';
  int? get delay => startup?.startupDelay;
  String? get args => startup?.parameter;
  bool get forceRun => startup?.isForcedOn ?? false;
  String? get targetOs => startup?.targetOs;
  String? get disableIn => startup?.disableIn; // 禁用到期时间

  /// 公共策略生效网吧名的展示文案（对齐 web PublicStrategyDialog.vue:379-380）
  String get merchantNamesText {
    final names = merchants.map((e) => e.name).where((e) => e.isNotEmpty).toList();
    return names.isEmpty ? '' : names.join('、');
  }

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
    this.merchants = const [],
    this.group,
    this.isPlaceholder = false,
  });

  /// 无策略网吧的占位行（私有策略列表扁平化时产出）。
  /// id 取 0 而不是 null：TacticItem.id 是非空 int，V1 旧页面大量直接读 item.id，
  /// 改成可空会连带改一大片 V1 代码；靠 isPlaceholder 标记来区分更安全。
  factory TacticItem.placeholder(MerchantBrief merchant) {
    return TacticItem(
      id: 0,
      merchant: merchant,
      startup: null,
      createdAt: '',
      updatedAt: '',
      isPlaceholder: true,
    );
  }

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
      // T8c-0：公共策略字段，私有策略接口不返回，解析全部容错
      merchants: (json['merchants'] as List?)?.whereType<Map>().map((e) {
            final m = Map<String, dynamic>.from(e);
            // 兼容后端两种键名（web PublicStrategyDialog.vue:379 `m.name || m.merchantName`）
            m['id'] ??= m['merchant_id'];
            m['name'] ??= m['merchantName'];
            return MerchantBrief.fromJson(m);
          }).toList() ??
          const [],
      group: json['group'] is Map
          ? GroupBrief.fromJson(Map<String, dynamic>.from(json['group'] as Map))
          : null,
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

