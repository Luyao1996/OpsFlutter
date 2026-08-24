import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';

/// 权限组单选 + 所选组的权限点预览（对标 web RolePreview.vue）。
/// 成员只绑定一个权限组：为空表示不绑定，调用方此时不提交 role_ids[]。
class RoleGroupPicker extends ConsumerStatefulWidget {
  final List<RoleGroup> groups;
  final int? value;
  final ValueChanged<int?> onChanged;

  /// 附加提示（如"该成员当前绑定 N 个权限组，保存后将仅保留所选 1 个"）
  final String? notice;

  const RoleGroupPicker({
    super.key,
    required this.groups,
    required this.value,
    required this.onChanged,
    this.notice,
  });

  @override
  ConsumerState<RoleGroupPicker> createState() => _RoleGroupPickerState();
}

class _RoleGroupPickerState extends ConsumerState<RoleGroupPicker> {
  RoleGroup? _detail;
  bool _loading = false;

  /// 请求序号：快速切换权限组时，旧响应回来后直接丢弃，避免覆盖新选择的预览
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _loadDetail(widget.value);
  }

  @override
  void didUpdateWidget(RoleGroupPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _loadDetail(widget.value);
  }

  Future<void> _loadDetail(int? id) async {
    final my = ++_seq;
    if (id == null) {
      setState(() {
        _detail = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final detail = await ref.read(userApiProvider).getRoleDetail(id);
      if (!mounted || my != _seq) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _detail = null;
        _loading = false;
      });
      showTopNotice(context, '获取权限详情失败：$e', level: NoticeLevel.error);
    }
  }

  String get _selectedName {
    for (final g in widget.groups) {
      if (g.id == widget.value) return g.name;
    }
    return '';
  }

  List<PermissionObject> get _flatList =>
      (_detail?.permissions ?? const <PermissionObject>[])
          .where((p) => p.id > 0)
          .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown(),
        if (widget.notice != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.notice!,
            style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
          ),
        ],
        if (widget.value != null) ...[
          const SizedBox(height: 10),
          _buildPreview(),
        ],
      ],
    );
  }

  Widget _buildDropdown() {
    // 下拉里可能残留已被删除的权限组 id，找不到时回落到「不绑定」避免 assert
    final known = widget.groups.any((g) => g.id == widget.value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: known ? widget.value : null,
          isExpanded: true,
          hint: const Text('选择权限组', style: TextStyle(fontSize: 14)),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('不绑定', style: TextStyle(fontSize: 14, color: Colors.grey)),
            ),
            ...widget.groups.map(
              (g) => DropdownMenuItem<int?>(
                value: g.id,
                child: Text(g.name, style: const TextStyle(fontSize: 14)),
              ),
            ),
          ],
          onChanged: widget.onChanged,
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final list = _flatList;
    final byId = {for (final p in list) p.id: p};
    final roots = list
        .where((p) => p.parentId == 0 || !byId.containsKey(p.parentId))
        .toList();
    final childrenOf = <int, List<PermissionObject>>{};
    for (final p in list) {
      if (p.parentId != 0 && byId.containsKey(p.parentId) && p.parentId != p.id) {
        childrenOf.putIfAbsent(p.parentId, () => []).add(p);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.shieldCheck, size: 14, color: AppColors.iosBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_selectedName.isEmpty ? '权限组' : '$_selectedName '}权限预览',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_loading)
                const Text('加载中', style: TextStyle(fontSize: 12, color: Colors.grey))
              else if (list.isNotEmpty)
                Text('共 ${list.length} 项',
                    style: const TextStyle(fontSize: 12, color: AppColors.iosBlue)),
            ],
          ),
          const SizedBox(height: 8),
          if (roots.isEmpty)
            Text(
              _loading ? '正在获取权限详情...' : '该权限组暂无权限',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            )
          else
            for (final node in roots) _buildNode(node, childrenOf[node.id] ?? const []),
        ],
      ),
    );
  }

  Widget _buildNode(PermissionObject node, List<PermissionObject> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.shieldCheck, size: 13, color: AppColors.iosBlue),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  node.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.iosBlue),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text('${children.length}',
                    style: const TextStyle(fontSize: 11, color: AppColors.iosBlue)),
              ],
            ],
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 19, top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in children)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECF5FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFD9ECFF)),
                      ),
                      child: Text(
                        c.name,
                        style: const TextStyle(fontSize: 12, color: AppColors.iosBlue),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
