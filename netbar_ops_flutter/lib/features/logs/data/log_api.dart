import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import 'log_types.dart';

class LogListResponse {
  final List<LogEntry> items;
  final int total;
  final int page;
  final int pageSize;

  LogListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
}

class LogApi {
  final ApiClient _client = ApiClient.instance;

  Future<LogListResponse> getLogs({
    String? search,
    String? module,
    String? level,
    DateTimeRange? timeRange,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (module != null && module.isNotEmpty) params['module'] = module;
    if (level != null && level.isNotEmpty) params['level'] = level;
    if (timeRange != null) {
      final fmt = DateFormat('yyyy-MM-dd');
      params['start_date'] = fmt.format(timeRange.start);
      params['end_date'] = fmt.format(timeRange.end);
    }

    final response = await _client.get('/logs', queryParameters: params);
    final data = response.data is Map ? response.data as Map : {};
    final list = data['data'] as List? ?? [];

    return LogListResponse(
      items: list.map((e) => LogEntry.fromJson(e as Map<String, dynamic>)).toList(),
      total: data['total'] is int ? data['total'] as int : int.tryParse('${data['total'] ?? 0}') ?? 0,
      page: data['page'] is int ? data['page'] as int : int.tryParse('${data['page'] ?? page}') ?? page,
      pageSize: data['page_size'] is int ? data['page_size'] as int : int.tryParse('${data['page_size'] ?? pageSize}') ?? pageSize,
    );
  }

  Future<LogEntry> getById(int id) async {
    final response = await _client.get('/logs/$id');
    return LogEntry.fromJson(response.data as Map<String, dynamic>);
  }
}
