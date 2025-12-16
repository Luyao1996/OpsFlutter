import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';

import '../../../shared/utils/web_download_helper_stub.dart'
    if (dart.library.html) '../../../shared/utils/web_download_helper_web.dart';
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
  final int _pageSize = 20;
  bool _exporting = false;

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

  Future<void> _handleExport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final api = LogApi();
      final now = DateTime.now();
      final name = 'logs_${DateFormat('yyyyMMdd_HHmmss').format(now)}.xlsx';

      final isMobile =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS);

      if (kIsWeb) {
        final bytes = await api.exportLogsBytes(
          search: _search.isNotEmpty ? _search : null,
          module: _moduleFilter?.name,
          level: _levelFilter?.name,
          timeRange: _timeRange,
        );
        await downloadBytesAsFile(bytes, name);
        if (mounted) {
          showTopNotice(context, '已导出: $name', level: NoticeLevel.success);
        }
        return;
      }

      if (isMobile) {
        final bytes = await api.exportLogsBytes(
          search: _search.isNotEmpty ? _search : null,
          module: _moduleFilter?.name,
          level: _levelFilter?.name,
          timeRange: _timeRange,
        );
        if (bytes.isEmpty) {
          throw Exception('导出内容为空');
        }
        final saved = await FilePicker.platform.saveFile(
          dialogTitle: '导出系统日志',
          fileName: name,
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: Uint8List.fromList(bytes),
        );
        if (saved == null) return;
        if (mounted) {
          showTopNotice(context, '已导出: $name', level: NoticeLevel.success);
        }
        return;
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出系统日志',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (savePath == null) return;
      await api.exportLogsToFile(
        savePath: savePath,
        search: _search.isNotEmpty ? _search : null,
        module: _moduleFilter?.name,
        level: _levelFilter?.name,
        timeRange: _timeRange,
      );
      if (mounted) {
        showTopNotice(context, '已导出到: $savePath', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '导出失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
        module: _moduleFilter?.name,
        level: _levelFilter?.name,
        timeRange: _timeRange,
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
    final successRate = scopeLogs.isEmpty
        ? 100.0
        : (success / scopeLogs.length * 100);
    return LogStatsData(
      total: totalFromServer,
      successRate: successRate,
      warning: warning,
      error: error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final filteredLogs = _logs.where((log) {
      final matchSearch =
          _search.isEmpty ||
          log.action.toLowerCase().contains(_search.toLowerCase()) ||
          log.description.toLowerCase().contains(_search.toLowerCase()) ||
          log.id.toLowerCase().contains(_search.toLowerCase()) ||
          log.user.name.toLowerCase().contains(_search.toLowerCase());
      final matchModule = _moduleFilter == null || log.module == _moduleFilter;
      final matchLevel = _levelFilter == null || log.level == _levelFilter;
      return matchSearch && matchModule && matchLevel;
    }).toList();

    final pagePadding = isPhone
        ? const EdgeInsets.all(12)
        : const EdgeInsets.all(24);
    final contentCardPadding = isPhone
        ? const EdgeInsets.all(12)
        : const EdgeInsets.all(24);
    final sectionGap = isPhone ? 12.0 : 24.0;

    final filter = LogFilter(
      search: _search,
      onSearchChanged: (v) {
        setState(() {
          _search = v;
          _page = 1;
        });
        _fetchLogs();
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
      onExport: _handleExport,
    );

    final content = _error != null
        ? _buildErrorView()
        : isPhone
        ? CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: LogStats(data: _buildStats(filteredLogs)),
              ),
              SliverToBoxAdapter(child: SizedBox(height: sectionGap)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedHeaderDelegate(
                  height: (36 * 2) + 8 + contentCardPadding.vertical + 12,
                  child: ColoredBox(
                    color: const Color(0xFFF3F4F6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: AppShadows.sm,
                      ),
                      padding: contentCardPadding,
                      child: KeyedSubtree(
                        key: const ValueKey('system_logs_filter'),
                        child: filter,
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (_loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else ...[
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final itemIndex = index ~/ 2;
                      if (index.isOdd) return const SizedBox(height: 10);
                      final log = filteredLogs[itemIndex];
                      return LogPhoneCard(
                        log: log,
                        onTap: () => _handleViewDetail(log),
                      );
                    },
                    childCount: filteredLogs.isEmpty
                        ? 0
                        : (filteredLogs.length * 2 - 1),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(child: _buildPagination()),
              ],
            ],
          )
        : Column(
            children: [
              LogStats(data: _buildStats(filteredLogs)),
              SizedBox(height: sectionGap),
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
                      Padding(padding: contentCardPadding, child: filter),
                      if (_loading)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
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
            padding: EdgeInsets.symmetric(
              horizontal: isPhone ? 12 : 24,
              vertical: isPhone ? 12 : 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: isPhone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '系统日志',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${filteredLogs.length} 条记录（共 $_total 条）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '数据保留: 180 天',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '系统日志',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${filteredLogs.length} 条记录（共 $_total 条）',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '数据保留周期: 180 天',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: Padding(padding: pagePadding, child: content),
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
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '未知错误',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final text = Text(
          '第 $_page / $totalPages 页（共 $_total 条）',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        );
        final controls = Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              onPressed: _page > 1
                  ? () {
                      setState(() => _page -= 1);
                      _fetchLogs();
                    }
                  : null,
              icon: const Icon(LucideIcons.chevronLeft, size: 16),
            ),
            IconButton(
              onPressed: _page < totalPages
                  ? () {
                      setState(() => _page += 1);
                      _fetchLogs();
                    }
                  : null,
              icon: const Icon(LucideIcons.chevronRight, size: 16),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: compact ? 8 : 12,
          ),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    text,
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: controls),
                  ],
                )
              : Row(children: [text, const Spacer(), controls]),
        );
      },
    );
  }
}

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.height != height;
  }
}
