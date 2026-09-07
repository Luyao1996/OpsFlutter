import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/natural_sort.dart';
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

  /// 表头排序：null = 不排序，保持接口返回顺序
  String? _sortKey;
  SortOrder? _sortOrder;

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
    final filtered = widget.netbars.where((n) {
      final matchName = _searchQuery.isEmpty || n.name.contains(_searchQuery);
      final matchGroup = _filterGroupId == null ||
          (n.groups?.any((g) => g.id == _filterGroupId) ?? false);
      final matchVersion = _filterVersion == null || n.version == _filterVersion;
      final matchOnline = _filterOnline == null || n.isOnline == _filterOnline;
      return matchName && matchGroup && matchVersion && matchOnline;
    }).toList();
    return _sortNetbars(filtered);
  }

  // ===== 表头排序 =====
  // 对齐 toolboxPage NetbarPage.vue:707-740 给网吧管理表头加排序的那笔改动。
  // 本端没有 web 那样的网吧管理页（网吧靠顶部 tab 切换），这张批量操作表格是
  // 形态最接近的列表，排序落在这里。
  //
  // 版本号列不能走自然序：'1.10' 必须排在 '1.2' 之后，得用语义化版本比较
  // （与筛选下拉的版本排序同一个 compareVersion，保证两处顺序一致）。
  static final Map<String, Object? Function(Netbar)> _sortGetters = {
    'name': (n) => n.name,
    'group': (n) => n.groups?.map((g) => g.name).join('、'),
    'version': (n) => n.version,
    'online': (n) => n.isOnline,
    'terminal': (n) => n.terminalCount,
  };

  List<Netbar> _sortNetbars(List<Netbar> list) {
    final getter = _sortGetters[_sortKey];
    if (getter == null || _sortOrder == null) return list;
    if (_sortKey == 'version') {
      return sortByGetter(list, getter, _sortOrder,
          compare: (a, b) => compareVersion(a?.toString(), b?.toString()));
    }
    return sortByGetter(list, getter, _sortOrder);
  }

  /// 三态循环：升序 → 降序 → 取消（回到接口返回的原始顺序）
  void _onHeaderTap(String key) {
    setState(() {
      if (_sortKey != key) {
        _sortKey = key;
        _sortOrder = SortOrder.ascending;
      } else if (_sortOrder == SortOrder.ascending) {
        _sortOrder = SortOrder.descending;
      } else {
        _sortKey = null;
        _sortOrder = null;
      }
    });
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

  Widget _buildSearchBox() {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: _fieldDecoration('搜索网吧名称').copyWith(
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey.shade400),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  Widget _buildGroupDropdown() {
    return DropdownButtonFormField<int?>(
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
    );
  }

  Widget _buildVersionDropdown() {
    return DropdownButtonFormField<String?>(
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
    );
  }

  Widget _buildOnlineDropdown() {
    return DropdownButtonFormField<bool?>(
      value: _filterOnline,
      isExpanded: true,
      decoration: _fieldDecoration('全部状态'),
      items: const [
        DropdownMenuItem<bool?>(value: null, child: Text('全部状态', style: TextStyle(fontSize: 13))),
        DropdownMenuItem<bool?>(value: true, child: Text('在线', style: TextStyle(fontSize: 13))),
        DropdownMenuItem<bool?>(value: false, child: Text('离线', style: TextStyle(fontSize: 13))),
      ],
      onChanged: (v) => setState(() => _filterOnline = v),
    );
  }

  /// 可排序表头：点一下切方向，第三下取消。当前列文字变蓝并带方向箭头。
  Widget _sortableHeader(String text, String key, {bool center = true}) {
    final active = _sortKey == key && _sortOrder != null;
    final color = active ? AppColors.iosBlue : const Color(0xFF909399);
    return InkWell(
      onTap: () => _onHeaderTap(key),
      child: Row(
        mainAxisAlignment:
            center ? MainAxisAlignment.center : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            active
                ? (_sortOrder == SortOrder.descending
                    ? Icons.arrow_downward
                    : Icons.arrow_upward)
                : Icons.unfold_more,
            size: 11,
            color: active ? AppColors.iosBlue : const Color(0xFFC0C4CC),
          ),
        ],
      ),
    );
  }

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
        // 手机端（全屏弹窗）走专属紧凑布局：筛选下拉等分一行、表格行改双行卡片
        final compact = available < 500;
        final showTerminal = !compact && available >= _kHideTerminalWidth;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 筛选栏（对标 Vue 端 filter-bar）
            if (compact) ...[
              _buildSearchBox(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildGroupDropdown()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildVersionDropdown()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildOnlineDropdown()),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '共 ${filtered.length} 家',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(height: 6),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 「共 N 家」占掉一截宽度，搜索框只能按 Wrap 自己拿到的宽度算，
                  // 直接用外层 available 会横向溢出
                  Expanded(
                    child: LayoutBuilder(builder: (context, barConstraints) {
                      final barWidth = barConstraints.maxWidth;
                      final searchWidth = barWidth < 500 ? barWidth : 200.0;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(width: searchWidth, child: _buildSearchBox()),
                          SizedBox(width: 130, child: _buildGroupDropdown()),
                          SizedBox(width: 120, child: _buildVersionDropdown()),
                          SizedBox(width: 110, child: _buildOnlineDropdown()),
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
            ],
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
                            child: _sortableHeader('网吧名称', 'name', center: false),
                          ),
                          if (compact)
                            SizedBox(
                                width: _kStatusColW,
                                child: _sortableHeader('状态', 'online'))
                          else ...[
                            Expanded(
                              child: _sortableHeader('所属分组', 'group', center: false),
                            ),
                            SizedBox(
                                width: _kVersionColW,
                                child: _sortableHeader('版本号', 'version')),
                            SizedBox(
                                width: _kStatusColW,
                                child: _sortableHeader('状态', 'online')),
                            if (showTerminal)
                              SizedBox(
                                  width: _kTerminalColW,
                                  child: _sortableHeader('终端数', 'terminal')),
                          ],
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
                                final checkbox = SizedBox(
                                  width: _kCheckColW,
                                  child: Checkbox(
                                    value: checked,
                                    onChanged: (v) => _toggleItem(n.id, v),
                                    activeColor: AppColors.iosBlue,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                );
                                // 手机端双行卡片：名称+状态一行，分组+版本一行，
                                // 避免五列挤一行时名称与分组黏连、各列截断到不可读
                                if (compact) {
                                  return InkWell(
                                    onTap: () => _toggleItem(n.id, !checked),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          checkbox,
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(n.name,
                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                                    overflow: TextOverflow.ellipsis),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(groupNames,
                                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                          overflow: TextOverflow.ellipsis),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(version,
                                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _statusBadge(n.isOnline),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return InkWell(
                                  onTap: () => _toggleItem(n.id, !checked),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Row(
                                      children: [
                                        checkbox,
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
