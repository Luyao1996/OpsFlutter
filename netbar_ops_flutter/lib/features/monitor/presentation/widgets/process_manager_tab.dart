import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/terminal_api.dart';

enum _ProcessSortKey { name, pid, cpu, mem, user, thread }

class ProcessManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String seatId;
  const ProcessManagerTab({super.key, required this.terminalId, required this.seatId});

  @override
  ConsumerState<ProcessManagerTab> createState() => _ProcessManagerTabState();
}

class _ProcessManagerTabState extends ConsumerState<ProcessManagerTab> {
  String _processSearch = '';
  List<TerminalProcess> _processTree = [];
  bool _loading = false;
  String? _error;
  _ProcessSortKey? _sortKey;
  bool _sortAsc = true;

  // 展开状态：key 为 PID
  final Set<int> _expandedPids = {};
  bool _allExpanded = false;

  // 正在结束的进程 PID
  final Set<int> _killingPids = {};

  @override
  void initState() {
    super.initState();
    _loadProcessTree();
  }

  Future<void> _loadProcessTree() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      final tree = await api.getProcessTree(widget.seatId, domain: domain);
      if (mounted) {
        setState(() {
          _processTree = tree;
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

  Future<void> _killProcess(TerminalProcess proc, {bool killTree = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(killTree ? '结束进程树' : '结束进程'),
        content: Text(killTree
            ? '确认结束该进程及其所有子进程 (${proc.name}, PID: ${proc.pid}) ?'
            : '确认结束进程 (${proc.name}, PID: ${proc.pid}) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _killingPids.add(proc.pid));

    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      await api.killProcess(
        widget.seatId,
        proc.pid,
        domain: domain,
        processName: proc.name,
        killTree: killTree,
      );
      if (mounted) {
        showTopNotice(
          context,
          killTree ? '已发送结束进程树指令' : '已发送结束进程指令',
          level: NoticeLevel.success,
        );
        _loadProcessTree();
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '结束进程失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) {
        setState(() => _killingPids.remove(proc.pid));
      }
    }
  }

  void _toggleExpand(int pid) {
    setState(() {
      if (_expandedPids.contains(pid)) {
        _expandedPids.remove(pid);
      } else {
        _expandedPids.add(pid);
      }
    });
  }

  void _expandAll() {
    setState(() {
      _allExpanded = true;
      _collectAllPids(_processTree, _expandedPids);
    });
  }

  void _collapseAll() {
    setState(() {
      _allExpanded = false;
      _expandedPids.clear();
    });
  }

  void _collectAllPids(List<TerminalProcess> processes, Set<int> pids) {
    for (final proc in processes) {
      if (proc.hasChildren) {
        pids.add(proc.pid);
        _collectAllPids(proc.children, pids);
      }
    }
  }

  bool _defaultSortAsc(_ProcessSortKey key) {
    switch (key) {
      case _ProcessSortKey.cpu:
      case _ProcessSortKey.mem:
        return false;
      case _ProcessSortKey.name:
      case _ProcessSortKey.pid:
      case _ProcessSortKey.user:
      case _ProcessSortKey.thread:
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

  /// 是否使用树形结构显示（仅按进程名排序或无排序时保留树形）
  bool get _useTreeView => _sortKey == null || _sortKey == _ProcessSortKey.name;

  List<TerminalProcess> get _filteredTree {
    final query = _processSearch.trim().toLowerCase();

    // 先过滤
    List<TerminalProcess> filtered;
    if (query.isEmpty) {
      filtered = _processTree;
    } else {
      filtered = _filterTree(_processTree, query);
    }

    // 根据排序字段决定是否打平
    if (_useTreeView) {
      // 按进程名排序或无排序：保留树形结构
      return _sortTreeRecursive(filtered);
    } else {
      // 其他字段排序：打平后排序
      final flatList = _flattenTree(filtered);
      return _sortFlatList(flatList);
    }
  }

  /// 递归过滤进程树
  List<TerminalProcess> _filterTree(List<TerminalProcess> tree, String query) {
    final result = <TerminalProcess>[];
    for (final proc in tree) {
      final nameMatch = proc.name.toLowerCase().contains(query);
      final pidMatch = proc.pid.toString().contains(query);
      final filteredChildren = _filterTree(proc.children, query);

      if (nameMatch || pidMatch || filteredChildren.isNotEmpty) {
        result.add(TerminalProcess(
          name: proc.name,
          pid: proc.pid,
          cpu: proc.cpu,
          mem: proc.mem,
          user: proc.user,
          threadCount: proc.threadCount,
          path: proc.path,
          memoryKB: proc.memoryKB,
          children: filteredChildren,
        ));
      }
    }
    return result;
  }

  /// 将进程树打平为列表（移除所有子进程关系）
  List<TerminalProcess> _flattenTree(List<TerminalProcess> tree) {
    final result = <TerminalProcess>[];
    for (final proc in tree) {
      // 添加时移除 children，变成平面节点
      result.add(TerminalProcess(
        name: proc.name,
        pid: proc.pid,
        cpu: proc.cpu,
        mem: proc.mem,
        user: proc.user,
        threadCount: proc.threadCount,
        path: proc.path,
        memoryKB: proc.memoryKB,
        children: [], // 打平后无子进程
      ));
      // 递归添加子进程
      if (proc.children.isNotEmpty) {
        result.addAll(_flattenTree(proc.children));
      }
    }
    return result;
  }

  /// 对打平的列表排序
  List<TerminalProcess> _sortFlatList(List<TerminalProcess> list) {
    if (_sortKey == null) return list;

    final sorted = List<TerminalProcess>.from(list);
    sorted.sort(_compareProcesses);
    return sorted;
  }

  /// 递归排序树形结构（仅用于按进程名排序）
  List<TerminalProcess> _sortTreeRecursive(List<TerminalProcess> tree) {
    if (_sortKey == null) return tree;

    final sorted = List<TerminalProcess>.from(tree)..sort(_compareProcesses);
    return sorted.map((proc) {
      if (proc.children.isEmpty) return proc;
      return TerminalProcess(
        name: proc.name,
        pid: proc.pid,
        cpu: proc.cpu,
        mem: proc.mem,
        user: proc.user,
        threadCount: proc.threadCount,
        path: proc.path,
        memoryKB: proc.memoryKB,
        children: _sortTreeRecursive(proc.children),
      );
    }).toList();
  }

  /// 进程比较函数
  int _compareProcesses(TerminalProcess a, TerminalProcess b) {
    int c;
    switch (_sortKey!) {
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
      case _ProcessSortKey.thread:
        c = a.threadCount.compareTo(b.threadCount);
        break;
    }
    if (c == 0) c = a.pid.compareTo(b.pid);
    return _sortAsc ? c : -c;
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isPhone || context.isNarrow;
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          _buildToolbar(),
          if (!isNarrow) _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _filteredTree.isEmpty
                        ? _buildEmptyState()
                        : _buildProcessList(isNarrow),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text('加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          Text(_error ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadProcessTree,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.cpu, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无进程数据', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('点击刷新按钮获取进程列表', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 搜索框
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _processSearch = v),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  prefixIcon: Icon(LucideIcons.search, size: 18, color: Colors.grey.shade400),
                  hintText: '搜索进程名或 PID...',
                  hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 展开/折叠按钮（仅树形视图时显示）
          if (_useTreeView) ...[
            _ToolbarButton(
              icon: _allExpanded ? LucideIcons.minimize2 : LucideIcons.maximize2,
              label: _allExpanded ? '全部折叠' : '全部展开',
              onTap: _allExpanded ? _collapseAll : _expandAll,
            ),
            const SizedBox(width: 8),
          ],
          // 刷新按钮
          _ToolbarButton(
            icon: LucideIcons.refreshCw,
            label: '刷新',
            primary: true,
            onTap: _loadProcessTree,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // 进程名列 - 固定宽度
          SizedBox(
            width: 280,
            child: _buildSortHeaderCell('进程名', _ProcessSortKey.name),
          ),
          // 数据列 - 使用 Expanded 均分
          Expanded(
            child: Row(
              children: [
                Expanded(child: Center(child: _buildSortHeaderCell('PID', _ProcessSortKey.pid))),
                Expanded(child: Center(child: _buildSortHeaderCell('用户', _ProcessSortKey.user))),
                Expanded(child: Center(child: _buildSortHeaderCell('线程', _ProcessSortKey.thread))),
                Expanded(child: Center(child: _buildSortHeaderCell('CPU%', _ProcessSortKey.cpu))),
                Expanded(child: Center(child: _buildSortHeaderCell('内存', _ProcessSortKey.mem))),
                const SizedBox(width: 80), // 操作列
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessList(bool isNarrow) {
    final flatList = <_ProcessNode>[];
    final isTreeView = _useTreeView;

    if (isTreeView) {
      // 树形视图：保留层级结构
      void flatten(List<TerminalProcess> processes, int level) {
        for (final proc in processes) {
          final isExpanded = _expandedPids.contains(proc.pid);
          flatList.add(_ProcessNode(process: proc, level: level, isExpanded: isExpanded, isTreeView: true));
          if (proc.hasChildren && isExpanded) {
            flatten(proc.children, level + 1);
          }
        }
      }
      flatten(_filteredTree, 0);
    } else {
      // 平铺视图：所有进程平级显示
      for (final proc in _filteredTree) {
        flatList.add(_ProcessNode(process: proc, level: 0, isExpanded: false, isTreeView: false));
      }
    }

    return Container(
      color: Colors.white,
      child: ListView.builder(
        itemCount: flatList.length,
        itemBuilder: (context, index) {
          final node = flatList[index];
          if (isNarrow) {
            return _buildNarrowProcessItem(node, index);
          }
          return _buildWideProcessItem(node, index);
        },
      ),
    );
  }

  Widget _buildWideProcessItem(_ProcessNode node, int index) {
    final proc = node.process;
    final isKilling = _killingPids.contains(proc.pid);
    final isEven = index % 2 == 0;
    final canExpand = node.isTreeView && proc.hasChildren;

    return Material(
      color: isEven ? Colors.white : Colors.grey.shade50,
      child: InkWell(
        onTap: canExpand ? () => _toggleExpand(proc.pid) : null,
        hoverColor: AppColors.iosBlue.withOpacity(0.05),
        splashColor: AppColors.iosBlue.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              // 进程名列 - 固定宽度，包含缩进和图标
              SizedBox(
                width: 280,
                child: _buildProcessNameCell(node),
              ),
              // 数据列 - Expanded 均分
              Expanded(
                child: Row(
                  children: [
                    // PID
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${proc.pid}',
                            style: TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 用户
                    Expanded(
                      child: Center(
                        child: Text(
                          proc.user.isNotEmpty ? proc.user : '-',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 线程数
                    Expanded(
                      child: Center(
                        child: Text(
                          '${proc.threadCount}',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                    // CPU
                    Expanded(
                      child: Center(child: _buildCpuCell(proc.cpu)),
                    ),
                    // 内存
                    Expanded(
                      child: Center(
                        child: Text(
                          _formatMemory(proc.memoryKB),
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ),
                    ),
                    // 操作
                    SizedBox(
                      width: 80,
                      child: Center(
                        child: isKilling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : _buildKillButton(proc, node.isTreeView),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessNameCell(_ProcessNode node) {
    final proc = node.process;
    final isTreeView = node.isTreeView;
    final indent = node.level * 24.0;

    return Row(
      children: [
        // 树形视图：缩进区域（包含树线）
        if (isTreeView && node.level > 0)
          SizedBox(
            width: indent,
            child: Row(
              children: [
                for (int i = 0; i < node.level - 1; i++)
                  Container(
                    width: 24,
                    alignment: Alignment.center,
                    child: Container(
                      width: 1,
                      color: Colors.grey.shade200,
                    ),
                  ),
                Container(
                  width: 24,
                  alignment: Alignment.centerLeft,
                  child: CustomPaint(
                    size: const Size(24, 40),
                    painter: _TreeLinePainter(color: Colors.grey.shade300),
                  ),
                ),
              ],
            ),
          ),
        // 树形视图：展开/折叠图标
        if (isTreeView) ...[
          if (proc.hasChildren)
            GestureDetector(
              onTap: () => _toggleExpand(proc.pid),
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: AppColors.iosBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  node.isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                  size: 14,
                  color: AppColors.iosBlue,
                ),
              ),
            )
          else
            const SizedBox(width: 32),
          // 树形视图：进程图标
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: proc.hasChildren ? Colors.blue.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              proc.hasChildren ? LucideIcons.folder : LucideIcons.fileCode,
              size: 14,
              color: proc.hasChildren ? Colors.blue.shade400 : Colors.grey.shade500,
            ),
          ),
        ],
        // 进程名
        Expanded(
          child: Tooltip(
            message: proc.path.isNotEmpty ? proc.path : proc.name,
            child: Text(
              proc.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isTreeView && proc.hasChildren ? FontWeight.w600 : FontWeight.w500,
                color: Colors.grey.shade800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCpuCell(double cpu) {
    Color color;
    Color bgColor;
    if (cpu > 80) {
      color = Colors.red.shade700;
      bgColor = Colors.red.shade50;
    } else if (cpu > 50) {
      color = Colors.orange.shade700;
      bgColor = Colors.orange.shade50;
    } else if (cpu > 20) {
      color = Colors.blue.shade700;
      bgColor = Colors.blue.shade50;
    } else {
      color = Colors.grey.shade600;
      bgColor = Colors.transparent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${cpu.toStringAsFixed(1)}%',
        style: TextStyle(
          fontSize: 12,
          fontWeight: cpu > 50 ? FontWeight.w600 : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  Widget _buildKillButton(TerminalProcess proc, bool isTreeView) {
    // 树形视图且有子进程时，显示"结束树"选项
    final showKillTree = isTreeView && proc.hasChildren;
    return TextButton(
      onPressed: () => _killProcess(proc, killTree: showKillTree),
      style: TextButton.styleFrom(
        foregroundColor: Colors.red.shade600,
        backgroundColor: Colors.red.shade50,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        showKillTree ? '结束树' : '结束',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatMemory(int kb) {
    if (kb >= 1024 * 1024) {
      return '${(kb / 1024 / 1024).toStringAsFixed(1)} GB';
    } else if (kb >= 1024) {
      return '${(kb / 1024).toStringAsFixed(1)} MB';
    }
    return '$kb KB';
  }

  Widget _buildNarrowProcessItem(_ProcessNode node, int index) {
    final proc = node.process;
    final isKilling = _killingPids.contains(proc.pid);
    final isTreeView = node.isTreeView;
    final indent = isTreeView ? node.level * 20.0 : 0.0;
    final isEven = index % 2 == 0;
    final canExpand = isTreeView && proc.hasChildren;

    return Material(
      color: isEven ? Colors.white : Colors.grey.shade50,
      child: InkWell(
        onTap: canExpand ? () => _toggleExpand(proc.pid) : null,
        child: Container(
          padding: EdgeInsets.only(left: 16 + indent, right: 16, top: 14, bottom: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 树形视图：展开图标
              if (isTreeView) ...[
                if (proc.hasChildren)
                  Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppColors.iosBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      node.isExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.iosBlue,
                    ),
                  )
                else if (node.level > 0)
                  Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 12),
                    child: Icon(LucideIcons.cornerDownRight, size: 16, color: Colors.grey.shade300),
                  )
                else
                  const SizedBox(width: 40),
              ],
              // 内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 树形视图：进程图标
                        if (isTreeView)
                          Container(
                            width: 24,
                            height: 24,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: proc.hasChildren ? Colors.blue.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              proc.hasChildren ? LucideIcons.folder : LucideIcons.fileCode,
                              size: 12,
                              color: proc.hasChildren ? Colors.blue.shade400 : Colors.grey.shade500,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            proc.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isTreeView && proc.hasChildren ? FontWeight.w600 : FontWeight.w500,
                              color: Colors.grey.shade800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metaChip('PID', '${proc.pid}', Colors.grey),
                        _metaChip('CPU', '${proc.cpu.toStringAsFixed(1)}%',
                            proc.cpu > 50 ? Colors.orange : Colors.grey),
                        _metaChip('内存', _formatMemory(proc.memoryKB), Colors.grey),
                        if (proc.user.isNotEmpty) _metaChip('用户', proc.user, Colors.blue),
                        if (proc.threadCount > 0) _metaChip('线程', '${proc.threadCount}', Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              // 操作
              Container(
                margin: const EdgeInsets.only(left: 12),
                child: isKilling
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : IconButton(
                        icon: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            LucideIcons.x,
                            size: 18,
                            color: Colors.red.shade600,
                          ),
                        ),
                        tooltip: '结束进程',
                        onPressed: () => _killProcess(proc, killTree: false),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortHeaderCell(String text, _ProcessSortKey key) {
    final isActive = _sortKey == key;
    final color = isActive ? AppColors.iosBlue : Colors.grey.shade600;
    return GestureDetector(
      onTap: () => _toggleSort(key),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.iosBlue.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                  size: 14,
                  color: AppColors.iosBlue,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: color.shade700, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 工具栏按钮
class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.iosBlue : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primary ? AppColors.iosBlue : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: primary ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: primary ? Colors.white : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 树线绘制
class _TreeLinePainter extends CustomPainter {
  final Color color;

  _TreeLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 垂直线
    canvas.drawLine(
      Offset(12, 0),
      Offset(12, size.height / 2),
      paint,
    );
    // 水平线
    canvas.drawLine(
      Offset(12, size.height / 2),
      Offset(24, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 用于渲染的进程节点
class _ProcessNode {
  final TerminalProcess process;
  final int level;
  final bool isExpanded;
  final bool isTreeView; // 是否为树形视图模式

  _ProcessNode({
    required this.process,
    required this.level,
    required this.isExpanded,
    this.isTreeView = true,
  });
}

extension on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0)).toColor();
  }
}
