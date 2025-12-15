import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

class ProcessManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  const ProcessManagerTab({super.key, required this.terminalId});

  @override
  ConsumerState<ProcessManagerTab> createState() => _ProcessManagerTabState();
}

class _ProcessManagerTabState extends ConsumerState<ProcessManagerTab> {
  String _processSearch = '';
  List<TerminalProcess> _processes = [];
  bool _loading = false;
  String? _error;

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
      final list = await api.getProcesses(widget.terminalId);
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
      await api.killProcess(widget.terminalId, pid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送结束进程指令')),
        );
        _loadProcesses();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('结束进程失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<TerminalProcess> get _filteredProcesses {
    if (_processSearch.isEmpty) return _processes;
    return _processes.where((p) => 
      p.name.toLowerCase().contains(_processSearch.toLowerCase()) || 
      p.pid.toString().contains(_processSearch)
    ).toList();
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
                      prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
                      hintText: '搜索进程...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Actions
              Row(
                children: [
                  _buildActionButton('刷新', LucideIcons.refreshCw, Colors.grey.shade700, Colors.white, Colors.grey.shade300, onTap: _loadProcesses),
                ],
              )
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
                Expanded(child: _buildHeaderCell('进程名')),
                SizedBox(width: 80, child: _buildHeaderCell('PID')),
                SizedBox(width: 100, child: _buildHeaderCell('CPU %')),
                SizedBox(width: 100, child: _buildHeaderCell('内存 (MB)')),
                SizedBox(width: 120, child: _buildHeaderCell('用户')),
                const SizedBox(width: 48), // Action col (touch-safe)
              ],
            ),
          ),

        // List
        Expanded(
          child: _loading 
            ? const Center(child: CircularProgressIndicator())
            : _error != null 
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : ListView.separated(
                    itemCount: _filteredProcesses.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
                    itemBuilder: (context, index) {
                      final proc = _filteredProcesses[index];
                      if (isNarrow) {
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          title: Text(
                            proc.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
                              icon: const Icon(LucideIcons.xCircle, size: 20, color: Colors.red),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  proc.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87),
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
                                  child: Text('${proc.cpu}%',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800))),
                              SizedBox(
                                  width: 100,
                                  child: Text('${proc.mem}',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade800))),
                              SizedBox(
                                  width: 120,
                                  child: Text(proc.user,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500))),
                              SizedBox(
                                width: 48,
                                child: IconButton(
                                  icon: const Icon(LucideIcons.xCircle,
                                      size: 18, color: Colors.red),
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

  Widget _buildActionButton(String label, IconData icon, Color textColor, Color bgColor, Color borderColor, {VoidCallback? onTap}) {
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
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
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
