import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/terminal_api.dart';

enum _ProcessSortKey { name, pid, cpu, mem, user }

class ProcessManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String seatId;
  const ProcessManagerTab({super.key, required this.terminalId, required this.seatId});

  @override
  ConsumerState<ProcessManagerTab> createState() => _ProcessManagerTabState();
}

class _ProcessManagerTabState extends ConsumerState<ProcessManagerTab> {
  String _processSearch = '';
  List<TerminalProcess> _processes = [];
  bool _loading = false;
  String? _error;
  _ProcessSortKey? _sortKey;
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    _loadProcesses();
  }

  Future<void> _loadProcesses() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      final list = await api.getProcesses(widget.seatId, domain: domain);
      if (mounted) {
        setState(() {
          _processes = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _killProcess(int pid) async {
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      await api.killProcess(widget.seatId, pid, domain: domain);
      if (mounted) {
        showTopNotice(context, '已发送结束进程指令', level: NoticeLevel.success);
        _loadProcesses();
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '结束进程失败: $e', level: NoticeLevel.error);
      }
    }
  }

  bool _defaultSortAsc(_ProcessSortKey key) {
    switch (key) {
      case _ProcessSortKey.cpu:
      case _ProcessSortKey.mem:
        return false; // CPU/内存默认降序
      case _ProcessSortKey.name:
      case _ProcessSortKey.pid:
      case _ProcessSortKey.user:
        return true;
    }
  }

  void _toggleSort(_ProcessSortKey key) {
    setState(() {
      if (_sortKey == key) {
        _sortAsc = !_sortAsc;
      } else {
        _sortKey = key;
        _sortAsc = _defaultSortAsc(key);
      }
    });
  }

  List<TerminalProcess> get _filteredProcesses {
    final query = _processSearch.trim().toLowerCase();
    final list = (query.isEmpty
            ? _processes
            : _processes.where((p) {
                return p.name.toLowerCase().contains(query) || p.pid.toString().contains(query);
              }))
        .toList();

    final sortKey = _sortKey;
    if (sortKey == null) return list;

    int compare(TerminalProcess a, TerminalProcess b) {
      int c;
      switch (sortKey) {
        case _ProcessSortKey.name:
          c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case _ProcessSortKey.pid:
          c = a.pid.compareTo(b.pid);
          break;
        case _ProcessSortKey.cpu:
          c = a.cpu.compareTo(b.cpu);
          break;
        case _ProcessSortKey.mem:
          c = a.mem.compareTo(b.mem);
          break;
        case _ProcessSortKey.user:
          c = a.user.toLowerCase().compareTo(b.user.toLowerCase());
          break;
      }
      if (c == 0) c = a.pid.compareTo(b.pid);
      return _sortAsc ? c : -c;
    }

    list.sort(compare);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isPhone || context.isNarrow;
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Search
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _processSearch = v),
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        LucideIcons.search,
                        size: 16,
                        color: Colors.grey.shade400,
                      ),
                      hintText: '搜索进程...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Actions
              Row(
                children: [
                  _buildActionButton(
                    '刷新',
                    LucideIcons.refreshCw,
                    Colors.grey.shade700,
                    Colors.white,
                    Colors.grey.shade300,
                    onTap: _loadProcesses,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Header
        if (!isNarrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(child: _buildSortHeaderCell('进程名', _ProcessSortKey.name)),
                SizedBox(width: 80, child: _buildSortHeaderCell('PID', _ProcessSortKey.pid)),
                SizedBox(width: 100, child: _buildSortHeaderCell('CPU %', _ProcessSortKey.cpu)),
                SizedBox(width: 100, child: _buildSortHeaderCell('内存 (MB)', _ProcessSortKey.mem)),
                SizedBox(width: 120, child: _buildSortHeaderCell('用户', _ProcessSortKey.user)),
                const SizedBox(width: 48), // Action col (touch-safe)
              ],
            ),
          ),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Text(
                    '加载失败: $_error',
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredProcesses.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade100),
                  itemBuilder: (context, index) {
                    final proc = _filteredProcesses[index];
                    if (isNarrow) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: Text(
                          proc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 6,
                            children: [
                              _metaChip('PID', '${proc.pid}'),
                              _metaChip('CPU', '${proc.cpu}%'),
                              _metaChip('内存', '${proc.mem} MB'),
                              _metaChip('用户', proc.user),
                            ],
                          ),
                        ),
                        trailing: SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton(
                            icon: const Icon(
                              LucideIcons.xCircle,
                              size: 20,
                              color: Colors.red,
                            ),
                            tooltip: '结束进程',
                            onPressed: () => _killProcess(proc.pid),
                          ),
                        ),
                      );
                    }

                    return InkWell(
                      onTap: () {},
                      hoverColor: Colors.blue.shade50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                proc.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                '${proc.pid}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                '${proc.cpu}%',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: Text(
                                '${proc.mem}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 120,
                              child: Text(
                                proc.user,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: IconButton(
                                icon: const Icon(
                                  LucideIcons.xCircle,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                tooltip: '结束进程',
                                onPressed: () => _killProcess(proc.pid),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color textColor,
    Color bgColor,
    Color borderColor, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade500,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSortHeaderCell(String text, _ProcessSortKey key) {
    final isActive = _sortKey == key;
    final color = isActive ? AppColors.iosBlue : Colors.grey.shade500;
    return GestureDetector(
      onTap: () => _toggleSort(key),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Row(
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 12,
                color: AppColors.iosBlue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
      ),
    );
  }
}
