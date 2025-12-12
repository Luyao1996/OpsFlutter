import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../data/log_types.dart';
import '../data/log_api.dart';
import 'widgets/log_stats.dart';
import 'widgets/log_filter.dart';
import 'widgets/log_table.dart';
import 'widgets/log_detail_dialog.dart';

class SystemLogsPage extends StatefulWidget {
  const SystemLogsPage({super.key});

  @override
  State<SystemLogsPage> createState() => _SystemLogsPageState();
}

class _SystemLogsPageState extends State<SystemLogsPage> {
  String _search = '';
  LogModule? _moduleFilter;
  LogLevel? _levelFilter;
  DateTimeRange? _timeRange;
  List<LogEntry> _logs = [];
  bool _loading = true;
  String? _error;
  int _total = 0;
  int _page = 1;
  int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  void _handleRefresh() {
    _fetchLogs();
  }

  void _handleViewDetail(LogEntry log) {
    showDialog(
      context: context,
      builder: (context) => LogDetailDialog(log: log),
    );
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = LogApi();
      final res = await api.getLogs(
        search: _search.isNotEmpty ? _search : null,
        module: _moduleFilter != null ? _moduleFilter!.name : null,
        level: _levelFilter != null ? _levelFilter!.name : null,
        page: _page,
        pageSize: _pageSize,
      );
      setState(() {
        _logs = res.items;
        _total = res.total;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  LogStatsData _buildStats(List<LogEntry> scopeLogs) {
    final totalFromServer = _total;
    final warning = scopeLogs.where((l) => l.level == LogLevel.warning).length;
    final error = scopeLogs.where((l) => l.level == LogLevel.error).length;
    final success = scopeLogs.length - error;
    final successRate = scopeLogs.isEmpty ? 100.0 : (success / scopeLogs.length * 100);
    return LogStatsData(
      total: totalFromServer,
      successRate: successRate,
      warning: warning,
      error: error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredLogs = _logs.where((log) {
      final matchSearch = _search.isEmpty ||
          log.action.toLowerCase().contains(_search.toLowerCase()) ||
          log.description.toLowerCase().contains(_search.toLowerCase()) ||
          log.id.toLowerCase().contains(_search.toLowerCase()) ||
          log.user.name.toLowerCase().contains(_search.toLowerCase());
      final matchModule = _moduleFilter == null || log.module == _moduleFilter;
      final matchLevel = _levelFilter == null || log.level == _levelFilter;
      return matchSearch && matchModule && matchLevel;
    }).toList();

    final content = _error != null
        ? _buildErrorView()
        : Column(
            children: [
              LogStats(data: _buildStats(filteredLogs)),
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: LogFilter(
                          search: _search,
                          onSearchChanged: (v) {
                            setState(() => _search = v);
                          },
                          moduleFilter: _moduleFilter,
                          onModuleFilterChanged: (v) => setState(() {
                            _moduleFilter = v;
                            _page = 1;
                            _fetchLogs();
                          }),
                          levelFilter: _levelFilter,
                          onLevelFilterChanged: (v) => setState(() {
                            _levelFilter = v;
                            _page = 1;
                            _fetchLogs();
                          }),
                          timeRange: _timeRange,
                          onTimeRangeChanged: (range) {
                            setState(() {
                              _timeRange = range;
                              _page = 1;
                            });
                            _fetchLogs();
                          },
                          onRefresh: _handleRefresh,
                        ),
                      ),
                      if (_loading)
                        const Expanded(child: Center(child: CircularProgressIndicator()))
                      else ...[
                        Expanded(
                          child: LogTable(
                            logs: filteredLogs,
                            onViewDetail: _handleViewDetail,
                          ),
                        ),
                        _buildPagination(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      '系统日志',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filteredLogs.length} 条记录（共 $_total 条）',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                ),
                Text(
                  '数据保留周期: 180 天',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.shieldOff, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text('加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade500)),
          const SizedBox(height: 6),
          Text(_error ?? '未知错误', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _fetchLogs,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text('第 $_page / $totalPages 页（共 $_total 条）', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          IconButton(
            onPressed: _page > 1 ? () { setState(() => _page -= 1); _fetchLogs(); } : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _page < totalPages ? () { setState(() => _page += 1); _fetchLogs(); } : null,
            icon: const Icon(LucideIcons.chevronRight, size: 16),
          ),
        ],
      ),
    );
  }
}
