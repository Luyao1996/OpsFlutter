import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'startup_monitor_models.dart';
import 'channel_models.dart' show StartupItem, TacticItem, LocaleItem, MerchantBrief, EnabledState, IpRange, ConfigFile, StartupPeriod, StartupStrategy;

// 重新导出以保持兼容
export 'channel_models.dart' show StartupItem, TacticItem, LocaleItem, MerchantBrief, EnabledState, IpRange, ConfigFile, StartupPeriod, StartupStrategy;

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

  bool get isFileMode => fileBytes != null && fileName != null;

  LocaleSubmitData({
    this.id,
    this.groupFileId,
    required this.path,
    this.content,
    this.fileBytes,
    this.fileName,
  });
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
    final List<TacticItem> result = [];
    for (final merchantData in merchantList) {
      if (merchantData is! Map<String, dynamic>) continue;

      final merchant = MerchantBrief.fromJson(merchantData);
      final tactics = merchantData['tactics'] as List? ?? [];

      for (final tacticData in tactics) {
        if (tacticData is! Map<String, dynamic>) continue;
        // 将商户信息注入到 tactic 数据中
        final enrichedTactic = Map<String, dynamic>.from(tacticData);
        enrichedTactic['merchant'] = merchantData;
        result.add(TacticItem.fromJson(enrichedTactic));
      }
    }

    return result;
  }

  /// 禁用启动项（仍用 startup 接口）
  /// [state.duration] 可以是小时数(int)或 'permanent' 表示永久禁用
  Future<void> disable(int startupId, EnabledState state) async {
    int? hours;
    if (state.duration != null && state.duration != 'permanent') {
      // duration 可能是 int 或 String
      if (state.duration is int) {
        hours = state.duration as int;
      } else {
        hours = int.tryParse(state.duration.toString());
      }
    }
    await _client.post('/startup/disable/$startupId', data: {
      if (hours != null && hours > 0) 'hours': hours,
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
    if (startupId != null) {
      formData.fields.add(MapEntry('startup[id]', startupId.toString()));
    }
    if (groupFileId != null) {
      formData.fields.add(MapEntry('startup[group_file_id]', groupFileId.toString()));
    }
    if (path != null) {
      formData.fields.add(MapEntry('startup[path]', path));
    }
    formData.fields.add(MapEntry('startup[parameter]', parameter ?? ''));
    formData.fields.add(MapEntry('startup[delay]', (delay ?? 0).toString()));
    formData.fields.add(MapEntry('startup[is_random_name]', (isRandomName ?? false) ? '1' : '0'));
    formData.fields.add(MapEntry('startup[is_forced_on]', (isForcedOn ?? false) ? '1' : '0'));
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

    // locales 部分
    _appendLocales(formData, locales);

    // area 部分
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
    if (groupFileId != null) {
      formData.fields.add(MapEntry('startup[group_file_id]', groupFileId.toString()));
    }
    formData.fields.add(MapEntry('startup[path]', path));
    formData.fields.add(MapEntry('startup[parameter]', parameter ?? ''));
    formData.fields.add(MapEntry('startup[delay]', (delay ?? 0).toString()));
    formData.fields.add(MapEntry('startup[is_random_name]', (isRandomName ?? false) ? '1' : '0'));
    formData.fields.add(MapEntry('startup[is_forced_on]', (isForcedOn ?? false) ? '1' : '0'));
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

    // locales 部分
    _appendLocales(formData, locales);

    // merchants 部分（必需）
    for (int i = 0; i < merchantIds.length; i++) {
      formData.fields.add(MapEntry('merchants[$i][id]', merchantIds[i].toString()));
      if (area != null && area.isNotEmpty) {
        for (final a in area) {
          formData.fields.add(MapEntry('merchants[$i][area][]', a));
        }
      }
    }

    await _client.post('/tactic', data: formData);
  }

  /// 公共方法：将 locales 数据追加到 FormData
  void _appendLocales(FormData formData, List<LocaleSubmitData>? locales) {
    if (locales == null) return;
    for (int i = 0; i < locales.length; i++) {
      final locale = locales[i];
      if (locale.id != null) {
        formData.fields.add(MapEntry('locales[$i][id]', locale.id.toString()));
      }
      if (locale.groupFileId != null) {
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
      } else if (locale.content != null && locale.content!.isNotEmpty) {
        // 文本模式：发送文本内容
        formData.fields.add(MapEntry('locales[$i][content]', locale.content!));
      }
    }
  }
}

/// 启动项监控 API - 使用 /channel 接口
class StartupItemMonitorApi {
  final ApiClient _client = ApiClient.instance;

  Future<List<NetbarMonitorData>> getMonitor({String? keyword}) async {
    final params = <String, dynamic>{
      'page': 1,
      'size': 100,
      'type': 'merchant',
    };
    if (keyword != null && keyword.isNotEmpty) {
      params['keyword'] = keyword;
    }

    final response = await _client.get('/channel', queryParameters: params);
    final data = response.data;

    // 解析 paginator.data
    List<dynamic> merchantList = [];
    if (data is Map<String, dynamic>) {
      final paginator = data['paginator'] as Map<String, dynamic>?;
      if (paginator != null) {
        merchantList = paginator['data'] as List? ?? [];
      }
    }

    return merchantList
        .map((e) => NetbarMonitorData.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
