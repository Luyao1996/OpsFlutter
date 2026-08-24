import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';
import 'merchant_transfer.dart';
import 'role_group_picker.dart';

/// 业主权限分组ID：该分组不允许设为管理员（对标 web MemberDialog OWNER_GROUP_ID）
const int _ownerGroupId = 21;

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
  List<int> _selectedMerchantIds = [];
  /// 权限组：单选，null = 不绑定（不提交 role_ids[]）
  int? _selectedRoleGroupId;
  /// 该成员原本绑定的权限组数量，>1 时提示保存后只保留所选 1 个
  int _boundRoleGroupCount = 0;
  /// 角色标签 role_tag，null = 不提交（编辑态回填原值，避免更新时被抹掉）
  int? _roleTag;
  /// 角色标签字典：优先用 getUser 响应里的 roleMap，缺省回退兜底常量
  Map<int, String> _roleTagLabels = kDefaultRoleTagLabels;
  List<RoleGroup> _roleGroups = [];
  bool _saving = false;
  bool _loadingUser = true;
  List<UserApiToken> _tokens = [];
  bool _tokensLoading = true;
  bool _tokenCreating = false;
  // 正在改名/启停/删除的 Token id，用于逐条禁用交互并显示 loading
  final Set<int> _busyTokenIds = {};

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(text: widget.user.nickname);
    _username = TextEditingController(text: widget.user.username);
    _password = TextEditingController();
    _selectedGroupId = widget.user.groupId;
    _isManager = widget.user.isManager;
    _loadUserDetails();
    _loadTokens();
  }

  bool get _isSuperAdmin {
    final auth = ref.read(authNotifierProvider);
    return auth.user?.isTopManager == true;
  }

  /// 业主分组：禁用「设为管理员」（对标 web isOwnerGroup）
  bool get _isOwnerGroup => _selectedGroupId == _ownerGroupId;

  @override
  void dispose() {
    _nickname.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  /// 加载权限组列表 + 用户详情（对标 web MemberDialog 打开流程）
  Future<void> _loadUserDetails() async {
    setState(() => _loadingUser = true);
    try {
      final api = ref.read(userApiProvider);
      // 每次打开都刷新权限组列表，保证能看到「权限组设置」里刚新增的项
      final groups = await api.getRoleList();
      final detail = await api.getDetail(widget.user.id);
      if (!mounted) return;

      final user = detail.user;
      setState(() {
        _roleGroups = groups;
        _nickname.text = user.nickname;
        _username.text = user.username;
        _selectedGroupId = user.groupId ?? widget.user.groupId;
        _isManager = user.isManager;
        // 权限组单选：回填第一个，多绑定时由 UI 提示保存后只保留 1 个
        _boundRoleGroupCount = user.roleObjects.length;
        _selectedRoleGroupId =
            user.roleObjects.isNotEmpty ? user.roleObjects.first.id : null;
        _roleTag = user.roleTag;
        if (detail.roleTagLabels.isNotEmpty) _roleTagLabels = detail.roleTagLabels;
        _selectedMerchantIds = List<int>.from(user.merchantIds);
        _loadingUser = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUser = false);
      showTopNotice(context, '获取成员信息失败：$e', level: NoticeLevel.error);
    }
  }

  /// 分组切换：业主分组强制取消管理员（其余联动已随权限组改造下线）
  void _onGroupChanged(int? newGroupId) {
    setState(() {
      _selectedGroupId = newGroupId;
      if (newGroupId == _ownerGroupId) _isManager = false;
    });
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
        roleId: _selectedRoleGroupId,
        // 透传原值：role_tag 为空时不提交，避免更新时把已有标签抹掉
        roleTag: _roleTag,
        merchantIds: _selectedMerchantIds,
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

  // ===== API Token：查询 / 创建 / 改名 / 启停 / 删除 =====

  Future<void> _loadTokens() async {
    if (!_tokensLoading) setState(() => _tokensLoading = true);
    try {
      final list = await ref.read(userApiProvider).getUserApiTokens(widget.user.id);
      if (!mounted) return;
      setState(() {
        _tokens = list;
        _tokensLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _tokensLoading = false);
      showTopNotice(context, '获取 Token 列表失败：$e', level: NoticeLevel.error);
    }
  }

  Future<void> _copyToken(UserApiToken t) async {
    if (t.token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t.token));
    if (!mounted) return;
    showTopNotice(context, 'Token 已复制到剪贴板', level: NoticeLevel.success);
  }

  Future<void> _createToken() async {
    final name = await showAdaptive<String>(
      context,
      (_) => const _TokenNameDialog(
        title: '新增 API Token',
        description: '请输入 Token 名称（用于区分用途，例如：对接系统A）',
        confirmText: '创建',
      ),
      routeName: '/dialog/api-token-name',
    );
    if (name == null || !mounted) return;
    setState(() => _tokenCreating = true);
    try {
      await ref.read(userApiProvider).createUserApiToken(widget.user.id, name: name);
      if (!mounted) return;
      showTopNotice(context, 'Token 创建成功', level: NoticeLevel.success);
      await _loadTokens();
    } catch (e) {
      if (mounted) showTopNotice(context, '创建失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _tokenCreating = false);
    }
  }

  Future<void> _renameToken(UserApiToken t) async {
    final name = await showAdaptive<String>(
      context,
      (_) => _TokenNameDialog(
        title: '修改 Token 名称',
        description: '请输入新的 Token 名称',
        confirmText: '保存',
        initialValue: t.name,
      ),
      routeName: '/dialog/api-token-name',
    );
    if (name == null || !mounted) return;
    setState(() => _busyTokenIds.add(t.id));
    try {
      await ref.read(userApiProvider).updateUserApiToken(widget.user.id, t.id, name: name);
      if (!mounted) return;
      showTopNotice(context, '修改成功', level: NoticeLevel.success);
      await _loadTokens();
    } catch (e) {
      if (mounted) showTopNotice(context, '修改失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _busyTokenIds.remove(t.id));
    }
  }

  Future<void> _toggleToken(UserApiToken t, bool enabled) async {
    setState(() => _busyTokenIds.add(t.id));
    try {
      await ref.read(userApiProvider).updateUserApiToken(widget.user.id, t.id, isEnabled: enabled);
      if (!mounted) return;
      showTopNotice(context, enabled ? '已启用' : '已停用', level: NoticeLevel.success);
      await _loadTokens();
    } catch (e) {
      // 失败不本地翻转开关，直接按服务端实际状态重拉，避免 UI 与后端不一致
      if (mounted) {
        showTopNotice(context, '操作失败：$e', level: NoticeLevel.error);
        await _loadTokens();
      }
    } finally {
      if (mounted) setState(() => _busyTokenIds.remove(t.id));
    }
  }

  Future<void> _deleteToken(UserApiToken t) async {
    final displayName = t.name.isEmpty ? '未命名 Token' : t.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Token'),
        content: Text('确认删除 Token「$displayName」？删除后使用该 Token 的调用将立即失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyTokenIds.add(t.id));
    try {
      await ref.read(userApiProvider).deleteUserApiToken(widget.user.id, t.id);
      if (!mounted) return;
      showTopNotice(context, '删除成功', level: NoticeLevel.success);
      await _loadTokens();
    } catch (e) {
      if (mounted) showTopNotice(context, '删除失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _busyTokenIds.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '编辑成员',
      maxWidth: 760,
      scrollableBody: !_loadingUser,
      bodyPadding: const EdgeInsets.all(20),
      body: _loadingUser
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildForm(),
      footer: _loadingUser ? null : _buildFooter(),
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

        // 角色标签（对标 Vue 端 MemberDialog 角色标签单选区）
        _buildRoleTagSection(),
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
              // 管理员开关（业主分组禁用并强制 false）
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
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              RoleGroupPicker(
                groups: _roleGroups,
                value: _selectedRoleGroupId,
                onChanged: (id) => setState(() => _selectedRoleGroupId = id),
                notice: _boundRoleGroupCount > 1
                    ? '该成员当前绑定 $_boundRoleGroupCount 个权限组，保存后将仅保留所选 1 个'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // API Token（对标 Vue 端 MemberDialog.vue，仅编辑态提供）
        _buildTokenSection(),
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

  /// API Token 区块。后端限制每个会员同时只能有一条 Token，
  /// 因此列表非空时不给「新增 Token」入口（与 Web 端一致）。
  Widget _buildTokenSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'API Token',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              if (!_tokensLoading && _tokens.isEmpty)
                TextButton.icon(
                  onPressed: _tokenCreating ? null : _createToken,
                  icon: _tokenCreating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.plus, size: 14),
                  label: const Text('新增 Token'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.iosBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                ),
            ],
          ),
          if (_tokensLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('加载中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else if (_tokens.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('该成员暂无 API Token',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            )
          else
            for (final t in _tokens) _buildTokenItem(t),
        ],
      ),
    );
  }

  Widget _buildTokenItem(UserApiToken t) {
    final busy = _busyTokenIds.contains(t.id);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.name.isEmpty ? '未命名 Token' : t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                onPressed: busy ? null : () => _renameToken(t),
                icon: const Icon(LucideIcons.pencil, size: 14),
                tooltip: '修改名称',
                color: Colors.grey.shade600,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              const SizedBox(width: 4),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch.adaptive(
                  value: t.isEnabled,
                  activeColor: AppColors.iosBlue,
                  onChanged: (v) => _toggleToken(t, v),
                ),
              IconButton(
                onPressed: busy ? null : () => _deleteToken(t),
                icon: const Icon(LucideIcons.trash2, size: 15),
                tooltip: '删除 Token',
                color: Colors.red,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 窄屏一行放不下时省略中间，点击仍复制完整 token
          InkWell(
            onTap: () => _copyToken(t),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.token,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.copy, size: 13, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          if (t.createdAt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '创建于 ${t.createdAt}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  /// 角色标签单选：字典优先用 getUser 响应里的 roleMap，缺省用兜底常量
  Widget _buildRoleTagSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('角色标签', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _roleTagLabels.entries.map((e) {
              final selected = _roleTag == e.key;
              return ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (v) => setState(() => _roleTag = v ? e.key : null),
                selectedColor: AppColors.iosBlue.withOpacity(0.15),
              );
            }).toList(),
          ),
        ],
      ),
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
          onChanged: _onGroupChanged,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
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
    );
  }
}

/// Token 名称输入弹窗（新增 / 改名共用）。
/// 确认时 `pop(trim 后的名称)`，取消/关闭 `pop(null)`，调用方以 null 判断放弃。
class _TokenNameDialog extends StatefulWidget {
  final String title;
  final String description;
  final String confirmText;
  final String initialValue;

  const _TokenNameDialog({
    required this.title,
    required this.description,
    required this.confirmText,
    this.initialValue = '',
  });

  @override
  State<_TokenNameDialog> createState() => _TokenNameDialogState();
}

class _TokenNameDialogState extends State<_TokenNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: widget.title,
      maxWidth: 400,
      bodyPadding: const EdgeInsets.all(24),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.description,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Token 名称',
                hintText: 'Token 名称',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入 Token 名称' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}
