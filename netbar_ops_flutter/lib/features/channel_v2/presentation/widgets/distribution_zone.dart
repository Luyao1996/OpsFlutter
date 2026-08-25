import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../netbar/data/netbar_api.dart';
import '../../../netbar/data/netbar_list_provider.dart';
import '../../../netbar/data/netbar_pinyin_matcher.dart';
import '../../data/channel_v2_models.dart';
import '../channel_v2_controllers.dart';
import 'resource_zone.dart';

/// 下发区复合面板：左 scope 树 + 右下发文件区（对齐 DistributionZone.vue）。
///
/// 树结构（总部节点仅总部账号可见，对齐 useDistributionTree.js:91-130）：
///   总部（叶）
///   分组 ▼（懒展开）
///     └─ 网吧（叶；多组归属的网吧在每个组下各现一次，复合 key 独立）
class DistributionZone extends ConsumerStatefulWidget {
  final DistributionZoneController controller;

  /// 总部节点可见性（isHQUser；小组账号查 hq scope 后端直接拒绝，
  /// 且总部下发的文件本就出现在自己组的下发树里，对齐 useDistributionTree.js:93-95）
  final bool isHqUser;

  /// 宽屏：树内联在左侧；窄屏：改为顶部条 + 全屏弹窗选择（showAdaptive）
  final bool showTreeInline;

  /// 'grid' | 'list'，透传给内部文件区（对齐 DistributionZone.vue props.viewMode）
  final String viewMode;

  /// 顶栏搜索词（三区联动）。命中集合在本组件内算，
  /// 与资源区各算各的（对齐 DistributionZone.vue:160-164 matchedIds）
  final String searchQuery;

  final void Function(V2File file, Offset globalPosition)? onFileContextMenu;
  final void Function(Offset globalPosition)? onBlankContextMenu;

  /// 本区产生选中 → 页面据此清空其他区选中（对齐 zone-activate 事件）
  final VoidCallback? onZoneActivate;

  const DistributionZone({
    super.key,
    required this.controller,
    required this.isHqUser,
    this.showTreeInline = true,
    this.viewMode = 'grid',
    this.searchQuery = '',
    this.onFileContextMenu,
    this.onBlankContextMenu,
    this.onZoneActivate,
  });

  @override
  ConsumerState<DistributionZone> createState() => _DistributionZoneState();
}

class _DistributionZoneState extends ConsumerState<DistributionZone> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DistributionZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// 元数据就绪后把选中态落到第一个可见节点（对齐 useDistributionTree.js:132-143
  /// ensureSelection：总部账号是「总部」，小组账号是第一个分组）
  void _ensureSelection(List<GroupBrief> groups) {
    if (widget.controller.selectedNode != null) return;
    DistributionScope? first;
    if (widget.isHqUser) {
      first = const DistributionScope(
          key: 'hq', type: 'hq', scopeType: 'hq', scopeId: '0', name: '总部');
    } else if (groups.isNotEmpty) {
      final g = groups.first;
      first = DistributionScope(
        key: 'group-${g.id}',
        type: 'group',
        scopeType: 'group',
        scopeId: '${g.id}',
        name: g.name,
      );
    }
    if (first != null) {
      final scope = first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.controller.selectedNode == null) {
          widget.controller.selectScope(scope);
        }
      });
    }
  }

  String get _zoneTitle {
    // 对齐 DistributionZone.vue:152-158 zoneTitle
    final n = widget.controller.selectedNode;
    if (n == null) return '下发文件区';
    if (n.type == 'hq') return '下发文件区 · 总部';
    if (n.type == 'group') return '下发文件区 · ${n.name}';
    return '下发文件区';
  }

  void _selectScope(DistributionScope scope) {
    widget.controller.selectScope(scope);
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(netbarListProvider);
    final groups = listAsync.valueOrNull?.groups ?? const <GroupBrief>[];
    final merchants = listAsync.valueOrNull?.merchants ?? const <Netbar>[];
    if (listAsync.hasValue) _ensureSelection(groups);

    final filesPanel = _buildFilesPanel(context);

    if (!widget.showTreeInline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildScopePickerBar(context, groups, merchants),
          const Divider(height: 1, color: Color(0xFFF1F3F6)),
          Expanded(child: filesPanel),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: listAsync.when(
            loading: () => const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('分组加载失败\n$e',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    textAlign: TextAlign.center),
              ),
            ),
            data: (data) => ScopeTree(
              groups: data.groups,
              merchants: data.merchants,
              isHqUser: widget.isHqUser,
              selectedKey: widget.controller.selectedTreeKey,
              onSelect: _selectScope,
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFFF1F3F6)),
        Expanded(child: filesPanel),
      ],
    );
  }

  /// 窄屏 scope 选择条：点击弹全屏树选择（手机端窗口型弹窗必须 showAdaptive）
  Widget _buildScopePickerBar(
      BuildContext context, List<GroupBrief> groups, List<Netbar> merchants) {
    final node = widget.controller.selectedNode;
    return InkWell(
      onTap: () async {
        final picked = await showAdaptive<DistributionScope>(
          context,
          (_) => _ScopePickerDialog(
            groups: groups,
            merchants: merchants,
            isHqUser: widget.isHqUser,
            selectedKey: widget.controller.selectedTreeKey,
          ),
          routeName: '/dialog/channel-v2-scope-picker',
        );
        if (picked != null) _selectScope(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(LucideIcons.network, size: 15, color: Color(0xFF007AFF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node?.name ?? '选择下发目标',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151)),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  Widget _buildFilesPanel(BuildContext context) {
    final ctrl = widget.controller;
    final path = ctrl.filesCtrl.path
        .map((n) => ZonePathItem(id: n.id, name: n.name))
        .toList();
    final q = widget.searchQuery.trim().toLowerCase();
    final matched = q.isEmpty
        ? const <String>{}
        : ctrl.files
            .where((f) => f.name.toLowerCase().contains(q))
            .map((f) => f.selectionKey)
            .toSet();
    return ResourceZone(
      zoneKey: 'distribution',
      title: _zoneTitle,
      files: ctrl.files,
      path: path,
      loading: ctrl.filesCtrl.loading,
      emptyText: '此目录为空',
      viewMode: widget.viewMode,
      searchActive: q.isNotEmpty,
      matchedKeys: matched,
      selectedKeys: ctrl.selectedIds,
      onFileTap: (file, {bool ctrl = false, bool shift = false}) {
        // 先通知父层清其他区选中，再落本区选中（对齐 onDistFileClick）
        widget.onZoneActivate?.call();
        this.widget.controller.selection.onClick(file, ctrl: ctrl, shift: shift);
      },
      onFileDoubleTap: (file) {
        if (!file.isFolder) return;
        ctrl.filesCtrl.enterFolder(file);
        ctrl.selection.clear();
      },
      onBreadcrumbTap: (idx) {
        ctrl.filesCtrl.goTo(idx);
        ctrl.selection.clear();
      },
      onBlankTap: () => ctrl.selection.onBlankClick(),
      onBoxSelect: (keys) {
        widget.onZoneActivate?.call();
        ctrl.selection.onBoxSelect(keys);
      },
      onFileContextMenu: widget.onFileContextMenu,
      onBlankContextMenu: widget.onBlankContextMenu,
    );
  }
}

/// scope 树（搜索 + 懒展开）。宽屏内联在面板左侧，窄屏包进全屏弹窗复用。
class ScopeTree extends StatefulWidget {
  final List<GroupBrief> groups;
  final List<Netbar> merchants;
  final bool isHqUser;
  final String? selectedKey;
  final void Function(DistributionScope scope) onSelect;

  const ScopeTree({
    super.key,
    required this.groups,
    required this.merchants,
    required this.isHqUser,
    this.selectedKey,
    required this.onSelect,
  });

  @override
  State<ScopeTree> createState() => _ScopeTreeState();
}

class _ScopeTreeState extends State<ScopeTree> {
  final _searchCtrl = TextEditingController();
  final Set<int> _expandedGroupIds = {};

  /// groupId → 该组网吧列表。一次线性扫描建索引（数据层 O(M)），
  /// 行 widget 仍由 ListView.builder 懒建——禁一次性构建千级节点指的是 UI 节点。
  Map<int, List<Netbar>> _byGroup = const {};
  List<Netbar>? _indexedFrom;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _ensureIndex() {
    if (identical(_indexedFrom, widget.merchants)) return;
    final map = <int, List<Netbar>>{};
    for (final m in widget.merchants) {
      for (final g in m.groups ?? const <GroupBrief>[]) {
        (map[g.id] ??= []).add(m);
      }
    }
    _byGroup = map;
    _indexedFrom = widget.merchants;
  }

  @override
  Widget build(BuildContext context) {
    _ensureIndex();
    final query = _searchCtrl.text.trim();
    final searching = query.isNotEmpty;

    // 扁平化可见行：搜索时命中的网吧自动展开其所属组
    final rows = <_TreeRow>[];
    if (widget.isHqUser && (!searching || '总部'.contains(query))) {
      rows.add(const _TreeRow.hq());
    }
    for (final g in widget.groups) {
      final all = _byGroup[g.id] ?? const <Netbar>[];
      if (searching) {
        final groupHit = g.name.toLowerCase().contains(query.toLowerCase());
        // 网吧匹配复用 netbar_pinyin_matcher（名称/全拼/首字母/ID/Token/组名）
        final hits = all.where((m) => NetbarMatcher.match(m, query)).toList();
        if (!groupHit && hits.isEmpty) continue;
        rows.add(_TreeRow.group(g, all.length));
        for (final m in (hits.isNotEmpty ? hits : all)) {
          rows.add(_TreeRow.merchant(g, m));
        }
      } else {
        rows.add(_TreeRow.group(g, all.length));
        if (_expandedGroupIds.contains(g.id)) {
          for (final m in all) {
            rows.add(_TreeRow.merchant(g, m));
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索分组 / 网吧（支持拼音 cd）',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF007AFF)),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F3F6)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(6),
            itemCount: rows.length,
            itemBuilder: (context, i) => _buildRow(rows[i], searching),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_TreeRow row, bool searching) {
    switch (row.kind) {
      case _TreeRowKind.hq:
        return _nodeTile(
          key: 'hq',
          indent: 0,
          icon: LucideIcons.building2,
          iconColor: const Color(0xFF007AFF),
          label: '总部',
          onTap: () => widget.onSelect(const DistributionScope(
              key: 'hq', type: 'hq', scopeType: 'hq', scopeId: '0', name: '总部')),
        );
      case _TreeRowKind.group:
        final g = row.group!;
        final expanded = searching || _expandedGroupIds.contains(g.id);
        return _nodeTile(
          key: 'group-${g.id}',
          indent: 0,
          icon: LucideIcons.folderOpen,
          iconColor: const Color(0xFFF59E0B),
          label: g.name,
          count: row.count,
          expandIcon: expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
          onExpandTap: searching
              ? null
              : () => setState(() {
                    // 懒展开：仅展开时才把该组的网吧行插进列表
                    if (!_expandedGroupIds.remove(g.id)) {
                      _expandedGroupIds.add(g.id);
                    }
                  }),
          onTap: () {
            // 对齐 el-tree expand-on-click-node：点击分组同时切换展开
            if (!searching) {
              setState(() {
                if (!_expandedGroupIds.remove(g.id)) {
                  _expandedGroupIds.add(g.id);
                }
              });
            }
            widget.onSelect(DistributionScope(
              key: 'group-${g.id}',
              type: 'group',
              scopeType: 'group',
              scopeId: '${g.id}',
              name: g.name,
            ));
          },
        );
      case _TreeRowKind.merchant:
        final g = row.group!;
        final m = row.merchant!;
        // 复合 key：同一网吧在多分组下各有独立唯一 key（useDistributionTree.js:110-111）
        final key = 'group-${g.id}-merchant-${m.id}';
        return _nodeTile(
          key: key,
          indent: 22,
          icon: LucideIcons.monitor,
          iconColor: const Color(0xFF94A3B8),
          label: m.name,
          onTap: () => widget.onSelect(DistributionScope(
            key: key,
            type: 'merchant',
            scopeType: 'merchant',
            scopeId: '${m.id}',
            name: m.name,
          )),
        );
    }
  }

  Widget _nodeTile({
    required String key,
    required double indent,
    required IconData icon,
    required Color iconColor,
    required String label,
    int? count,
    IconData? expandIcon,
    VoidCallback? onExpandTap,
    required VoidCallback onTap,
  }) {
    final selected = widget.selectedKey == key;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: EdgeInsets.only(left: 6 + indent, right: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF007AFF).withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            if (expandIcon != null)
              GestureDetector(
                onTap: onExpandTap,
                child: Icon(expandIcon, size: 14, color: Colors.grey.shade400),
              )
            else
              const SizedBox(width: 14),
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: selected ? const Color(0xFF007AFF) : iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  color: selected ? const Color(0xFF007AFF) : const Color(0xFF374151),
                ),
              ),
            ),
            if (count != null && count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF007AFF).withValues(alpha: 0.16)
                      : const Color(0xFFEEF2F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: selected ? const Color(0xFF007AFF) : const Color(0xFF6B7280),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _TreeRowKind { hq, group, merchant }

class _TreeRow {
  final _TreeRowKind kind;
  final GroupBrief? group;
  final Netbar? merchant;
  final int count;

  const _TreeRow.hq()
      : kind = _TreeRowKind.hq,
        group = null,
        merchant = null,
        count = 0;
  const _TreeRow.group(GroupBrief this.group, this.count)
      : kind = _TreeRowKind.group,
        merchant = null;
  const _TreeRow.merchant(GroupBrief this.group, Netbar this.merchant)
      : kind = _TreeRowKind.merchant,
        count = 0;
}

/// 窄屏全屏树选择弹窗（手机端窗口型弹窗规范：ResponsiveDialogScaffold + showAdaptive）
class _ScopePickerDialog extends StatelessWidget {
  final List<GroupBrief> groups;
  final List<Netbar> merchants;
  final bool isHqUser;
  final String? selectedKey;

  const _ScopePickerDialog({
    required this.groups,
    required this.merchants,
    required this.isHqUser,
    this.selectedKey,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '选择下发目标',
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      maxWidth: 420,
      body: SizedBox(
        height: 520,
        child: ScopeTree(
          groups: groups,
          merchants: merchants,
          isHqUser: isHqUser,
          selectedKey: selectedKey,
          onSelect: (scope) => Navigator.of(context).pop(scope),
        ),
      ),
    );
  }
}
