import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';
import '../../data/user_mock_data.dart';

class EditUserDialog extends ConsumerStatefulWidget {
  final User user;
  final int? netbarId;
  final int? groupId;

  const EditUserDialog({
    super.key,
    required this.user,
    this.netbarId,
    this.groupId,
  });

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  late final TextEditingController _name;
  late UserRole _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.nickname);
    _role = widget.user.roles.contains(UserRole.admin) ? UserRole.admin : UserRole.user;
  }

  bool get _isSuperAdmin {
    final auth = ref.read(authNotifierProvider);
    final role = (auth.user?.role ?? '').toLowerCase();
    return role == 'super_admin' || (auth.user?.username == 'admin');
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(userApiProvider).update(widget.user.id, {
        'name': _name.text.trim(),
        'role': _role == UserRole.admin ? 'admin' : 'user',
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      showTopNotice(context, '保存失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除用户 ${widget.user.nickname} 吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(userApiProvider).delete(widget.user.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      showTopNotice(context, '删除失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置密码'),
        content: const Text('将为该用户生成随机新密码，并且仅本窗口可见。是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.iosBlue, foregroundColor: Colors.white),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final pwd = await ref.read(userApiProvider).resetPassword(widget.user.id);
      if (!mounted) return;
      await _showPasswordOnce(pwd);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '重置失败：$e', level: NoticeLevel.error);
    }
  }

  Future<void> _removeFromGroup() async {
    if (_saving) return;
    final netbarId = widget.netbarId ?? ref.read(currentNetbarProvider).id;
    final groupId = widget.groupId;
    if (netbarId == null || groupId == null || groupId <= 0) {
      showTopNotice(context, '当前未选择分组', level: NoticeLevel.warning);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移出分组'),
        content: Text('确定将用户 ${widget.user.nickname} 移出当前分组吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(netbarUserGroupApiProvider).removeUserFromGroup(netbarId, groupId, widget.user.id);
      if (!mounted) return;
      showTopNotice(context, '已移出分组', level: NoticeLevel.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '移出失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showPasswordOnce(String password) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新密码仅本窗口可见，请及时复制保存。'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: password));
                      if (context.mounted) showTopNotice(context, '已复制', level: NoticeLevel.success);
                    },
                    icon: const Icon(LucideIcons.copy, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 420;
    final canRemoveFromGroup = widget.groupId != null && widget.groupId! > 0;
    final inSelectedGroup = canRemoveFromGroup && widget.user.netbarGroupIds.contains(widget.groupId);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('编辑用户', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: widget.user.username,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '账号',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: '昵称',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('角色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('普通用户'),
                        selected: _role == UserRole.user,
                        onSelected: (_) => setState(() => _role = UserRole.user),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('管理员'),
                        selected: _role == UserRole.admin,
                        onSelected: (_) => setState(() => _role = UserRole.admin),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isCompact)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _resetPassword,
                          icon: const Icon(LucideIcons.keyRound, size: 16),
                          label: const Text('重置密码'),
                        ),
                        if (canRemoveFromGroup)
                          OutlinedButton.icon(
                            onPressed: (_saving || !inSelectedGroup) ? null : _removeFromGroup,
                            icon: const Icon(Icons.group_remove_outlined, size: 16),
                            label: const Text('移出分组'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                            ),
                          ),
                        if (_isSuperAdmin)
                          TextButton.icon(
                            onPressed: _saving ? null : _delete,
                            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                            label: const Text('删除用户', style: TextStyle(color: Colors.red)),
                          ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _resetPassword,
                          icon: const Icon(LucideIcons.keyRound, size: 16),
                          label: const Text('重置密码'),
                        ),
                        const SizedBox(width: 8),
                        if (canRemoveFromGroup)
                          OutlinedButton.icon(
                            onPressed: (_saving || !inSelectedGroup) ? null : _removeFromGroup,
                            icon: const Icon(Icons.group_remove_outlined, size: 16),
                            label: const Text('移出分组'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                            ),
                          ),
                        const Spacer(),
                        if (_isSuperAdmin)
                          TextButton.icon(
                            onPressed: _saving ? null : _delete,
                            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
                            label: const Text('删除用户', style: TextStyle(color: Colors.red)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('取消')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_saving ? '保存中...' : '保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
