import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/strategy_api.dart';

/// 「生效网吧」多选面板。
///
/// 对齐 web netbar-panel（LocalStrategyAdd.vue:13-70）：
/// 分组下拉 + 关键字搜索 + 全选 + 逐行勾选。数据源 GET /tactic/merchants
/// （T8c-0 已实现，全量无分页，每个 merchant 带 groups[] 归属）。
///
/// 【使用范围，留痕】T8c-2 时只给公共策略用；本次（用户反馈 #5）起
/// **私有策略编辑态**在显式开启 `allowMerchantEdit` 时也复用本面板。
/// V1 两个旧页面不开该开关，仍是"当前网吧"上下文、看不到本面板 → V1 行为不变。
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

  /// 用户反馈 #3 新增（**可选，默认 null → 与改动前一字不差**）：
  /// 新增态默认勾选的网吧 id（V2 传"顶部 tab 栏当前网吧"）。
  ///
  /// 【生效条件，留痕】只有 [initialSelectedIds] 为空（= 新增态 / 无回填）
  /// **且**该 id 出现在 /tactic/merchants 返回的候选里时才勾；候选里没有就
  /// 静默跳过，不报错。编辑态的回填集合非空 → 本参数不参与，绝不覆盖回填。
  /// 不在本组件里读 currentNetbarProvider：那会让共享层对所有调用方（含 V1）
  /// 生效，必须由调用方显式注入。
  final int? defaultSelectedMerchantId;

  const StrategyMerchantsPanel({
    super.key,
    required this.api,
    required this.onChanged,
    this.groupFileId,
    this.initialSelectedIds = const {},
    this.isSheet = false,
    this.defaultSelectedMerchantId,
  });

  @override
  State<StrategyMerchantsPanel> createState() => _StrategyMerchantsPanelState();
}

class _StrategyMerchantsPanelState extends State<StrategyMerchantsPanel> {
  final TextEditingController _kw = TextEditingController();

  /// 筛选行控件统一高度（边框由 Container 自绘，见 build 内注释）
  static const double _kFilterHeight = 36;

  /// 搜索框边框自绘 → 聚焦高亮只能自己监听 FocusNode
  final FocusNode _kwFocus = FocusNode();

  static BoxDecoration _filterBox({bool focused = false}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: focused ? AppColors.iosBlue : const Color(0xFFDCDFE6),
          width: focused ? 1.5 : 1,
        ),
      );

  List<MerchantBrief> _all = const [];
  late Set<int> _selected;
  String? _groupFilter;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initialSelectedIds};
    _kwFocus.addListener(_onKwFocusChanged);
    _load();
  }

  @override
  void dispose() {
    _kwFocus.removeListener(_onKwFocusChanged);
    _kwFocus.dispose();
    _kw.dispose();
    super.dispose();
  }

  void _onKwFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.getTacticMerchants(
        groupFileId: widget.groupFileId,
      );
      if (!mounted) return;
      // 默认勾选当前网吧：只在"一家都没勾"时补，且必须在候选列表里
      final int? fallback = widget.defaultSelectedMerchantId;
      final int? applyId = (_selected.isEmpty &&
              fallback != null &&
              list.any((m) => m.id == fallback))
          ? fallback
          : null;
      setState(() {
        _all = list;
        _loading = false;
        if (applyId != null) _selected.add(applyId);
      });
      // 回调必须发出去，否则父弹窗的 _selectedMerchantIds 还是空、保存时会报
      // 「请至少选择一家网吧」。此处已过异步 gap，不在 build 阶段，可以直接调。
      if (applyId != null) _notify();
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
              // 文案改成两形态通用（本面板现在也给私有策略编辑态用）
              Text(
                '至少选择一家网吧；已选 ${_selected.length} 家',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 12),
              // 【溢出修复】原先分组下拉写死 SizedBox(width:130) + isExpanded 缺省(false)：
              // DropdownButton 不换行时按**最宽 item 的固有宽度**撑开自己，分组名一长
              // 就把 130 撑爆 → 整行 RIGHT OVERFLOWED。改为
              //   1. isExpanded:true + item 文本 ellipsis（下拉不再按内容撑宽）
              //   2. 两个控件都用 Expanded 按比例分配（窄容器下一起收缩，不会溢出）
              //
              // 【等高修复，与 v2_strategy_list_dialog 同一根因】原来两个控件都是
              // InputDecorator（DropdownButtonFormField / TextField）套 SizedBox(36)：
              // isDense 时 InputDecorator 的可见边框按自身内容算高度，SizedBox 只占位
              // 不撑边框 → 下拉≈36、输入框≈18，肉眼明显不齐。现在边框一律由 Container
              // 自绘，高度恒为 _kFilterHeight。
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: _kFilterHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.center,
                      decoration: _filterBox(),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _groupFilter,
                          isDense: true,
                          isExpanded: true,
                          hint: const Text('所属分组',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF9CA3AF))),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 16, color: Color(0xFF9CA3AF)),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF1F2937)),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null,
                                child: Text('全部分组',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            for (final g in _groupOptions)
                              DropdownMenuItem(
                                value: g,
                                child: Text(g,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (v) => setState(() => _groupFilter = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: _kFilterHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: _filterBox(focused: _kwFocus.hasFocus),
                      child: TextField(
                        controller: _kw,
                        focusNode: _kwFocus,
                        style: const TextStyle(fontSize: 13),
                        onChanged: (_) => setState(() {}),
                        // isCollapsed + 边框全 none + filled:false：装饰完全交给外层
                        // Container（同时压掉全局 inputDecorationTheme 的 filled/边框）
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          hintText: '搜索网吧 / 分组',
                          hintStyle:
                              TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
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
