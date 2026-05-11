import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../netbar/data/netbar_api.dart';

/// 可控网吧穿梭框
///
/// 对标 toolboxPage `UserPage.vue` 第 263-339 行的双表格穿梭框。
/// 数据策略：弹窗内直接调 `NetbarApi.getList()` 拉取全量（按当前用户权限过滤）。
class MerchantTransfer extends StatefulWidget {
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  const MerchantTransfer({
    super.key,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<MerchantTransfer> createState() => _MerchantTransferState();
}

class _MerchantTransferState extends State<MerchantTransfer> {
  bool _loading = true;
  String? _loadError;
  List<Netbar> _all = const [];

  String _leftSearch = '';
  String _rightSearch = '';
  int? _leftGroupFilter;
  final Set<int> _leftChecked = <int>{};
  final Set<int> _rightChecked = <int>{};

  late final TextEditingController _leftSearchCtrl;
  late final TextEditingController _rightSearchCtrl;

  @override
  void initState() {
    super.initState();
    _leftSearchCtrl = TextEditingController();
    _rightSearchCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _leftSearchCtrl.dispose();
    _rightSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await NetbarApi().getList();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  // ---- 派生数据 ----

  Set<int> get _selectedSet => widget.selectedIds.toSet();

  /// 分组下拉选项：从 _all[].groups 聚合去重
  List<MapEntry<int, String>> get _groupOptions {
    final map = <int, String>{};
    for (final n in _all) {
      final gs = n.groups;
      if (gs == null) continue;
      for (final g in gs) {
        if (g.id > 0 && !map.containsKey(g.id)) map[g.id] = g.name;
      }
    }
    return map.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  }

  List<Netbar> get _leftList {
    final selectedSet = _selectedSet;
    final kw = _leftSearch.trim().toLowerCase();
    return _all.where((n) {
      if (selectedSet.contains(n.id)) return false;
      if (_leftGroupFilter != null) {
        final gs = n.groups;
        if (gs == null || !gs.any((g) => g.id == _leftGroupFilter)) return false;
      }
      if (kw.isNotEmpty) {
        final name = n.name.toLowerCase();
        final groupName = (n.groups?.isNotEmpty == true ? n.groups!.first.name : '').toLowerCase();
        if (!name.contains(kw) && !groupName.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  List<Netbar> get _rightList {
    final selectedSet = _selectedSet;
    final kw = _rightSearch.trim().toLowerCase();
    return _all.where((n) {
      if (!selectedSet.contains(n.id)) return false;
      if (kw.isNotEmpty) {
        final name = n.name.toLowerCase();
        final groupName = (n.groups?.isNotEmpty == true ? n.groups!.first.name : '').toLowerCase();
        if (!name.contains(kw) && !groupName.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  // ---- 操作 ----

  void _moveToRight() {
    if (_leftChecked.isEmpty) return;
    final next = <int>{...widget.selectedIds, ..._leftChecked}.toList();
    widget.onChanged(next);
    setState(_leftChecked.clear);
  }

  void _moveToLeft() {
    if (_rightChecked.isEmpty) return;
    final removeSet = Set<int>.from(_rightChecked);
    final next = widget.selectedIds.where((id) => !removeSet.contains(id)).toList();
    widget.onChanged(next);
    setState(_rightChecked.clear);
  }

  void _toggleLeftCheck(int id, bool? value) {
    setState(() {
      if (value == true) {
        _leftChecked.add(id);
      } else {
        _leftChecked.remove(id);
      }
    });
  }

  void _toggleRightCheck(int id, bool? value) {
    setState(() {
      if (value == true) {
        _rightChecked.add(id);
      } else {
        _rightChecked.remove(id);
      }
    });
  }

  /// tri-state 全选：在当前显示列表范围内
  void _toggleSelectAllLeft(bool? value) {
    final ids = _leftList.map((n) => n.id).toSet();
    setState(() {
      if (value == true) {
        _leftChecked.addAll(ids);
      } else {
        _leftChecked.removeAll(ids);
      }
    });
  }

  void _toggleSelectAllRight(bool? value) {
    final ids = _rightList.map((n) => n.id).toSet();
    setState(() {
      if (value == true) {
        _rightChecked.addAll(ids);
      } else {
        _rightChecked.removeAll(ids);
      }
    });
  }

  bool? _leftHeaderTriState() {
    final ids = _leftList.map((n) => n.id).toSet();
    if (ids.isEmpty) return false;
    final inter = ids.intersection(_leftChecked);
    if (inter.isEmpty) return false;
    if (inter.length == ids.length) return true;
    return null;
  }

  bool? _rightHeaderTriState() {
    final ids = _rightList.map((n) => n.id).toSet();
    if (ids.isEmpty) return false;
    final inter = ids.intersection(_rightChecked);
    if (inter.isEmpty) return false;
    if (inter.length == ids.length) return true;
    return null;
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _buildLoadingOrError(loading: true);
    }
    if (_loadError != null) {
      return _buildLoadingOrError(loading: false);
    }
    return context.isNarrow ? _buildNarrow() : _buildWide();
  }

  Widget _buildLoadingOrError({required bool loading}) {
    return Container(
      height: 360,
      decoration: _panelDecoration,
      alignment: Alignment.center,
      child: loading
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(strokeWidth: 2),
                SizedBox(height: 12),
                Text('加载网吧列表...', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertCircle, size: 28, color: Colors.red.shade400),
                const SizedBox(height: 8),
                Text(
                  '加载失败：${_loadError ?? '未知错误'}',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(LucideIcons.refreshCw, size: 14),
                  label: const Text('重试'),
                ),
              ],
            ),
    );
  }

  // 宽屏：左右双栏 + 中间按钮
  Widget _buildWide() {
    return SizedBox(
      height: 360,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildLeftPanel()),
          const SizedBox(width: 12),
          _buildMoveButtons(vertical: true),
          const SizedBox(width: 12),
          Expanded(child: _buildRightPanel()),
        ],
      ),
    );
  }

  // 窄屏：Tab 切换待选/已选
  Widget _buildNarrow() {
    return DefaultTabController(
      length: 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            labelColor: AppColors.iosBlue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.iosBlue,
            tabs: [
              Tab(text: '待选 (${_leftList.length})'),
              Tab(text: '已选 (${widget.selectedIds.length})'),
            ],
          ),
          SizedBox(
            height: 360,
            child: TabBarView(
              children: [
                _buildLeftPanel(),
                _buildRightPanel(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildMoveButtons(vertical: false),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      decoration: _panelDecoration,
      child: Column(
        children: [
          _buildPanelHeader(
            title: '待选',
            tristate: _leftHeaderTriState(),
            onToggleAll: _toggleSelectAllLeft,
            countSelected: _leftChecked.length,
            countTotal: _leftList.length,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildGroupDropdown(),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _buildSearchField(
                    controller: _leftSearchCtrl,
                    hint: '搜索网吧',
                    onChanged: (v) => setState(() => _leftSearch = v),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList(_leftList, _leftChecked, _toggleLeftCheck, leftSide: true)),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      decoration: _panelDecoration,
      child: Column(
        children: [
          _buildPanelHeader(
            title: '已选 (${widget.selectedIds.length})',
            tristate: _rightHeaderTriState(),
            onToggleAll: _toggleSelectAllRight,
            countSelected: _rightChecked.length,
            countTotal: _rightList.length,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: _buildSearchField(
              controller: _rightSearchCtrl,
              hint: '搜索网吧',
              onChanged: (v) => setState(() => _rightSearch = v),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList(_rightList, _rightChecked, _toggleRightCheck, leftSide: false)),
        ],
      ),
    );
  }

  Widget _buildPanelHeader({
    required String title,
    required bool? tristate,
    required ValueChanged<bool?> onToggleAll,
    required int countSelected,
    required int countTotal,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              tristate: true,
              value: tristate,
              onChanged: countTotal == 0 ? null : onToggleAll,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (countSelected > 0)
            Text(
              '勾选 $countSelected',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupDropdown() {
    final options = _groupOptions;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          isExpanded: true,
          value: _leftGroupFilter,
          hint: const Text('所属分组', style: TextStyle(fontSize: 12, color: Colors.grey)),
          icon: const Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey),
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('全部分组')),
            ...options.map((e) => DropdownMenuItem<int?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (v) => setState(() => _leftGroupFilter = v),
        ),
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
          prefixIcon: const Icon(LucideIcons.search, size: 13, color: Colors.grey),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildList(
    List<Netbar> data,
    Set<int> checkedSet,
    void Function(int id, bool? value) onToggle, {
    required bool leftSide,
  }) {
    if (_all.isEmpty) {
      return const Center(
        child: Text('暂无可控网吧', style: TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    if (data.isEmpty) {
      // 区分"右侧本来就空"和"搜索无结果"
      final hasSearch = leftSide ? _leftSearch.isNotEmpty : _rightSearch.isNotEmpty;
      final hasFilter = leftSide && _leftGroupFilter != null;
      final msg = (hasSearch || hasFilter)
          ? '无匹配结果'
          : (leftSide ? '所有网吧已选完' : '暂未选择');
      return Center(
        child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      );
    }
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: data.length,
      itemBuilder: (context, index) {
        final n = data[index];
        final checked = checkedSet.contains(n.id);
        final groupName = n.groups?.isNotEmpty == true ? n.groups!.first.name : '';
        return InkWell(
          onTap: () => onToggle(n.id, !checked),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: checked,
                    onChanged: (v) => onToggle(n.id, v),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        n.name,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (groupName.isNotEmpty)
                        Text(
                          groupName,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoveButtons({required bool vertical}) {
    final toRightEnabled = _leftChecked.isNotEmpty;
    final toLeftEnabled = _rightChecked.isNotEmpty;
    final btnRight = _circleButton(
      icon: LucideIcons.chevronRight,
      enabled: toRightEnabled,
      filled: true,
      onTap: _moveToRight,
    );
    final btnLeft = _circleButton(
      icon: LucideIcons.chevronLeft,
      enabled: toLeftEnabled,
      filled: false,
      onTap: _moveToLeft,
    );
    if (vertical) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [btnLeft, const SizedBox(height: 10), btnRight],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [btnLeft, const SizedBox(width: 12), btnRight],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool enabled,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final bg = filled
        ? (enabled ? AppColors.iosBlue : Colors.grey.shade300)
        : Colors.transparent;
    final fg = filled
        ? Colors.white
        : (enabled ? AppColors.iosBlue : Colors.grey);
    final border = filled
        ? null
        : Border.all(color: enabled ? AppColors.iosBlue : Colors.grey.shade300);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          border: border,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: fg),
      ),
    );
  }

  BoxDecoration get _panelDecoration => BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      );
}
