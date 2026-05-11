import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/providers/app_providers.dart';

/// 操作日志 Tab —— 显示终端的操作日志（默认全部，可按 event 过滤）。
/// 数据源：`GET /terminals/{id}/operationLogs?event=xxx&page=N`
/// 主要用例：2FA 解锁记录（unlock.manual / unlock.local）。
class LogManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  const LogManagerTab({super.key, required this.terminalId});

  @override
  ConsumerState<LogManagerTab> createState() => _LogManagerTabState();
}

class _LogManagerTabState extends ConsumerState<LogManagerTab> {
  /// event 过滤：null = 全部；'unlock.manual' / 'unlock.local'
  String? _selectedEvent;
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  int _perPage = 20;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _logs = [];
  Map<String, String> _eventMap = {};
  int? _expandedIndex; // 点击行展开详情

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final raw = await api.getOperationLogs(
        widget.terminalId,
        event: _selectedEvent,
        page: _currentPage,
      );
      if (!mounted) return;
      final paginator = raw['paginator'] is Map
          ? Map<String, dynamic>.from(raw['paginator'] as Map)
          : <String, dynamic>{};
      final list = (paginator['data'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      final em = raw['eventMap'] is Map
          ? Map<String, dynamic>.from(raw['eventMap'] as Map)
          : <String, dynamic>{};
      setState(() {
        _logs = list;
        _eventMap = em.map((k, v) => MapEntry(k, v.toString()));
        _currentPage = (paginator['current_page'] as num?)?.toInt() ?? 1;
        _lastPage = (paginator['last_page'] as num?)?.toInt() ?? 1;
        _total = (paginator['total'] as num?)?.toInt() ?? list.length;
        _perPage = (paginator['per_page'] as num?)?.toInt() ?? 20;
        _expandedIndex = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onEventChanged(String? newEvent) {
    if (_selectedEvent == newEvent) return;
    setState(() {
      _selectedEvent = newEvent;
      _currentPage = 1; // 切换过滤回到第一页
    });
    _load();
  }

  void _gotoPage(int page) {
    if (page < 1 || page > _lastPage || page == _currentPage) return;
    setState(() => _currentPage = page);
    _load();
  }

  String _resolveEventLabel(String event) {
    return _eventMap[event] ?? event;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
        if (!_loading && _error == null && _logs.isNotEmpty) _buildPagination(),
      ],
    );
  }

  /// 顶部工具栏：event 过滤 dropdown + 刷新按钮。
  /// 手机端窄屏（≤360px）下避免溢出：dropdown 选中态显示短文本，
  /// 其余元素压缩；下拉菜单内仍显示完整描述。
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(LucideIcons.filter, size: 14, color: Color(0xFF6B7280)),
          const SizedBox(width: 4),
          const Text('事件:',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(width: 4),
          // Flexible 兜底：极窄屏 dropdown 也不会撑爆
          Flexible(
            child: DropdownButton<String?>(
              value: _selectedEvent,
              isDense: true,
              isExpanded: false,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              // 选中态短文本（避免长文本撑爆窄屏）
              selectedItemBuilder: (ctx) => const [
                Text('全部', overflow: TextOverflow.ellipsis),
                Text('人工解锁', overflow: TextOverflow.ellipsis),
                Text('本地解锁', overflow: TextOverflow.ellipsis),
              ],
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('全部')),
                DropdownMenuItem<String?>(
                    value: 'unlock.manual',
                    child: Text('人工解锁（生成2FA动态码）')),
                DropdownMenuItem<String?>(
                    value: 'unlock.local', child: Text('本地解锁')),
              ],
              onChanged: _onEventChanged,
            ),
          ),
          const Spacer(),
          if (_total > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '$_total 条',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(LucideIcons.refreshCw,
                    size: 16, color: Colors.grey.shade600),
            tooltip: '刷新',
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('加载失败: $_error',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
      );
    }
    if (_logs.isEmpty) {
      return Center(
        child: Text(
          '暂无操作日志',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _logs.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (_, i) => _buildItem(_logs[i], i),
    );
  }

  Widget _buildItem(Map<String, dynamic> log, int index) {
    final user = log['user'] is Map
        ? Map<String, dynamic>.from(log['user'] as Map)
        : <String, dynamic>{};
    final nickname = (user['nickname'] ?? '-').toString();
    final ip = (log['ip_address'] ?? '-').toString();
    final desc = (log['description'] ?? '-').toString();
    final event = (log['event'] ?? '').toString();
    final eventLabel = _resolveEventLabel(event);
    final createdAt = (log['created_at'] ?? '-').toString();
    final isExpanded = _expandedIndex == index;

    return InkWell(
      onTap: () =>
          setState(() => _expandedIndex = isExpanded ? null : index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: isExpanded ? Colors.blue.withOpacity(0.04) : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                // 事件 pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    eventLabel,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF2563EB)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    desc,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  createdAt,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  Icon(LucideIcons.user, size: 11, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(nickname,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(width: 12),
                  Icon(LucideIcons.globe,
                      size: 11, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(ip,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(height: 10),
              _buildDetailPanel(log),
            ],
          ],
        ),
      ),
    );
  }

  /// 展开详情：显示完整字段（含 payload JSON）
  Widget _buildDetailPanel(Map<String, dynamic> log) {
    final encoder = const JsonEncoder.withIndent('  ');
    String prettyJson;
    try {
      prettyJson = encoder.convert(log);
    } catch (_) {
      prettyJson = log.toString();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 20),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SelectableText(
        prettyJson,
        style: const TextStyle(
            fontSize: 11, fontFamily: 'monospace', color: Colors.black87),
      ),
    );
  }

  /// 底部分页：[上一页] {current/last} [下一页]
  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed:
                _currentPage > 1 ? () => _gotoPage(_currentPage - 1) : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 14),
            label: const Text('上一页', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(80, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '$_currentPage / $_lastPage 页（每页 $_perPage 条）',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _currentPage < _lastPage
                ? () => _gotoPage(_currentPage + 1)
                : null,
            icon: const Icon(LucideIcons.chevronRight, size: 14),
            label: const Text('下一页', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(80, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }
}
