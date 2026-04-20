import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/netbar_api.dart';

/// 网吧多选表格组件（带搜索+分组筛选）
/// 对标 Vue 端 BatchClearWindowsPasswordDialog.vue 和 BatchProgramUpdateDialog.vue 中的共用表格部分
class NetbarMultiSelectTable extends StatefulWidget {
  final List<Netbar> netbars;
  final List<GroupBrief> groups;
  final ValueChanged<List<int>> onSelectionChanged;

  const NetbarMultiSelectTable({
    super.key,
    required this.netbars,
    required this.groups,
    required this.onSelectionChanged,
  });

  @override
  State<NetbarMultiSelectTable> createState() => _NetbarMultiSelectTableState();
}

class _NetbarMultiSelectTableState extends State<NetbarMultiSelectTable> {
  String _searchQuery = '';
  int? _filterGroupId;
  final Set<int> _selectedIds = {};

  List<Netbar> get _filteredNetbars {
    return widget.netbars.where((n) {
      final matchName = _searchQuery.isEmpty || n.name.contains(_searchQuery);
      final matchGroup = _filterGroupId == null ||
          (n.groups?.any((g) => g.id == _filterGroupId) ?? false);
      return matchName && matchGroup;
    }).toList();
  }

  bool get _isAllSelected {
    final filtered = _filteredNetbars;
    return filtered.isNotEmpty && filtered.every((n) => _selectedIds.contains(n.id));
  }

  void _toggleAll(bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds.addAll(_filteredNetbars.map((n) => n.id));
      } else {
        for (final n in _filteredNetbars) {
          _selectedIds.remove(n.id);
        }
      }
    });
    widget.onSelectionChanged(_selectedIds.toList());
  }

  void _toggleItem(int id, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
    widget.onSelectionChanged(_selectedIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNetbars;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 筛选栏（对标 Vue 端 filter-bar）
        Row(
          children: [
            // 名称搜索
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: '搜索网吧名称',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            // 分组筛选
            Expanded(
              child: DropdownButtonFormField<int?>(
                value: _filterGroupId,
                isExpanded: true,
                decoration: InputDecoration(
                  hintText: '全部分组',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('全部', style: TextStyle(fontSize: 13))),
                  ...widget.groups.map((g) => DropdownMenuItem<int?>(
                    value: g.id,
                    child: Text(g.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                  )),
                ],
                onChanged: (v) => setState(() => _filterGroupId = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 表格（对标 Vue 端 el-table）— 用 Expanded 填充剩余高度
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // 表头
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Checkbox(
                          value: _isAllSelected,
                          onChanged: _toggleAll,
                          activeColor: AppColors.iosBlue,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const Expanded(flex: 3, child: Text('网吧名称', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)))),
                      const Expanded(flex: 3, child: Text('所属分组', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)))),
                      const SizedBox(width: 60, child: Text('终端数', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)))),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                // 行列表 — 用 Expanded 填充表格容器剩余空间
                Expanded(
                  child: filtered.isEmpty
                    ? Center(child: Text('无匹配数据', style: TextStyle(color: Colors.grey.shade400)))
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        itemBuilder: (context, index) {
                          final n = filtered[index];
                          final checked = _selectedIds.contains(n.id);
                          final groupNames = n.groups?.map((g) => g.name).join('、') ?? '-';
                          return InkWell(
                            onTap: () => _toggleItem(n.id, !checked),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Checkbox(
                                      value: checked,
                                      onChanged: (v) => _toggleItem(n.id, v),
                                      activeColor: AppColors.iosBlue,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  Expanded(flex: 3, child: Text(n.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                                  Expanded(flex: 3, child: Text(groupNames, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                                  SizedBox(width: 60, child: Text('${n.terminalCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
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
        ),
        // 已选计数
        if (_selectedIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '已选择 ${_selectedIds.length} 家网吧',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}
