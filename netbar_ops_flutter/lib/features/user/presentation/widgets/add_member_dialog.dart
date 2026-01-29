import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';

class AddMemberDialog extends ConsumerStatefulWidget {
  final List<UserGroup> groups;
  final int? initialGroupId;

  const AddMemberDialog({
    super.key,
    required this.groups,
    this.initialGroupId,
  });

  @override
  ConsumerState<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<AddMemberDialog> {
  int? _selectedGroupId;
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _passwordVisible = true;
  bool _isManager = false;
  List<int> _selectedRoleIds = [];
  List<Role> _roleList = [];
  bool _creating = false;
  bool _loadingRoles = true;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId ??
        (widget.groups.isNotEmpty ? widget.groups.first.id : null);
    _password.text = _generatePassword();
    _loadRoles();
  }

  bool get _isSuperAdmin {
    final auth = ref.read(authNotifierProvider);
    return auth.user?.isTopManager == true;
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final api = ref.read(userApiProvider);
      final roles = await api.getRoleList();
      if (!mounted) return;
      setState(() {
        _roleList = roles;
        _loadingRoles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
    }
  }

  String _generatePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _handleCreate() async {
    final username = _username.text.trim();
    final name = _name.text.trim();
    final password = _password.text.trim();

    if (username.isEmpty) {
      showTopNotice(context, '请输入账号', level: NoticeLevel.warning);
      return;
    }
    if (name.isEmpty) {
      showTopNotice(context, '请输入昵称', level: NoticeLevel.warning);
      return;
    }
    if (password.isEmpty || password.length < 6) {
      showTopNotice(context, '密码长度至少6位', level: NoticeLevel.warning);
      return;
    }

    setState(() => _creating = true);
    try {
      final api = ref.read(userApiProvider);
      await api.create(
        username: username,
        password: password,
        nickname: name,
        groupId: _selectedGroupId,
        isManager: _isManager,
        roleIds: _selectedRoleIds.isNotEmpty ? _selectedRoleIds : null,
      );
      if (!mounted) return;
      showTopNotice(context, '用户创建成功', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '创建失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _creating = false);
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
          const Icon(LucideIcons.userPlus, size: 20, color: AppColors.iosBlue),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '添加成员',
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
          controller: _name,
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
        _buildPasswordField(),
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
  }) {
    return TextField(
      controller: controller,
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

  Widget _buildPasswordField() {
    return TextField(
      controller: _password,
      obscureText: !_passwordVisible,
      decoration: InputDecoration(
        hintText: '设置登录密码',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(LucideIcons.lock, size: 18, color: Colors.grey.shade400),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(
                _passwordVisible ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 18,
                color: Colors.grey.shade400,
              ),
              splashRadius: 18,
            ),
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _password.text));
                showTopNotice(context, '密码已复制', level: NoticeLevel.success);
              },
              icon: Icon(LucideIcons.copy, size: 18, color: Colors.grey.shade400),
              splashRadius: 18,
              tooltip: '复制密码',
            ),
            IconButton(
              onPressed: () => setState(() => _password.text = _generatePassword()),
              icon: Icon(LucideIcons.refreshCw, size: 18, color: Colors.grey.shade400),
              splashRadius: 18,
              tooltip: '重新生成',
            ),
          ],
        ),
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
      style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
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
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _creating ? null : _handleCreate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确认添加'),
          ),
        ],
      ),
    );
  }
}
