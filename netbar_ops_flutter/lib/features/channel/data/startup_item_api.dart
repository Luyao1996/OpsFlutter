import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import 'startup_monitor_models.dart';
import 'channel_models.dart' show StartupItem, TacticItem, LocaleItem, MerchantBrief, EnabledState, IpRange, ConfigFile, StartupPeriod, StartupStrategy;

// 重新导出以保持兼容
export 'channel_models.dart' show StartupItem, TacticItem, LocaleItem, MerchantBrief, EnabledState, IpRange, ConfigFile, StartupPeriod, StartupStrategy;

/// 启动项 API - 适配后端 /api/tactic
class StartupItemApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取策略列表（原启动项列表）
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

    // 后端返回 {paginator: {data: [...]}}
    List<dynamic> list = [];
    if (data is Map<String, dynamic>) {
      final paginator = data['paginator'] as Map<String, dynamic>?;
      if (paginator != null) {
        list = paginator['data'] as List? ?? [];
      }
    } else if (data is List) {
      list = data;
    }

    return list.map((e) => TacticItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 禁用启动项（仍用 startup 接口）
  Future<void> disable(int startupId, EnabledState state) async {
    final hours = state.durationDays != null ? state.durationDays! * 24 : null;
    await _client.post('/startup/disable/$startupId', data: {
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
    List<LocaleItem>? locales,
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
    if (locales != null) {
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
        if (locale.content != null && locale.content!.isNotEmpty) {
          formData.fields.add(MapEntry('locales[$i][content]', locale.content!));
        }
      }
    }

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
}

/// 启动项监控 API - 后端可能不支持
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
