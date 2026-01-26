import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_api.dart';
import '../../data/user_mock_data.dart';

class AddMemberDialog extends ConsumerStatefulWidget {
  final int netbarId;
  final List<UserGroup> groups;
  final int? initialGroupId;

  const AddMemberDialog({
    super.key,
    required this.netbarId,
    required this.groups,
    this.initialGroupId,
  });

  @override
  ConsumerState<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<AddMemberDialog> {
  // ---- shared ----
  int? _selectedGroupId;

  // netbar users cache (for dedupe + group membership check)
  bool _loadingNetbarUsers = true;
  Map<int, User> _netbarUsersById = {};

  // ---- existing user tab ----
  bool _showAllUsers = false;
  bool _loadingUsers = true;
  String _search = '';
  Timer? _searchDebounce;
  List<User> _candidateUsers = [];

  // ---- new user tab ----
  final _username = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _passwordVisible = true;
  UserRole _role = UserRole.user;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _selectedGroupId = widget.initialGroupId ??
        (widget.groups.isNotEmpty ? widget.groups.first.id : null);
    _password.text = _generatePassword();
    _primeNetbarUsers();
    _loadCandidates();
  }

  bool get _isSuperAdmin {
    final auth = ref.read(authNotifierProvider);
    final role = (auth.user?.role ?? '').toLowerCase();
    return role == 'super_admin' || (auth.user?.username == 'admin');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _username.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _primeNetbarUsers() async {
    setState(() => _loadingNetbarUsers = true);
    try {
      final api = ref.read(netbarUserGroupApiProvider);
      final users = await api.getNetbarUsers(widget.netbarId);
      final map = <int, User>{};
      for (final u in users) {
        map[u.id] = u;
      }
      if (!mounted) return;
      setState(() {
        _netbarUsersById = map;
        _loadingNetbarUsers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingNetbarUsers = false);
      showTopNotice(context, '加载本网吧成员失败：$e', level: NoticeLevel.error);
    }
  }

  Future<void> _loadCandidates() async {
    setState(() => _loadingUsers = true);
    try {
      final q = _search.trim();
      if (_showAllUsers) {
        final users = await ref
            .read(userApiProvider)
            .getList(search: q.isEmpty ? null : q);
        if (!mounted) return;
        setState(() {
          _candidateUsers = users;
          _loadingUsers = false;
        });
      } else {
        final users = await ref
            .read(netbarUserGroupApiProvider)
            .getNetbarUsers(widget.netbarId, search: q.isEmpty ? null : q);
        if (!mounted) return;
        setState(() {
          _candidateUsers = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingUsers = false);
      showTopNotice(context, '加载用户失败：$e', level: NoticeLevel.error);
    }
  }

  void _scheduleSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _search = v;
      _loadCandidates();
    });
  }

  bool _isAlreadyInSelectedGroup(User user) {
    final groupId = _selectedGroupId;
    if (groupId == null) return false;
    final nbUser = _netbarUsersById[user.id];
    if (nbUser == null) return false;
    return nbUser.netbarGroupIds.contains(groupId);
  }

  String _userScopeLabel(User user) {
    final nbUser = _netbarUsersById[user.id];
    if (nbUser != null) return '本网吧';
    if (user.netbarIds.isEmpty) return '未分组成员';
    if (user.netbarIds.contains(widget.netbarId)) return '本网吧';
    return '其他网吧';
  }

  Color _scopeColor(String scope) {
    switch (scope) {
      case '本网吧':
        return const Color(0xFF22C55E);
      case '未分组成员':
        return Colors.grey.shade600;
      default:
        return Colors.orange;
    }
  }

  Future<void> _addExistingUser(User user) async {
    final groupId = _selectedGroupId;
    if (groupId == null) {
      showTopNotice(context, '请先选择分组', level: NoticeLevel.warning);
      return;
    }
    if (_isAlreadyInSelectedGroup(user)) {
      showTopNotice(context, '该用户已在当前分组中', level: NoticeLevel.warning);
      return;
    }
    try {
      await ref
          .read(netbarUserGroupApiProvider)
          .addUserToGroup(widget.netbarId, groupId, user.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      showTopNotice(context, '加入失败：$e', level: NoticeLevel.error);
    }
  }

  Future<void> _createUserAndJoin() async {
    if (_creating) return;
    final groupId = _selectedGroupId;
    if (groupId == null) {
      showTopNotice(context, '请先选择分组', level: NoticeLevel.warning);
      return;
    }

    final username = _username.text.trim();
    if (username.isEmpty) {
      showTopNotice(context, '账号不能为空', level: NoticeLevel.warning);
      return;
    }
    final password = _password.text.trim();
    if (password.length < 6) {
      showTopNotice(context, '密码长度至少 6 位', level: NoticeLevel.warning);
      return;
    }

    setState(() => _creating = true);
    try {
      final result = await ref.read(userApiProvider).create(
            username: username,
            password: password,
            name: _name.text.trim().isEmpty ? null : _name.text.trim(),
            role: _role == UserRole.admin ? 'admin' : 'user',
            netbarId: widget.netbarId,
            netbarGroupId: groupId,
          );
      if (!mounted) return;
      await _showPasswordOnce(
        title: '创建成功',
        password: result.initialPassword.isEmpty ? password : result.initialPassword,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '创建失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _showPasswordOnce({
    required String title,
    required String password,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: password));
                      if (context.mounted) {
                        showTopNotice(context, '已复制', level: NoticeLevel.success);
                      }
                    },
                    icon: const Icon(LucideIcons.copy, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#%*';
    final now = DateTime.now().microsecondsSinceEpoch;
    final out = StringBuffer();
    for (var i = 0; i < 12; i++) {
      final idx = (now + i * 9973) % chars.length;
      out.write(chars[idx]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isPhone;
    final dialogWidth = isMobile ? double.infinity : 760.0;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = (screenHeight - (isMobile ? 24 : 120)).clamp(520.0, screenHeight);
    final dialogHeight = (isMobile ? screenHeight * 0.9 : 640.0).clamp(520.0, maxHeight);

    return Dialog(
      insetPadding: isMobile ? const EdgeInsets.all(12) : null,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '添加成员',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(child: _buildGroupPicker()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildSearchBox()),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TabBar(
                  labelColor: AppColors.iosBlue,
                  unselectedLabelColor: Colors.grey.shade600,
                  indicatorColor: AppColors.iosBlue,
                  tabs: const [
                    Tab(text: '选择已有用户'),
                    Tab(text: '新建用户'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildExistingTab(),
                    _buildNewUserTab(),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Text(
                      _loadingNetbarUsers ? '加载成员关系中...' : ' ',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupPicker() {
    final groups = widget.groups;
    return DropdownButtonFormField<int>(
      value: _selectedGroupId,
      items: groups
          .map((g) => DropdownMenuItem<int>(value: g.id, child: Text(g.name)))
          .toList(),
      onChanged: (v) => setState(() => _selectedGroupId = v),
      decoration: InputDecoration(
        labelText: '目标分组',
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildSearchBox() {
    return TextField(
      onChanged: _scheduleSearch,
      decoration: InputDecoration(
        prefixIcon: const Icon(LucideIcons.search, size: 16),
        hintText: '搜索用户（账号/昵称/手机号）',
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildExistingTab() {
    final isMobile = context.isPhone;
    final hintText = _isSuperAdmin
        ? (isMobile ? '显示全部用户' : '显示全部用户（含其他网吧/未分组）')
        : (isMobile ? '包含未分组' : '包含未分组成员');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Switch(
                value: _showAllUsers,
                onChanged: (v) {
                  setState(() => _showAllUsers = v);
                  _loadCandidates();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hintText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loadCandidates,
                icon: const Icon(LucideIcons.refreshCw, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loadingUsers
                ? const Center(child: CircularProgressIndicator())
                : _candidateUsers.isEmpty
                    ? Center(
                        child: Text(
                          '暂无用户',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _candidateUsers.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final u = _candidateUsers[index];
                          final scope = _userScopeLabel(u);
                          final already = _isAlreadyInSelectedGroup(u);
                          return ListTile(
                            dense: true,
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    u.nickname.isEmpty ? u.username : u.nickname,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _scopeColor(scope).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: _scopeColor(scope).withOpacity(0.25)),
                                  ),
                                  child: Text(
                                    scope,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _scopeColor(scope),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '@${u.username}${u.phone != null ? '  ·  ${u.phone}' : ''}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                            trailing: ElevatedButton(
                              onPressed: already ? null : () => _addExistingUser(u),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.iosBlue,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(already ? '已加入' : '加入'),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewUserTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _field('昵称', _name, hint: '可选'),
                    const SizedBox(height: 12),
                    _field('账号', _username, hint: '必填'),
                    const SizedBox(height: 12),
                    _passwordField(),
                    const SizedBox(height: 12),
                    _rolePicker(),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _createUserAndJoin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.iosBlue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(_creating ? '创建中...' : '创建并加入分组'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint}) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _password,
      obscureText: !_passwordVisible,
      decoration: InputDecoration(
        labelText: '初始密码',
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _passwordVisible ? '隐藏' : '显示',
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(_passwordVisible ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
            ),
            IconButton(
              tooltip: '重新生成',
              onPressed: () => setState(() => _password.text = _generatePassword()),
              icon: const Icon(LucideIcons.refreshCw, size: 18),
            ),
            IconButton(
              tooltip: '复制',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _password.text));
                if (mounted) showTopNotice(context, '已复制', level: NoticeLevel.success);
              },
              icon: const Icon(LucideIcons.copy, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rolePicker() {
    return Row(
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
    );
  }
}
