import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/user_api.dart';
import 'merchant_transfer.dart';

/// 业主权限分组ID（对标 Vue 端 UserPage.vue 第 625 行）
const int _ownerGroupId = 21;
/// 分组21允许的角色名称（对标 Vue 端第 628 行）
const List<String> _allowedRolesForOwner = ['网吧管理'];
/// 分组21允许的权限名称（对标 Vue 端第 631 行）
const List<String> _allowedPermissionsForOwner = ['远程/唤醒'];

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
  List<int> _selectedPermissionIds = [];
  List<int> _selectedMerchantIds = [];
  List<Role> _roleList = [];
  List<PermissionObject> _permissionList = [];
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

  /// 当前选中分组是否为业主权限分组（对标 Vue 端 isGroup21 computed）
  bool get _isOwnerGroup => _selectedGroupId == _ownerGroupId;

  /// 判断角色是否在业主白名单中（对标 Vue 端 isAllowedRole）
  bool _isAllowedRole(String roleName) =>
      _allowedRolesForOwner.contains(roleName);

  /// 判断权限是否在业主白名单中（对标 Vue 端 isAllowedPermission）
  bool _isAllowedPermission(String permName) =>
      _allowedPermissionsForOwner.contains(permName);

  /// 获取白名单角色的ID列表（对标 Vue 端 getAllowedRoleIds）
  List<int> get _allowedRoleIds =>
      _roleList.where((r) => _allowedRolesForOwner.contains(r.name)).map((r) => r.id).toList();

  /// 获取白名单权限的ID列表（对标 Vue 端 getAllowedPermissionIds）
  List<int> get _allowedPermissionIds =>
      _permissionList.where((p) => _allowedPermissionsForOwner.contains(p.name)).map((p) => p.id).toList();

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
      final result = await api.getRoleAndPermissionList();
      if (!mounted) return;
      setState(() {
        _roleList = result.roles;
        _permissionList = result.permissions;
        _loadingRoles = false;
        // 初始化默认选中（对标 Vue 端 openMemberModal 第 690-720 行）
        if (_isOwnerGroup) {
          _selectedRoleIds = _allowedRoleIds;
          _selectedPermissionIds = _allowedPermissionIds;
          _isManager = false;
        } else {
          _selectedRoleIds = _roleList.map((r) => r.id).toList();
          _selectedPermissionIds = _permissionList.map((p) => p.id).toList();
        }
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

  /// 分组切换处理（对标 Vue 端 watch(() => memberForm.group_id) 第 658-681 行）
  void _onGroupChanged(int? newGroupId) {
    final oldGroupId = _selectedGroupId;
    setState(() {
      _selectedGroupId = newGroupId;
      if (oldGroupId == _ownerGroupId && newGroupId != _ownerGroupId) {
        // 从分组21切换到其他分组：全选角色和权限
        _selectedRoleIds = _roleList.map((r) => r.id).toList();
        _selectedPermissionIds = _permissionList.map((p) => p.id).toList();
      } else if (newGroupId == _ownerGroupId) {
        // 切换到分组21：过滤只保留允许的
        _selectedRoleIds = _selectedRoleIds.where((id) => _allowedRoleIds.contains(id)).toList();
        _selectedPermissionIds = _selectedPermissionIds.where((id) => _allowedPermissionIds.contains(id)).toList();
        _isManager = false;
      }
    });
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

    // 分组21的特殊权限处理（对标 Vue 端 saveMember 第 858-870 行）
    List<int> finalRoleIds = List.from(_selectedRoleIds);
    List<int> finalPermissionIds = List.from(_selectedPermissionIds);
    if (_isOwnerGroup) {
      finalRoleIds = finalRoleIds.where((id) => _allowedRoleIds.contains(id)).toList();
      finalPermissionIds = finalPermissionIds.where((id) => _allowedPermissionIds.contains(id)).toList();
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
        roleIds: finalRoleIds.isNotEmpty ? finalRoleIds : null,
        permissionIds: finalPermissionIds.isNotEmpty ? finalPermissionIds : null,
        merchantIds: _selectedMerchantIds,
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
    return ResponsiveDialogScaffold(
      title: '添加成员',
      maxWidth: 760,
      body: _buildForm(),
      footer: _buildFooter(),
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
              // 管理员开关（对标 Vue 端 :disabled="isGroup21"）
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('设为管理员', style: TextStyle(fontSize: 14)),
                  Switch.adaptive(
                    value: _isManager,
                    activeColor: AppColors.iosBlue,
                    onChanged: _isOwnerGroup ? null : (v) => setState(() => _isManager = v),
                  ),
                ],
              ),
              // 角色分配（对标 Vue 端 :disabled="isGroup21 && !isAllowedRole(role.name)"）
              if (_roleList.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  '角色分配',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _roleList.map((role) {
                    final selected = _selectedRoleIds.contains(role.id);
                    final disabled = _isOwnerGroup && !_isAllowedRole(role.name);
                    return FilterChip(
                      label: Text(role.name),
                      selected: selected,
                      onSelected: disabled ? null : (v) {
                        setState(() {
                          if (v) {
                            _selectedRoleIds.add(role.id);
                          } else {
                            _selectedRoleIds.remove(role.id);
                          }
                        });
                      },
                      selectedColor: disabled ? Colors.grey.shade200 : AppColors.iosBlue.withOpacity(0.15),
                      checkmarkColor: disabled ? Colors.grey : AppColors.iosBlue,
                      backgroundColor: disabled ? Colors.grey.shade100 : null,
                    );
                  }).toList(),
                ),
              ],
              // 细分权限（对标 Vue 端 groupedPermissions，按 parent_id 分组展示）
              if (_permissionList.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  '细分权限',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ..._buildGroupedPermissions(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 可控网吧（对标 Vue 端 UserPage.vue 第 263-339 行的穿梭框）
        _buildLabel('可控网吧'),
        const SizedBox(height: 6),
        MerchantTransfer(
          selectedIds: _selectedMerchantIds,
          onChanged: (ids) => setState(() => _selectedMerchantIds = ids),
        ),
      ],
    );
  }

  /// 按 parent_id 分组展示权限（对标 Vue 端 groupedPermissions computed）
  List<Widget> _buildGroupedPermissions() {
    // 构建角色ID→名称映射
    final roleMap = <int, String>{};
    for (final r in _roleList) {
      roleMap[r.id] = r.name;
    }

    // 按 parent_id 分组
    final groups = <int, List<PermissionObject>>{};
    for (final p in _permissionList) {
      groups.putIfAbsent(p.parentId, () => []).add(p);
    }

    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      final groupName = roleMap[entry.key] ?? '其他';
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(groupName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
      ));
      widgets.add(Wrap(
        spacing: 8,
        runSpacing: 8,
        children: entry.value.map((perm) {
          final selected = _selectedPermissionIds.contains(perm.id);
          final disabled = _isOwnerGroup && !_isAllowedPermission(perm.name);
          return FilterChip(
            label: Text(perm.name),
            selected: selected,
            onSelected: disabled ? null : (v) {
              setState(() {
                if (v) {
                  _selectedPermissionIds.add(perm.id);
                } else {
                  _selectedPermissionIds.remove(perm.id);
                }
              });
            },
            selectedColor: disabled ? Colors.grey.shade200 : AppColors.iosBlue.withOpacity(0.15),
            checkmarkColor: disabled ? Colors.grey : AppColors.iosBlue,
            backgroundColor: disabled ? Colors.grey.shade100 : null,
          );
        }).toList(),
      ));
    }
    return widgets;
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
          onChanged: _onGroupChanged,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
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
    );
  }
}
