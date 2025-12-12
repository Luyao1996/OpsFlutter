import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

class LogManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  const LogManagerTab({super.key, required this.terminalId});

  @override
  ConsumerState<LogManagerTab> createState() => _LogManagerTabState();
}

class _LogManagerTabState extends ConsumerState<LogManagerTab> {
  String _selectedCategory = 'All';
  int? _selectedLogIndex;
  List<TerminalLog> _logs = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final logs = await api.getLogs(widget.terminalId);
      if (mounted) {
        setState(() {
          _logs = logs;
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

  // Categories derived from logs
  List<String> get _categories {
    final cats = _logs.map((l) => l.category).toSet().toList();
    cats.sort();
    return ['All', ...cats];
  }

  List<TerminalLog> get _filteredLogs {
    if (_selectedCategory == 'All') return _logs;
    return _logs.where((l) => l.category == _selectedCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载失败: $_error', style: const TextStyle(color: Colors.red)));

    return Row(
      children: [
        // Left Sidebar: Log Categories
        Container(
          width: 240,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: const [
                    Icon(LucideIcons.list, size: 20, color: Colors.black87),
                    SizedBox(width: 8),
                    Text('日志分类', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final cat = _categories[index];
                    final isSelected = cat == _selectedCategory;
                    final count = cat == 'All' ? _logs.length : _logs.where((l) => l.category == cat).length;
                    
                    return InkWell(
                      onTap: () => setState(() {
                        _selectedCategory = cat;
                        _selectedLogIndex = null;
                      }),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.fileText, size: 16, color: isSelected ? Colors.blue : Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cat, 
                                style: TextStyle(
                                  fontSize: 13, 
                                  color: isSelected ? Colors.blue : Colors.grey.shade700,
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                )
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        
        // Right Content Area
        Expanded(
          child: Column(
            children: [
              // Toolbar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    IconButton(icon: Icon(LucideIcons.refreshCw, size: 16, color: Colors.grey.shade500), onPressed: _loadLogs),
                  ],
                ),
              ),
              
              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.shade50,
                child: Row(
                  children: [
                    SizedBox(width: 80, child: _buildHeaderCell('级别')),
                    SizedBox(width: 150, child: _buildHeaderCell('时间')),
                    SizedBox(width: 150, child: _buildHeaderCell('来源')),
                    SizedBox(width: 60, child: _buildHeaderCell('事件ID')),
                    Expanded(child: _buildHeaderCell('消息')),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.grey.shade200),

              // Table List
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredLogs.length,
                  itemBuilder: (context, index) {
                    final log = _filteredLogs[index];
                    final isSelected = _selectedLogIndex == index;
                    return InkWell(
                      onTap: () => setState(() => _selectedLogIndex = index),
                      child: Container(
                        color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            SizedBox(width: 80, child: _buildLevelCell(log.level)),
                            SizedBox(width: 150, child: Text(log.time, style: const TextStyle(fontSize: 12))),
                            SizedBox(width: 150, child: Text(log.source, style: const TextStyle(fontSize: 12))),
                            SizedBox(width: 60, child: Text('${log.eventId}', style: const TextStyle(fontSize: 12))),
                            Expanded(child: Text(log.message, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Bottom Detail Panel
              if (_selectedLogIndex != null)
                _buildDetailPanel(_filteredLogs[_selectedLogIndex!]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String text) {
    return Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600));
  }

  Widget _buildLevelCell(String level) {
    IconData icon;
    Color color;
    switch (level.toLowerCase()) {
      case 'error': icon = LucideIcons.alertTriangle; color = Colors.red; break;
      case 'warning': icon = LucideIcons.alertTriangle; color = Colors.orange; break;
      default: icon = LucideIcons.info; color = Colors.blue;
    }
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(level, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDetailPanel(TerminalLog log) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Event ${log.eventId} - ${log.source}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 14, color: Colors.grey),
                  onPressed: () => setState(() => _selectedLogIndex = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    log.message,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
