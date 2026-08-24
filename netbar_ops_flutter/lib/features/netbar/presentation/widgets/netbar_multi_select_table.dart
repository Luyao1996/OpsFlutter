import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/netbar_api.dart';
import '../../data/version_compare.dart';

/// 表格各定宽列的宽度，表头与数据行共用，保证两边列对齐
const double _kCheckColW = 32;
const double _kVersionColW = 62;
const double _kStatusColW = 54;
const double _kTerminalColW = 54;

/// 低于该可用宽度时隐藏「终端数」列，把空间让给网吧名称与状态
const double _kHideTerminalWidth = 420;

/// 网吧多选表格组件（搜索 + 分组 / 版本号 / 在线状态筛选）
/// 对标 Vue 端 BatchClearWindowsPasswordDialog.vue 和 BatchProgramUpdateDialog.vue 中的共用表格部分
class NetbarMultiSelectTable extends StatefulWidget {
  final List<Netbar> netbars;
  final List<GroupBrief> groups;
  final ValueChanged<List<int>> onSelectionChanged;

  /// 是否在表格下方显示「已选择 N 家网吧」。
  /// 调用方自己有更详细的已选提示时传 false，避免同一句话出现两遍。
  final bool showSelectedCount;

  const NetbarMultiSelectTable({
    super.key,
    required this.netbars,
    required this.groups,
    required this.onSelectionChanged,
    this.showSelectedCount = true,
  });

  @override
  State<NetbarMultiSelectTable> createState() => _NetbarMultiSelectTableState();
}

class _NetbarMultiSelectTableState extends State<NetbarMultiSelectTable> {
  String _searchQuery = '';
  int? _filterGroupId;
  String? _filterVersion;
  bool? _filterOnline;
  final Set<int> _selectedIds = {};
  late List<String> _versionOptions;

  @override
  void initState() {
    super.initState();
    _versionOptions = _buildVersionOptions();
  }

  @override
  void didUpdateWidget(covariant NetbarMultiSelectTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.netbars, widget.netbars)) {
      _versionOptions = _buildVersionOptions();
      // 选中的版本可能已经不在新数据里；不清掉的话 DropdownButtonFormField
      // 会因为 value 在 items 中找不到而直接断言失败
      if (_filterVersion != null && !_versionOptions.contains(_filterVersion)) {
        _filterVersion = null;
      }
    }
  }

  List<Netbar> get _filteredNetbars {
    return widget.netbars.where((n) {
      final matchName = _searchQuery.isEmpty || n.name.contains(_searchQuery);
      final matchGroup = _filterGroupId == null ||
          (n.groups?.any((g) => g.id == _filterGroupId) ?? false);
      final matchVersion = _filterVersion == null || n.version == _filterVersion;
      final matchOnline = _filterOnline == null || n.isOnline == _filterOnline;
      return matchName && matchGroup && matchVersion && matchOnline;
    }).toList();
  }

  /// 版本号选项：去重后按语义化版本降序（"1.10" 必须排在 "1.2" 前面，不能按字符串排）
  List<String> _buildVersionOptions() {
    final set = <String>{};
    for (final n in widget.netbars) {
      final v = n.version;
      if (v != null && v.isNotEmpty) set.add(v);
    }
    final list = set.toList();
    list.sort((a, b) => compareVersion(a, b, desc: true));
    return list;
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

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
    );
  }

  Widget _headerCell(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)),
      );

  /// 在线状态徽章：描边圆角小标签，对标 Vue 端 el-tag effect="plain" round
  Widget _statusBadge(bool online) {
    final color = online ? const Color(0xFF16A34A) : const Color(0xFF909399);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        online ? '在线' : '离线',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNetbars;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final showTerminal = available >= _kHideTerminalWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 筛选栏（对标 Vue 端 filter-bar）
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 「共 N 家」占掉一截宽度，搜索框只能按 Wrap 自己拿到的宽度算，
                // 直接用外层 available 会横向溢出
                Expanded(
                  child: LayoutBuilder(builder: (context, barConstraints) {
                    final barWidth = barConstraints.maxWidth;
                    // 手机端弹窗是全屏页，筛选栏必须能换行；搜索框在 Wrap 里拿不到
                    // 弹性宽度，只能显式给：窄屏独占一行，宽屏留 200 让三个下拉排同一行
                    final searchWidth = barWidth < 500 ? barWidth : 200.0;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // 名称搜索
                        SizedBox(
                          width: searchWidth,
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: _fieldDecoration('搜索网吧名称').copyWith(
                              prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        // 分组筛选
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<int?>(
                            value: _filterGroupId,
                            isExpanded: true,
                            decoration: _fieldDecoration('全部分组'),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('全部分组', style: TextStyle(fontSize: 13))),
                              ...widget.groups.map((g) => DropdownMenuItem<int?>(
                                    value: g.id,
                                    child: Text(g.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _filterGroupId = v),
                          ),
                        ),
                        // 版本号筛选
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String?>(
                            value: _filterVersion,
                            isExpanded: true,
                            decoration: _fieldDecoration('全部版本'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('全部版本', style: TextStyle(fontSize: 13))),
                              ..._versionOptions.map((v) => DropdownMenuItem<String?>(
                                    value: v,
                                    child: Text('v$v', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _filterVersion = v),
                          ),
                        ),
                        // 在线状态筛选
                        SizedBox(
                          width: 110,
                          child: DropdownButtonFormField<bool?>(
                            value: _filterOnline,
                            isExpanded: true,
                            decoration: _fieldDecoration('全部状态'),
                            items: const [
                              DropdownMenuItem<bool?>(value: null, child: Text('全部状态', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem<bool?>(value: true, child: Text('在线', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem<bool?>(value: false, child: Text('离线', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) => setState(() => _filterOnline = v),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
                const SizedBox(width: 8),
                Text(
                  '共 ${filtered.length} 家',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
                            width: _kCheckColW,
                            child: Checkbox(
                              value: _isAllSelected,
                              onChanged: _toggleAll,
                              activeColor: AppColors.iosBlue,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('网吧名称',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('所属分组',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF909399)),
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(width: _kVersionColW, child: _headerCell('版本号')),
                          SizedBox(width: _kStatusColW, child: _headerCell('状态')),
                          if (showTerminal) SizedBox(width: _kTerminalColW, child: _headerCell('终端数')),
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
                                final version = (n.version != null && n.version!.isNotEmpty) ? 'v${n.version}' : '-';
                                return InkWell(
                                  onTap: () => _toggleItem(n.id, !checked),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: _kCheckColW,
                                          child: Checkbox(
                                            value: checked,
                                            onChanged: (v) => _toggleItem(n.id, v),
                                            activeColor: AppColors.iosBlue,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(n.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                        ),
                                        Expanded(
                                          flex: 3,
                                          child: Text(groupNames,
                                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        SizedBox(
                                          width: _kVersionColW,
                                          child: Text(version,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 12),
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                        SizedBox(
                                          width: _kStatusColW,
                                          child: Center(child: _statusBadge(n.isOnline)),
                                        ),
                                        if (showTerminal)
                                          SizedBox(
                                            width: _kTerminalColW,
                                            child: Text('${n.terminalCount}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(fontSize: 13),
                                                overflow: TextOverflow.ellipsis),
                                          ),
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
            if (widget.showSelectedCount && _selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '已选择 ${_selectedIds.length} 家网吧',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        );
      },
    );
  }
}
