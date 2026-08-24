import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/user_api.dart';
import 'permission_tree.dart';

/// 权限组设置（对标 web PermissionGroupDialog.vue）。
/// 入口权限由调用方控制：仅总部管理员可见。
class PermissionGroupDialog extends ConsumerStatefulWidget {
  /// 发生过增删改时回调，供调用方在弹窗被 X/返回键关闭时也能刷新列表
  final VoidCallback? onChanged;

  const PermissionGroupDialog({super.key, this.onChanged});

  @override
  ConsumerState<PermissionGroupDialog> createState() => _PermissionGroupDialogState();
}

class _PermissionGroupDialogState extends ConsumerState<PermissionGroupDialog> {
  List<RoleGroup> _list = [];
  bool _loading = true;
  String _keyword = '';
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<RoleGroup> get _filtered {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return _list;
    return _list.where((r) => r.name.toLowerCase().contains(kw)).toList();
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    try {
      final list = await ref.read(userApiProvider).getRoleList();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopNotice(context, '获取权限组失败：$e', level: NoticeLevel.error);
    }
  }

  void _markChanged() {
    _changed = true;
    widget.onChanged?.call();
  }

  /// 编辑必须先拿到详情再开窗：详情失败就只报错不开窗，
  /// 否则勾选态为空会被用户当成"该组没权限"直接保存，把权限清空。
  Future<void> _openEdit([RoleGroup? row]) async {
    RoleGroup? detail;
    if (row != null) {
      try {
        detail = await ref.read(userApiProvider).getRoleDetail(row.id);
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '获取权限组详情失败：$e', level: NoticeLevel.error);
        }
        return;
      }
      if (!mounted) return;
    }

    final saved = await showAdaptive<bool>(
      context,
      (_) => _RoleGroupEditDialog(initial: detail),
      routeName: '/dialog/permission-group-edit',
    );
    if (saved == true) {
      _markChanged();
      await _load();
    }
  }

  Future<void> _delete(RoleGroup row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: Text('确认删除权限组「${row.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(userApiProvider).deleteRole(row.id);
      if (!mounted) return;
      showTopNotice(context, '删除成功', level: NoticeLevel.success);
      _markChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '删除失败：$e', level: NoticeLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '权限组设置',
      maxWidth: 900,
      scrollableBody: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: _buildToolbar(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('暂无权限组',
                            style: TextStyle(fontSize: 13, color: Colors.grey)),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _buildRow(_filtered[i]),
                      ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_changed),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 40,
          child: TextField(
            onChanged: (v) => setState(() => _keyword = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索权限组名称',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
            ),
          ),
        ),
        Text(
          '共 ${_filtered.length} 个权限组',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        ElevatedButton.icon(
          onPressed: () => _openEdit(),
          icon: const Icon(LucideIcons.plus, size: 14),
          label: const Text('新增权限组', style: TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.iosBlue,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(RoleGroup row) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.isSystem) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Text(
                          '系统',
                          style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  row.description.isEmpty ? '—' : row.description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _openEdit(row),
            icon: const Icon(LucideIcons.edit2, size: 13),
            label: const Text('编辑', style: TextStyle(fontSize: 13)),
            style: TextButton.styleFrom(foregroundColor: AppColors.iosBlue),
          ),
          // 系统内置组不给删除入口（与 web 一致）
          if (!row.isSystem)
            TextButton.icon(
              onPressed: () => _delete(row),
              icon: const Icon(LucideIcons.trash2, size: 13),
              label: const Text('删除', style: TextStyle(fontSize: 13)),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
        ],
      ),
    );
  }
}

/// 新增 / 编辑权限组表单。编辑态的 [initial] 必须已带详情（平铺 permissions）。
class _RoleGroupEditDialog extends ConsumerStatefulWidget {
  final RoleGroup? initial;

  const _RoleGroupEditDialog({this.initial});

  @override
  ConsumerState<_RoleGroupEditDialog> createState() => _RoleGroupEditDialogState();
}

class _RoleGroupEditDialogState extends ConsumerState<_RoleGroupEditDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description ?? '');

  PermissionTreeData _tree = const PermissionTreeData();
  String? _treeError;
  Set<int> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 详情回填的是父+子混合 id，等树加载完再 normalize 掉父 id
    _selected = (widget.initial?.permissions ?? const [])
        .map((p) => p.id)
        .where((id) => id > 0)
        .toSet();
    _loadTree();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadTree() async {
    setState(() {
      _tree = const PermissionTreeData();
      _treeError = null;
    });
    try {
      final nodes = await ref.read(userApiProvider).getRolePermissionTree();
      if (!mounted) return;
      final data = PermissionTreeData(nodes: nodes, ready: true);
      setState(() {
        _tree = data;
        _selected = data.normalizeParentSelections(_selected);
      });
    } catch (e) {
      if (!mounted) return;
      // 保持 ready=false：树没拿到就保存会漏掉父模块 id，宁可禁用保存让用户重试
      setState(() => _treeError = '获取权限列表失败：$e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      showTopNotice(context, '请输入权限组名称', level: NoticeLevel.warning);
      return;
    }
    if (!_tree.ready) {
      showTopNotice(context, '权限列表加载中，请稍后再试', level: NoticeLevel.warning);
      return;
    }

    // 提交时把被勾子权限的父模块 id 一起带上（业务约定：拥有子即拥有父）
    final permissionIds = _tree.expandWithParents(_selected);
    final description = _description.text.trim();
    final id = widget.initial?.id;

    setState(() => _saving = true);
    try {
      final api = ref.read(userApiProvider);
      if (id != null) {
        await api.updateRole(id,
            name: name, description: description, permissionIds: permissionIds);
      } else {
        await api.createRole(
            name: name, description: description, permissionIds: permissionIds);
      }
      if (!mounted) return;
      showTopNotice(context, id != null ? '修改成功' : '新增成功', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: widget.initial != null ? '编辑权限组' : '新增权限组',
      maxWidth: 820,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('权限组名称', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          _buildField(_name, '请输入名称', maxLength: 20),
          const SizedBox(height: 16),
          const Text('权限描述', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          _buildField(_description, '可选', maxLength: 100, maxLines: 2),
          const SizedBox(height: 16),
          const Text('权限', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          PermissionTree(
            data: _tree,
            selected: _selected,
            onChanged: (ids) => setState(() => _selected = ids),
            error: _treeError,
            onRetry: _loadTree,
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            // 权限树未就绪禁用保存，避免 expandWithParents 漏掉父模块 id
            onPressed: (_saving || !_tree.ready) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String hint, {
    int? maxLength,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        counterText: '',
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
        ),
      ),
    );
  }
}
