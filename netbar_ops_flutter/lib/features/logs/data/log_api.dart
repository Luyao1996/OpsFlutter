import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import 'log_types.dart';

class LogListResponse {
  final List<LogEntry> items;
  final int total;
  final int page;
  final int pageSize;
  final Map<String, String> eventMap;

  LogListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.eventMap,
  });
}

class LogApi {
  final ApiClient _client = ApiClient.instance;

  Map<String, dynamic> _exportParams({
    String? search,
    String? module,
    String? level,
    DateTimeRange? timeRange,
  }) {
    final params = <String, dynamic>{};
    if (search != null && search.isNotEmpty) params['keyword'] = search;
    if (module != null && module.isNotEmpty) params['event'] = module;
    // level参数后端不支持
    if (timeRange != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      params['start_time'] = fmt.format(timeRange.start);
      params['end_time'] = fmt.format(timeRange.end);
    }
    return params;
  }

  Future<void> exportLogsToFile({
    required String savePath,
    String? search,
    String? module,
    String? level,
    DateTimeRange? timeRange,
  }) async {
    // 后端可能不支持导出，会报错
    final params = _exportParams(
      search: search,
      module: module,
      level: level,
      timeRange: timeRange,
    );
    params['format'] = 'xlsx';
    await _client.dio.download('/export/logs', savePath, queryParameters: params);
  }

  Future<List<int>> exportLogsBytes({
    String? search,
    String? module,
    String? level,
    DateTimeRange? timeRange,
  }) async {
    // 后端可能不支持导出，会报错
    final params = _exportParams(
      search: search,
      module: module,
      level: level,
      timeRange: timeRange,
    );
    params['format'] = 'xlsx';
    final resp = await _client.dio.get<List<int>>(
      '/export/logs',
      queryParameters: params,
      options: Options(responseType: ResponseType.bytes),
    );
    return resp.data ?? const [];
  }

  /// 获取操作日志列表 - 适配后端 /api/operationLog
  Future<LogListResponse> getLogs({
    String? search,
    String? module, // 后端: event
    String? level,
    String? user,
    DateTimeRange? timeRange,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'size': pageSize,
    };
    if (search != null && search.isNotEmpty) params['keyword'] = search;
    if (module != null && module.isNotEmpty) params['event'] = module;
    if (user != null && user.isNotEmpty) params['user'] = user;
    if (timeRange != null) {
      final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
      params['start_time'] = fmt.format(timeRange.start);
      params['end_time'] = fmt.format(timeRange.end.add(const Duration(days: 1)));
    }

    final response = await _client.get('/operationLog', queryParameters: params);
    final data = response.data is Map ? response.data as Map<String, dynamic> : <String, dynamic>{};

    // 解析分页数据
    final paginator = data['paginator'] as Map<String, dynamic>? ?? {};
    final list = paginator['data'] as List? ?? [];
    final total = paginator['total'] ?? 0;
    final currentPage = paginator['current_page'] ?? page;
    final perPage = paginator['per_page'] ?? pageSize;

    // 解析事件映射
    final eventMapData = data['eventMap'] as Map<String, dynamic>? ?? {};
    final eventMapResult = eventMapData.map((k, v) => MapEntry(k, v.toString()));

    // 更新全局事件映射
    updateEventMap(eventMapData);

    return LogListResponse(
      items: list.map((e) => LogEntry.fromJson(e as Map<String, dynamic>)).toList(),
      total: total is int ? total : int.tryParse('$total') ?? 0,
      page: currentPage is int ? currentPage : int.tryParse('$currentPage') ?? page,
      pageSize: perPage is int ? perPage : int.tryParse('$perPage') ?? pageSize,
      eventMap: eventMapResult,
    );
  }

  Future<LogEntry> getById(int id) async {
    // 后端没有单独获取日志详情的接口
    throw UnimplementedError('后端不支持获取单条日志详情');
  }

  /// 添加操作日志
  Future<void> addLog({
    required String event,
    required String description,
    Map<String, dynamic>? payload,
  }) async {
    await _client.post('/operationLog', data: {
      'event': event,
      'description': description,
      if (payload != null) ...payload,
    });
  }

  /// 获取可用的事件类型列表
  Future<Map<String, String>> getEventTypes() async {
    final response = await getLogs(pageSize: 1);
    return response.eventMap;
  }
}
