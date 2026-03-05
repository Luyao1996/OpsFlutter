import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';

class EditUserDialog extends ConsumerStatefulWidget {
  final User user;
  final List<UserGroup> groups;

  const EditUserDialog({
    super.key,
    required this.user,
    required this.groups,
  });

  @override
  ConsumerState<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends ConsumerState<EditUserDialog> {
  late TextEditingController _nickname;
  late TextEditingController _username;
  late TextEditingController _password;
  late int? _selectedGroupId;
  late bool _isManager;
  List<int> _selectedRoleIds = [];
  List<Role> _roleList = [];
  bool _saving = false;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.user.nickname);
    _username = TextEditingController(text: widget.user.username);
    _password = TextEditingController();
    _selectedGroupId = widget.user.groupId;
    _isManager = widget.user.isManager;
    _loadUserDetails();
  }

  bool get _isSuperAdmin {
    final auth = ref.read(authNotifierProvider);
    return auth.user?.isTopManager == true;
  }

  @override
  void dispose() {
    _nickname.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadUserDetails() async {
    setState(() => _loadingUser = true);
    try {
      final api = ref.read(userApiProvider);
      // 加载角色列表
      final roles = await api.getRoleList();
      // 加载用户详情（包含 roles）
      final user = await api.getById(widget.user.id);
      if (!mounted) return;
      setState(() {
        _roleList = roles;
        _nickname.text = user.nickname;
        _username.text = user.username;
        _selectedGroupId = user.groupId;
        _isManager = user.isManager;
        // 直接使用用户详情中解析好的 roleIds
        _selectedRoleIds = List<int>.from(user.roleIds);
        _loadingUser = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUser = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final nickname = _nickname.text.trim();
    final username = _username.text.trim();
    final password = _password.text.trim();

    if (nickname.isEmpty) {
      showTopNotice(context, '请输入昵称', level: NoticeLevel.warning);
      return;
    }
    if (username.isEmpty) {
      showTopNotice(context, '请输入账号', level: NoticeLevel.warning);
      return;
    }
    if (password.isNotEmpty && password.length < 6) {
      showTopNotice(context, '密码长度至少6位', level: NoticeLevel.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      final api = ref.read(userApiProvider);
      await api.update(
        widget.user.id,
        nickname: nickname,
        username: username,
        password: password.isNotEmpty ? password : null,
        groupId: _selectedGroupId,
        isManager: _isManager,
        roleIds: _selectedRoleIds.isNotEmpty ? _selectedRoleIds : null,
      );
      if (!mounted) return;
      showTopNotice(context, '保存成功', level: NoticeLevel.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除成员'),
        content: Text('确定要删除成员 "${widget.user.nickname}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
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
      final api = ref.read(userApiProvider);
      await api.delete(widget.user.id);
      if (!mounted) return;
      showTopNotice(context, '删除成功', level: NoticeLevel.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '删除失败：$e', level: NoticeLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow;
    final dialogWidth = isNarrow ? MediaQuery.of(context).size.width * 0.95 : 500.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            if (_loadingUser)
              const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildForm(),
                ),
              ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.userCog, size: 20, color: AppColors.iosBlue),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '编辑成员',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, size: 18),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 昵称
        _buildLabel('昵称'),
        const SizedBox(height: 6),
        _buildTextField(
          controller: _nickname,
          hint: '显示名称',
          icon: LucideIcons.user,
        ),
        const SizedBox(height: 16),

        // 账号
        _buildLabel('账号'),
        const SizedBox(height: 6),
        _buildTextField(
          controller: _username,
          hint: '登录账号',
          icon: LucideIcons.atSign,
        ),
        const SizedBox(height: 16),

        // 密码
        _buildLabel('密码'),
        const SizedBox(height: 6),
        _buildTextField(
          controller: _password,
          hint: '不修改请留空',
          icon: LucideIcons.lock,
          obscureText: true,
        ),
        const SizedBox(height: 16),

        // 所属分组
        _buildLabel('所属分组'),
        const SizedBox(height: 6),
        _buildGroupDropdown(),
        const SizedBox(height: 16),

        // 权限设置
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '权限设置',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('设为管理员', style: TextStyle(fontSize: 14)),
                  Switch.adaptive(
                    value: _isManager,
                    activeColor: AppColors.iosBlue,
                    onChanged: (v) => setState(() => _isManager = v),
                  ),
                ],
              ),
              if (_roleList.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  '权限分配',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _roleList.map((role) {
                    final selected = _selectedRoleIds.contains(role.id);
                    return FilterChip(
                      label: Text(role.name),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedRoleIds.add(role.id);
                          } else {
                            _selectedRoleIds.remove(role.id);
                          }
                        });
                      },
                      selectedColor: AppColors.iosBlue.withOpacity(0.15),
                      checkmarkColor: AppColors.iosBlue,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade400),
        filled: true,
        fillColor: Colors.grey.shade50,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildGroupDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedGroupId,
          isExpanded: true,
          hint: const Text('选择分组'),
          items: widget.groups.map((g) {
            return DropdownMenuItem(value: g.id, child: Text(g.name));
          }).toList(),
          onChanged: (v) => setState(() => _selectedGroupId = v),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _delete,
            icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
            tooltip: '删除成员',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('保存修改'),
          ),
        ],
      ),
    );
  }
}
