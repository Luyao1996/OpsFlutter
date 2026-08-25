import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/strategy_api.dart';

/// 「生效网吧」多选面板（T8c-2 新增，**只给公共策略用**）。
///
/// 对齐 web StrategyAddDialog.vue:15-70 的 netbar-panel：
/// 分组下拉 + 关键字搜索 + 全选 + 逐行勾选。数据源 GET /tactic/merchants
/// （T8c-0 已实现，全量无分页，每个 merchant 带 groups[] 归属）。
///
/// 【只用于 public 的原因，留痕】私有策略在 Flutter 侧是"当前网吧"上下文
/// （V1 两个旧页面就一个网吧，V2 列表页在进表单前先弹单选器），编辑态 web 也只构造
/// 当前一家、不请求列表（StrategyAddDialog.vue:806-822）。把本面板挂到私有形态上
/// 等于给 V1 平白多一个页签 —— 违反"V1 行为一字不变"，故不做。
///
/// 【虚拟化】网吧可达上千家，列表恒走 ListView.builder。
class StrategyMerchantsPanel extends StatefulWidget {
  final StrategyApi api;

  /// 透传给 /tactic/merchants 的 group_file_id（可空，为空拿全量）
  final int? groupFileId;

  /// 初始勾选的网吧 id（编辑态 = 已生效网吧；复制态 = 模板的生效网吧）
  final Set<int> initialSelectedIds;

  /// 勾选变化回调（父弹窗保存时取这一份）
  final ValueChanged<Set<int>> onChanged;

  final bool isSheet;

  const StrategyMerchantsPanel({
    super.key,
    required this.api,
    required this.onChanged,
    this.groupFileId,
    this.initialSelectedIds = const {},
    this.isSheet = false,
  });

  @override
  State<StrategyMerchantsPanel> createState() => _StrategyMerchantsPanelState();
}

class _StrategyMerchantsPanelState extends State<StrategyMerchantsPanel> {
  final TextEditingController _kw = TextEditingController();

  List<MerchantBrief> _all = const [];
  late Set<int> _selected;
  String? _groupFilter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedIds};
    _load();
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.getTacticMerchants(
        groupFileId: widget.groupFileId,
      );
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载网吧列表失败: $e';
        _loading = false;
      });
    }
  }

  /// 分组名列表。
  /// 【写法说明】不写 `m.groups ?? const []`：策略侧的 GroupBrief 被
  /// strategy_api.dart 的 re-export 刻意 hide 掉了（与 netbar_api 的同名类冲突），
  /// 这里名不可写、`const []` 会退化成 List&lt;dynamic&gt; 让 g.name 变成动态调用。
  /// 先取局部变量做非空判断，静态类型全程保留。
  List<String> _groupNamesOf(MerchantBrief m) {
    final gs = m.groups;
    if (gs == null) return const [];
    return gs.map((g) => g.name).where((n) => n.isNotEmpty).toList();
  }

  List<String> get _groupOptions {
    final set = <String>{};
    for (final m in _all) {
      set.addAll(_groupNamesOf(m));
    }
    return set.toList();
  }

  String _groupsText(MerchantBrief m) => _groupNamesOf(m).join('、');

  /// 过滤口径照抄 web filteredNetbarList（:316-324）：分组精确匹配，
  /// 关键字同时匹配网吧名与分组名，大小写不敏感。
  List<MerchantBrief> get _filtered {
    final kw = _kw.text.trim().toLowerCase();
    final gf = _groupFilter;
    return _all.where((m) {
      final groupNames = _groupNamesOf(m);
      if (gf != null && gf.isNotEmpty && !groupNames.contains(gf)) return false;
      if (kw.isEmpty) return true;
      if (m.name.toLowerCase().contains(kw)) return true;
      return groupNames.any((g) => g.toLowerCase().contains(kw));
    }).toList();
  }

  void _notify() => widget.onChanged({..._selected});

  void _toggle(int id, bool on) {
    setState(() {
      if (on) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
    _notify();
  }

  /// 全选只作用于**当前过滤结果**（对齐 web handleSelectAll，:334-336）
  void _toggleAll(bool on) {
    final visible = _filtered;
    setState(() {
      for (final m in visible) {
        if (on) {
          _selected.add(m.id);
        } else {
          _selected.remove(m.id);
        }
      }
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.isSheet ? 16.0 : 24.0;
    final list = _filtered;
    final allSelected =
        list.isNotEmpty && list.every((m) => _selected.contains(m.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '生效网吧',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '公共策略至少选择一家网吧；已选 ${_selected.length} 家',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    height: 36,
                    child: DropdownButtonFormField<String>(
                      initialValue: _groupFilter,
                      isDense: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '所属分组',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF1F2937)),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('全部分组')),
                        for (final g in _groupOptions)
                          DropdownMenuItem(value: g, child: Text(g)),
                      ],
                      onChanged: (v) => setState(() => _groupFilter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _kw,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: '搜索网吧 / 分组',
                          hintStyle:
                              TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: allSelected,
                      tristate: false,
                      onChanged: list.isEmpty
                          ? null
                          : (v) => _toggleAll(v ?? false),
                      activeColor: AppColors.iosBlue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '全选当前筛选结果（${list.length} 家）',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildList(list, pad)),
      ],
    );
  }

  Widget _buildList(List<MerchantBrief> list, double pad) {
    if (_loading) {
      return const Center(
        child: Text('加载中...',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.red)),
        ),
      );
    }
    if (list.isEmpty) {
      return const Center(
        child: Text('无匹配网吧',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    // 网吧可能上千家 → 虚拟化
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pad - 8, 0, pad - 8, 12),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final m = list[i];
        final groups = _groupsText(m);
        final checked = _selected.contains(m.id);
        return InkWell(
          onTap: () => _toggle(m.id, !checked),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: checked,
                    onChanged: (v) => _toggle(m.id, v ?? false),
                    activeColor: AppColors.iosBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF1F2937)),
                      ),
                      Text(
                        '终端数 ${m.terminalCount}'
                        '${groups.isEmpty ? '' : ' · $groups'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF9CA3AF)),
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
}
