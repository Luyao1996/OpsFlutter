import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/user_api.dart';
import '../../data/user_mock_data.dart';

class AddUserDialog extends ConsumerStatefulWidget {
  final User? initialUser;
  final List<UserGroup> groups;
  final int? initialGroupId;

  const AddUserDialog({
    super.key,
    this.initialUser,
    required this.groups,
    this.initialGroupId,
  });

  @override
  ConsumerState<AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<AddUserDialog> {
  late TextEditingController _nicknameController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  int? _selectedGroupId;
  List<UserRole> _selectedRoles = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.initialUser?.nickname ?? '');
    _usernameController = TextEditingController(text: widget.initialUser?.username ?? '');
    _passwordController = TextEditingController();

    int? initialId = widget.initialUser?.groupId ?? widget.initialGroupId;
    if (initialId == 0 || (initialId != null && !widget.groups.any((g) => g.id == initialId))) {
      initialId = null;
    }
    _selectedGroupId = initialId ?? (widget.groups.isNotEmpty ? widget.groups.first.id : null);

    if (widget.initialUser != null) {
      _selectedRoles = List.from(widget.initialUser!.roles);
    } else {
      _selectedRoles = [UserRole.user];
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleRole(UserRole role) {
    setState(() {
      // 单选角色
      _selectedRoles = [role];
    });
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    final isEditing = widget.initialUser != null;
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final nickname = _nicknameController.text.trim();
    final selectedRole = _selectedRoles.isNotEmpty ? _selectedRoles.first : UserRole.user;

    if (username.isEmpty) {
      _showError('账号不能为空');
      return;
    }
    if (!isEditing && password.isEmpty) {
      _showError('请填写密码');
      return;
    }
    if (password.isNotEmpty && password.length < 6) {
      _showError('密码长度至少 6 位');
      return;
    }

    setState(() => _saving = true);
    final api = ref.read(userApiProvider);
    try {
      if (isEditing) {
        await api.update(widget.initialUser!.id, {
          if (nickname.isNotEmpty) 'name': nickname,
          'role': selectedRole == UserRole.admin ? 'admin' : 'user',
          'group_id': _selectedGroupId,
          if (password.isNotEmpty) 'password': password,
        });
      } else {
        await api.create(
          username: username,
          password: password,
          name: nickname.isNotEmpty ? nickname : null,
          role: selectedRole == UserRole.admin ? 'admin' : 'user',
          groupId: _selectedGroupId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    if (widget.initialUser == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除用户 ${widget.initialUser!.nickname} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(userApiProvider).delete(widget.initialUser!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showError('删除失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialUser != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Sharper corners like Vue
      child: Container(
        width: 500, // Slightly wider to match Vue
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? '编辑成员信息' : '添加成员',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(LucideIcons.x, size: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField('昵称', _nicknameController),
                  const SizedBox(height: 16),
                  _buildTextField('账号', _usernameController, enabled: !isEditing),
                  const SizedBox(height: 16),
                  _buildTextField('密码', _passwordController, hint: isEditing ? '不修改请留空' : null),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    '分组',
                    _selectedGroupId,
                    widget.groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                    (v) => setState(() => _selectedGroupId = v),
                  ),
                  const SizedBox(height: 16),
                  
                  // Roles (Checkbox Grid)
                  const Text('管理员/角色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 32, // Fixed height for checkbox rows
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: UserRole.values.length,
                    itemBuilder: (context, index) {
                      final role = UserRole.values[index];
                      final isChecked = _selectedRoles.contains(role);
                      return InkWell(
                        onTap: () => _toggleRole(role),
                        child: Row(
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: isChecked ? AppColors.iosBlue : Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isChecked ? AppColors.iosBlue : Colors.grey.shade300,
                                ),
                              ),
                              child: isChecked 
                                ? const Icon(LucideIcons.check, size: 12, color: Colors.white) 
                                : null,
                            ),
                            const SizedBox(width: 8),
                            Text(roleLabels[role]!, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (isEditing)
                    TextButton.icon(
                      onPressed: _saving ? null : _handleDelete,
                      icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.red),
                      label: const Text('删除成员', style: TextStyle(color: AppColors.red)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildTextField(String label, TextEditingController controller, {String? hint, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: label == '密码',
          decoration: InputDecoration(
            hintText: hint ?? '请输入$label',
            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: AppColors.iosBlue, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, int? value, List<DropdownMenuItem<int>> items, ValueChanged<int?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: value,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
