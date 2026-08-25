import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'strategy_models.dart';

// 重新导出以保持兼容（V1 旧页面只 import 本文件就能拿到全部策略模型）。
// hide GroupBrief：features/netbar/data/netbar_api.dart 里有一个同名但不同的 GroupBrief，
// channel_v2 大量 import netbar_api；若这里把 GroupBrief 一起导出去，
// 同时 import 这两个文件的地方会直接报 ambiguous import。
// 需要策略侧 GroupBrief 类型的，请显式 import 'strategy_models.dart'（必要时带 as 前缀）。
export 'strategy_models.dart' hide GroupBrief;

/// 本地化文件提交数据 - 支持文本内容或文件上传
class LocaleSubmitData {
  final int? id;
  final int? groupFileId;
  final String path;
  /// 文本模式：文本内容
  final String? content;
  /// 上传模式：文件字节
  final Uint8List? fileBytes;
  /// 上传模式：文件名
  final String? fileName;

  /// T8c-0 新增：后端回传的已上传文件 id。
  /// "上传模式 + 本次没有重新选文件"时必须原样发回去，否则后端会丢掉文件引用。
  final int? fileId;

  /// T8c-0 新增：是否为上传模式（对齐 web StrategyAddDialog.vue:920 `file.mode === 'upload'`）。
  /// 不能只靠 fileBytes 判断：重编辑一条已上传的本地化文件时没有新字节，但仍是上传模式。
  final bool isUploadMode;

  bool get isFileMode => fileBytes != null && fileName != null;

  LocaleSubmitData({
    this.id,
    this.groupFileId,
    required this.path,
    this.content,
    this.fileBytes,
    this.fileName,
    this.fileId,
    this.isUploadMode = false,
  });
}

/// 策略列表结果（列表 + 分页信息）
///
/// T8c-0：私有 /tactic 与公共 /public-tactic 的 paginator.data 结构完全不同，
/// 解析必须分开写（见 listPrivateTactics / listPublicTactics），只有这个结果壳是共用的。
class TacticListResult {
  final List<TacticItem> items;
  final int total;
  final int currentPage;
  final int perPage;

  const TacticListResult({
    required this.items,
    required this.total,
    this.currentPage = 1,
    this.perPage = 20,
  });

  static const empty = TacticListResult(items: [], total: 0);
}

/// 启动项 API - 适配后端 /api/tactic
class StartupItemApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取策略列表（原启动项列表）
  /// 后端返回的是 商户列表，每个商户下嵌套 tactics 数组，需要展平
  Future<List<TacticItem>> getAll({
    String? zone,
    bool? enabled,
    String? search,
    int? netbarId,
    int? groupFileId,
    String? groupFileType,
  }) async {
    final params = <String, dynamic>{};
    if (search != null && search.isNotEmpty) params['keyword'] = search;
    if (groupFileId != null) params['group_file_id'] = groupFileId;
    if (groupFileType != null) params['group_file_type'] = groupFileType;

    final response = await _client.get('/tactic', queryParameters: params);
    final data = response.data;

    // 后端返回 {paginator: {data: [{id: merchantId, name, tactics: [...]}]}}
    List<dynamic> merchantList = [];
    if (data is Map<String, dynamic>) {
      final paginator = data['paginator'] as Map<String, dynamic>?;
      if (paginator != null) {
        merchantList = paginator['data'] as List? ?? [];
      }
    } else if (data is List) {
      merchantList = data;
    }

    // 展平：遍历商户，提取每个商户下的 tactics
    // T8c-0：扁平化逻辑抽成 _flattenPrivateTactics 与 listPrivateTactics 共用。
    // 这里保持 V1 原口径：无策略的商户直接丢弃、不排序——V1 的卡片 UI 没有占位行的概念，
    // 塞进去会渲染出一张没有 id 的空卡片（删除/启禁用全炸）。占位行只给 V2 的
    // listPrivateTactics 用（T8c-1 的表格会按 isPlaceholder 禁掉操作按钮）。
    return _flattenPrivateTactics(merchantList, keepPlaceholder: false, sort: false);
  }

  /// 私有策略列表扁平化（后端 paginator.data = [merchant{tactics:[]}]）
  ///
  /// [keepPlaceholder] 为 true 时，没有任何策略的商户会产出一条 isPlaceholder 占位行
  /// （对齐 web NetbarStrategyDialog.vue:334-365）。
  List<TacticItem> _flattenPrivateTactics(
    List<dynamic> merchantList, {
    required bool keepPlaceholder,
    required bool sort,
  }) {
    final List<TacticItem> result = [];
    for (final merchantData in merchantList) {
      if (merchantData is! Map<String, dynamic>) continue;

      final tactics = merchantData['tactics'] as List? ?? [];
      var appended = 0;

      for (final tacticData in tactics) {
        if (tacticData is! Map<String, dynamic>) continue;
        // 将商户信息注入到 tactic 数据中
        final enrichedTactic = Map<String, dynamic>.from(tacticData);
        enrichedTactic['merchant'] = merchantData;
        result.add(TacticItem.fromJson(enrichedTactic));
        appended++;
      }

      if (keepPlaceholder && appended == 0) {
        result.add(TacticItem.placeholder(MerchantBrief.fromJson(merchantData)));
      }
    }

    if (sort) {
      // 与 web 一致按网吧名排序。偏离留痕：web 用 localeCompare(zh-CN) 走中文拼音排序，
      // Dart 的 String.compareTo 是 UTF-16 码点序，中文名的先后次序会和 web 不同。
      result.sort((a, b) => (a.merchant?.name ?? '').compareTo(b.merchant?.name ?? ''));
    }
    return result;
  }

  /// 禁用启动项（仍用 startup 接口）
  /// [state.duration] 可以是小时数(int)或 'permanent' 表示永久禁用
  Future<void> disable(int startupId, EnabledState state) async {
    int? hours;
    if (state.duration == 'permanent') {
      // 【T8c-0 行为变更 a】永久禁用要显式发 hours:0。
      // web NetbarStrategyDialog.vue:116-124 的单选组「永久」就是 value=0，
      // performEnableDisable(:489) 只判 `hours !== null` 就带上参数，request.js:136 会保留 0。
      // 原 Flutter 写法（duration=='permanent' → hours 留 null → `hours>0` 过滤掉）
      // 会发一个空 body，后端收不到 hours 只能按默认时长处理，永久禁用根本不生效。
      // 本次行为变更同时影响 V1 旧页面（通道管理页 / 资源管理页的"永久禁用"），需回归验证。
      hours = 0;
    } else if (state.duration != null) {
      // duration 可能是 int 或 String
      if (state.duration is int) {
        hours = state.duration as int;
      } else {
        hours = int.tryParse(state.duration.toString());
      }
    }
    await _client.post('/startup/disable/$startupId', data: {
      // 【T8c-0 行为变更 a】0 也要发，不能再用 `hours > 0` 过滤
      if (hours != null) 'hours': hours,
    });
  }

  /// 启用启动项（仍用 startup 接口）
  Future<void> enable(int startupId) async {
    await _client.post('/startup/enable/$startupId');
  }

  /// 更新策略 - POST /tactic/{id}
  Future<void> updateTactic(
    int tacticId, {
    // startup 字段
    int? startupId,
    String? path,
    int? groupFileId,
    String? parameter,
    int? delay,
    bool? isRandomName,
    bool? isForcedOn,
    StartupStrategy? strategy,
    List<StartupPeriod>? period,
    // locales 字段
    List<LocaleSubmitData>? locales,
    // area 字段
    List<String>? area,
  }) async {
    final formData = FormData();

    // startup 部分
    _appendStartup(
      formData,
      startupId: startupId,
      groupFileId: groupFileId,
      path: path,
      parameter: parameter,
      delay: delay,
      isRandomName: isRandomName,
      isForcedOn: isForcedOn,
      strategy: strategy,
      period: period,
    );

    // locales 部分
    _appendLocales(formData, locales);

    // area 部分（私有策略编辑态：web StrategyAddDialog.vue:965-988 只发 area[]，不发 merchants）
    if (area != null) {
      if (area.isEmpty) {
        formData.fields.add(const MapEntry('area[]', ''));
      } else {
        for (final a in area) {
          formData.fields.add(MapEntry('area[]', a));
        }
      }
    }

    await _client.post('/tactic/$tacticId', data: formData);
  }

  /// 删除策略 - DELETE /tactic/{id}
  Future<void> delete(int tacticId) async {
    await _client.delete('/tactic/$tacticId');
  }

  /// 创建策略 - POST /tactic
  Future<void> createTactic({
    // startup 字段
    int? groupFileId,
    required String path,
    String? parameter,
    int? delay,
    bool? isRandomName,
    bool? isForcedOn,
    StartupStrategy? strategy,
    List<StartupPeriod>? period,
    // locales 字段
    List<LocaleSubmitData>? locales,
    // merchants 字段（必需）
    required List<int> merchantIds,
    List<String>? area,
  }) async {
    final formData = FormData();

    // startup 部分
    _appendStartup(
      formData,
      groupFileId: groupFileId,
      path: path,
      parameter: parameter,
      delay: delay,
      isRandomName: isRandomName,
      isForcedOn: isForcedOn,
      strategy: strategy,
      period: period,
    );

    // locales 部分
    _appendLocales(formData, locales);

    // merchants 部分（必需）——私有策略是嵌套键形 merchants[i][id] + merchants[i][area][]
    _appendPrivateMerchants(formData, merchantIds, area);

    await _client.post('/tactic', data: formData);
  }

  // ===========================================================================
  // T8c-0 新增：V2 用的列表 / 候选网吧 / 公共策略接口
  // ===========================================================================

  /// 列表请求参数（/tactic 与 /public-tactic 参数完全一致）
  Map<String, dynamic> _buildListParams({
    required int page,
    required int perPage,
    String? keyword,
    String? type,
    int? groupFileId,
    String? groupFileType,
  }) {
    final params = <String, dynamic>{'page': page, 'per_page': perPage};
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (type != null && type.isNotEmpty) params['type'] = type;
    if (groupFileId != null) params['group_file_id'] = groupFileId;
    if (groupFileType != null && groupFileType.isNotEmpty) {
      params['group_file_type'] = groupFileType;
    }
    return params;
  }

  Map<String, dynamic>? _paginatorOf(dynamic data) {
    if (data is Map<String, dynamic>) {
      final p = data['paginator'];
      if (p is Map<String, dynamic>) return p;
    }
    return null;
  }

  /// 网吧私有策略列表 - GET /tactic
  ///
  /// 响应结构：`paginator.data = [ merchant{ id,name,terminal_count,groups,tactics:[...] } ]`
  /// → 必须前端扁平化成"每条策略一行"；没有策略的网吧产出 isPlaceholder 占位行。
  /// **不要**和 listPublicTactics 共用解析：公共策略的 paginator.data 是策略数组，结构完全不同。
  Future<TacticListResult> listPrivateTactics({
    int page = 1,
    int perPage = 20,
    String? keyword,
    String? type,
    int? groupFileId,
    String? groupFileType,
  }) async {
    final response = await _client.get(
      '/tactic',
      queryParameters: _buildListParams(
        page: page,
        perPage: perPage,
        keyword: keyword,
        type: type,
        groupFileId: groupFileId,
        groupFileType: groupFileType,
      ),
    );
    final paginator = _paginatorOf(response.data);
    if (paginator == null) return TacticListResult.empty;

    final merchantList = paginator['data'] as List? ?? const [];
    final items = _flattenPrivateTactics(merchantList, keepPlaceholder: true, sort: true);

    // total 口径偏离留痕：web NetbarStrategyDialog.vue:376 用 flattened.length 当总数，
    // 那是把"当前页行数"当成"总条数"，翻页数字是坏的（页码永远只有 1 页）。
    // 我们改用后端 paginator.total（分页的真实总数，单位是"网吧"而不是"策略行"）。
    // 副作用：一个网吧挂多条策略时，本页行数会大于 per_page，行数与 total 对不齐属预期。
    final total = paginator['total'];
    return TacticListResult(
      items: items,
      total: total is int ? total : (int.tryParse(total?.toString() ?? '') ?? items.length),
      currentPage: paginator['current_page'] is int ? paginator['current_page'] as int : page,
      perPage: paginator['per_page'] is int ? paginator['per_page'] as int : perPage,
    );
  }

  /// 程序公共策略列表 - GET /public-tactic
  ///
  /// 响应结构：`paginator.data = [ tactic{ id,startup,locales,merchants:[...],group } ]`
  /// → 一条策略就是一行，不需要扁平化（对齐 web PublicStrategyDialog.vue:370-403）。
  Future<TacticListResult> listPublicTactics({
    int page = 1,
    int perPage = 20,
    String? keyword,
    String? type,
    int? groupFileId,
    String? groupFileType,
  }) async {
    final response = await _client.get(
      '/public-tactic',
      queryParameters: _buildListParams(
        page: page,
        perPage: perPage,
        keyword: keyword,
        type: type,
        groupFileId: groupFileId,
        groupFileType: groupFileType,
      ),
    );
    final paginator = _paginatorOf(response.data);
    if (paginator == null) return TacticListResult.empty;

    final rawList = paginator['data'] as List? ?? const [];
    final items = rawList
        .whereType<Map>()
        .map((e) => TacticItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final total = paginator['total'];
    return TacticListResult(
      items: items,
      total: total is int ? total : (int.tryParse(total?.toString() ?? '') ?? items.length),
      currentPage: paginator['current_page'] is int ? paginator['current_page'] as int : page,
      perPage: paginator['per_page'] is int ? paginator['per_page'] as int : perPage,
    );
  }

  /// 生效网吧候选列表 - GET /tactic/merchants
  ///
  /// 对齐 web src/api/LocalStrategy.js:fetchTacticMerchants。返回全量、无分页，
  /// 每个 merchant 带 groups[] 归属映射（策略弹窗左侧按分组分类要用）。
  /// 响应本身就是数组（ApiClient 已剥掉 {code,message,data} 外壳）。
  Future<List<MerchantBrief>> getTacticMerchants({int? groupFileId}) async {
    final params = <String, dynamic>{};
    // group_file_id 允许不传（web 那边把非空校验注释掉了，后端会返回全量网吧）
    if (groupFileId != null) params['group_file_id'] = groupFileId;

    final response = await _client.get('/tactic/merchants', queryParameters: params);
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => MerchantBrief.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 创建公共策略 - POST /public-tactic
  Future<void> createPublicTactic({
    int? groupFileId,
    required String path,
    String? parameter,
    int? delay,
    bool? isRandomName,
    bool? isForcedOn,
    StartupStrategy? strategy,
    List<StartupPeriod>? period,
    List<LocaleSubmitData>? locales,
    required List<int> merchantIds,
  }) async {
    final formData = FormData();
    _appendStartup(
      formData,
      groupFileId: groupFileId,
      path: path,
      parameter: parameter,
      delay: delay,
      isRandomName: isRandomName,
      isForcedOn: isForcedOn,
      strategy: strategy,
      period: period,
    );
    _appendLocales(formData, locales);
    // 公共策略：扁平键形 merchants[i]=id，且不带 area（公共策略没有区域概念）
    _appendPublicMerchants(formData, merchantIds);

    await _client.post('/public-tactic', data: formData);
  }

  /// 更新公共策略 - POST /public-tactic/{id}
  ///
  /// [deleteMerchantIds] 传编辑前 editData.merchants 的全部 id：
  /// web 是"先把旧的全删一遍，再发新的 merchants"（StrategyAddDialog.vue:999-1008）。
  Future<void> updatePublicTactic(
    int tacticId, {
    int? startupId,
    int? groupFileId,
    String? path,
    String? parameter,
    int? delay,
    bool? isRandomName,
    bool? isForcedOn,
    StartupStrategy? strategy,
    List<StartupPeriod>? period,
    List<LocaleSubmitData>? locales,
    required List<int> merchantIds,
    List<int>? deleteMerchantIds,
  }) async {
    final formData = FormData();
    _appendStartup(
      formData,
      startupId: startupId,
      groupFileId: groupFileId,
      path: path,
      parameter: parameter,
      delay: delay,
      isRandomName: isRandomName,
      isForcedOn: isForcedOn,
      strategy: strategy,
      period: period,
    );
    _appendLocales(formData, locales);
    _appendPublicMerchants(formData, merchantIds, deleteMerchantIds: deleteMerchantIds);

    await _client.post('/public-tactic/$tacticId', data: formData);
  }

  /// 删除公共策略 - DELETE /public-tactic/{id}
  Future<void> deletePublicTactic(int tacticId) async {
    await _client.delete('/public-tactic/$tacticId');
  }

  /// 公共方法：拼 startup 块（create / update 共用，字段顺序与原实现完全一致）
  ///
  /// 【T8c-0 行为变更 e】只有 path 非空时才发整个 startup 块。
  /// 对齐 web StrategyAddDialog.vue:866 `if (startupForm.execPath) { ... }`。
  /// 原 Flutter 无条件发 startup[parameter]/[delay]/[strategy] 等字段，
  /// 于是"只改本地化文件、startup 没有路径"的场景会把后端的 startup 配置清成空壳。
  /// 本次行为变更同时影响 V1 旧页面（startup_config_modal 传的 path 来自
  /// item.startup?.startupPath，为 null 时以前照发、现在整块跳过），需回归验证。
  void _appendStartup(
    FormData formData, {
    int? startupId,
    int? groupFileId,
    String? path,
    String? parameter,
    int? delay,
    bool? isRandomName,
    bool? isForcedOn,
    StartupStrategy? strategy,
    List<StartupPeriod>? period,
  }) {
    if (path == null || path.isEmpty) return;

    if (startupId != null) {
      formData.fields.add(MapEntry('startup[id]', startupId.toString()));
    }
    if (groupFileId != null) {
      formData.fields.add(MapEntry('startup[group_file_id]', groupFileId.toString()));
    }
    formData.fields.add(MapEntry('startup[path]', path));
    formData.fields.add(MapEntry('startup[parameter]', parameter ?? ''));
    formData.fields.add(MapEntry('startup[delay]', (delay ?? 0).toString()));
    formData.fields.add(MapEntry('startup[is_random_name]', (isRandomName ?? false) ? '1' : '0'));
    formData.fields.add(MapEntry('startup[is_forced_on]', (isForcedOn ?? false) ? '1' : '0'));
    // mode 三值原样透传（'0'/'1'/'2'）。禁止在这里做 `mode != '1' → '0'` 的降级，
    // 那是 web StrategyAddDialog.vue:1172-1180 的数据破坏 bug，见 StartupStrategy 注释。
    formData.fields.add(MapEntry('startup[strategy][mode]', strategy?.mode ?? '0'));
    if (strategy?.name != null && strategy!.name.isNotEmpty) {
      formData.fields.add(MapEntry('startup[strategy][name]', strategy.name));
    }

    if (period != null) {
      for (int i = 0; i < period.length; i++) {
        formData.fields.add(MapEntry('startup[period][$i][start]', period[i].start));
        formData.fields.add(MapEntry('startup[period][$i][end]', period[i].end));
      }
    }
  }

  /// 私有策略（/tactic）的 merchants 键形：**嵌套** merchants[i][id] + merchants[i][area][]
  ///
  /// 【T8c-0 行为变更 b】每个 merchant 无论有没有区域，都要补一条
  /// `merchants[i][area][]=''` 空串占位，对齐 web StrategyAddDialog.vue:985-993
  /// （注释原文"空数组占位，确保后端知道没有区域限制"）。
  /// 原 Flutter 是 `if (area != null && area.isNotEmpty)`，区域为空时整个 area 键都不发，
  /// 后端收不到 area 字段就会保留旧区域 —— 表现为"取消区域限制保存后区域还在"。
  /// 本次行为变更同时影响 V1 旧页面（add_startup_item_modal 新增策略），需回归验证。
  void _appendPrivateMerchants(
    FormData formData,
    List<int> merchantIds,
    List<String>? area,
  ) {
    for (int i = 0; i < merchantIds.length; i++) {
      formData.fields.add(MapEntry('merchants[$i][id]', merchantIds[i].toString()));
      if (area != null && area.isNotEmpty) {
        for (final a in area) {
          formData.fields.add(MapEntry('merchants[$i][area][]', a));
        }
      } else {
        formData.fields.add(MapEntry('merchants[$i][area][]', ''));
      }
    }
  }

  /// 公共策略（/public-tactic）的 merchants 键形：**扁平** merchants[i] = id，不带区域。
  /// 对齐 web StrategyAddDialog.vue:996-1008。编辑态还要先把原有生效网吧
  /// 全部用 delete_merchants[] 发一遍再发新的 merchants（后端是"先删后加"语义）。
  void _appendPublicMerchants(
    FormData formData,
    List<int> merchantIds, {
    List<int>? deleteMerchantIds,
  }) {
    if (deleteMerchantIds != null) {
      for (final id in deleteMerchantIds) {
        formData.fields.add(MapEntry('delete_merchants[]', id.toString()));
      }
    }
    for (int i = 0; i < merchantIds.length; i++) {
      formData.fields.add(MapEntry('merchants[$i]', merchantIds[i].toString()));
    }
  }

  /// 公共方法：将 locales 数据追加到 FormData
  void _appendLocales(FormData formData, List<LocaleSubmitData>? locales) {
    if (locales == null) return;
    for (int i = 0; i < locales.length; i++) {
      final locale = locales[i];
      if (locale.id != null) {
        formData.fields.add(MapEntry('locales[$i][id]', locale.id.toString()));
      }
      // 【T8c-0 行为变更 d】上传模式：group_file_id 恒发 0，且在"没有重新选文件"时
      // 把后端回传的 file_id 原样带回去。对齐 web StrategyAddDialog.vue:920-928。
      // 原 Flutter 完全没有 file_id，重新编辑一条已上传的本地化文件时后端拿不到引用 → 文件丢失。
      // 本次行为变更同时影响 V1 旧页面（startup_config_modal 编辑本地化文件），需回归验证。
      if (locale.isUploadMode) {
        formData.fields.add(MapEntry('locales[$i][group_file_id]', '0'));
        if (!locale.isFileMode && locale.fileId != null) {
          formData.fields.add(MapEntry('locales[$i][file_id]', locale.fileId.toString()));
        }
      } else if (locale.groupFileId != null) {
        formData.fields.add(MapEntry('locales[$i][group_file_id]', locale.groupFileId.toString()));
      }
      if (locale.path.isNotEmpty) {
        formData.fields.add(MapEntry('locales[$i][path]', locale.path));
      }
      if (locale.isFileMode) {
        // 上传模式：发送文件 + 文件名作为 content
        formData.files.add(MapEntry(
          'locales[$i][file]',
          MultipartFile.fromBytes(locale.fileBytes!, filename: locale.fileName),
        ));
        formData.fields.add(MapEntry('locales[$i][content]', locale.fileName ?? ''));
      } else if (locale.content != null) {
        // 【T8c-0 行为变更 c】文本模式：空串也要发。
        // 对齐 web StrategyAddDialog.vue:934-938（判的是 `!== null && !== undefined`）。
        // 原 Flutter 是 `content!.isNotEmpty`，把文本清空后保存等于没发 content，
        // 后端保留旧内容 —— 表现为"本地化文本删不掉"。
        // 本次行为变更同时影响 V1 旧页面，需回归验证。
        formData.fields.add(MapEntry('locales[$i][content]', locale.content!));
      }
    }
  }
}

/// T8c-0：类名保留 StartupItemApi（V1 旧页面大量引用，改名纯属制造回归面），
/// 新代码（channel_v2 / 策略共享层）用这个别名，语义与文件名 strategy_api.dart 一致。
typedef StrategyApi = StartupItemApi;
