import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/user_api.dart';

/// 权限树数据 + 「UI 选中集合 ⇄ 提交集合」的转换（对标 web PermissionTree.vue）。
///
/// UI 选中集合只含「子权限 id」与「无子项模块自身 id」，父模块勾选态由子项派生；
/// 后端存的是父+子混合，所以提交前补父、回填时剔父，两个方向都在这里收口。
class PermissionTreeData {
  final List<PermissionNode> nodes;

  /// 树是否加载完成。未就绪时不允许保存，否则 expandWithParents 拿不到树会漏掉父 id
  final bool ready;

  const PermissionTreeData({this.nodes = const [], this.ready = false});

  /// 模块参与勾选的权限 id：有子项取子项，无子项取模块自身
  List<int> _modulePermIds(PermissionNode mod) =>
      mod.children.isNotEmpty ? mod.children.map((c) => c.id).toList() : [mod.id];

  /// 提交前：按当前已勾子权限补全所属父模块 id（业务约定：拥有子即拥有父）
  List<int> expandWithParents(Iterable<int> selected) {
    final childToParent = <int, int>{};
    for (final mod in nodes) {
      for (final c in mod.children) {
        childToParent[c.id] = mod.id;
      }
    }
    final result = <int>{};
    for (final id in selected) {
      result.add(id);
      final parentId = childToParent[id];
      if (parentId != null) result.add(parentId);
    }
    return result.toList();
  }

  /// 回填时：剔除「有子项的父模块 id」，父勾选态改由子项派生
  Set<int> normalizeParentSelections(Iterable<int> ids) {
    final parentWithChildren = nodes
        .where((mod) => mod.children.isNotEmpty)
        .map((mod) => mod.id)
        .toSet();
    return ids.where((id) => !parentWithChildren.contains(id)).toSet();
  }
}

/// 权限点勾选树：父模块一行（含三态勾选），子权限缩进多列平铺
class PermissionTree extends StatefulWidget {
  final PermissionTreeData data;

  /// UI 选中集合（只含子权限 id 与无子项模块 id）
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  /// 加载失败提示；非空时显示错误与「重试」
  final String? error;
  final VoidCallback? onRetry;

  const PermissionTree({
    super.key,
    required this.data,
    required this.selected,
    required this.onChanged,
    this.error,
    this.onRetry,
  });

  @override
  State<PermissionTree> createState() => _PermissionTreeState();
}

class _PermissionTreeState extends State<PermissionTree> {
  final Set<int> _expanded = {};
  bool _initialExpandDone = false;

  void _syncInitialExpand() {
    // 默认展开第一个模块，其余折叠（与 web 一致）
    if (_initialExpandDone || widget.data.nodes.isEmpty) return;
    _initialExpandDone = true;
    _expanded.add(widget.data.nodes.first.id);
  }

  List<int> _modulePermIds(PermissionNode mod) => widget.data._modulePermIds(mod);

  void _togglePerm(int id, bool checked) {
    final next = Set<int>.from(widget.selected);
    if (checked) {
      next.add(id);
    } else {
      next.remove(id);
    }
    widget.onChanged(next);
  }

  void _toggleModule(PermissionNode mod, bool checked) {
    final ids = _modulePermIds(mod);
    final next = Set<int>.from(widget.selected);
    if (checked) {
      next.addAll(ids);
    } else {
      next.removeAll(ids);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(widget.error!,
                  style: TextStyle(fontSize: 13, color: Colors.red.shade600)),
            ),
            if (widget.onRetry != null)
              TextButton(onPressed: widget.onRetry, child: const Text('重试')),
          ],
        ),
      );
    }

    if (!widget.data.ready) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('加载权限列表...', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    _syncInitialExpand();

    if (widget.data.nodes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('暂无可分配权限', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final mod in widget.data.nodes) _buildModule(mod),
        ],
      ),
    );
  }

  Widget _buildModule(PermissionNode mod) {
    final ids = _modulePermIds(mod);
    final checkedCount = ids.where(widget.selected.contains).length;
    final allChecked = checkedCount == ids.length && ids.isNotEmpty;
    final indeterminate = checkedCount > 0 && checkedCount < ids.length;
    final hasChildren = mod.children.isNotEmpty;
    final expanded = _expanded.contains(mod.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren
              ? () => setState(() {
                    if (expanded) {
                      _expanded.remove(mod.id);
                    } else {
                      _expanded.add(mod.id);
                    }
                  })
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: hasChildren
                      ? Icon(
                          expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                          size: 18,
                          color: Colors.grey.shade500,
                        )
                      : null,
                ),
                Checkbox(
                  // tristate 仅用于展示"部分选中"，点击时按全选/全不选二选一处理
                  tristate: true,
                  value: allChecked ? true : (indeterminate ? null : false),
                  activeColor: AppColors.iosBlue,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _toggleModule(mod, !allChecked),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mod.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasChildren)
                  Text(
                    '$checkedCount/${ids.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ),
        if (hasChildren && expanded)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 0,
              children: [
                for (final child in mod.children) _buildPermItem(child),
              ],
            ),
          ),
        Divider(height: 1, color: Colors.grey.shade100),
      ],
    );
  }

  Widget _buildPermItem(PermissionNode perm) {
    final checked = widget.selected.contains(perm.id);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: InkWell(
        onTap: () => _togglePerm(perm.id, !checked),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: checked,
              activeColor: AppColors.iosBlue,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _togglePerm(perm.id, v ?? false),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                perm.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
