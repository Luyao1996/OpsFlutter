import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/top_notice.dart';
import '../data/user_mock_data.dart';
import '../data/user_api.dart';
import 'widgets/group_sidebar.dart';
import 'widgets/user_grid.dart';
import 'widgets/add_user_dialog.dart';
import 'widgets/two_factor_dialog.dart';

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  // State
  List<UserGroup> _groups = [];
  List<User> _users = [];
  int? _selectedGroupId;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!_isAdmin) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final userApi = ref.read(userApiProvider);
      final groupApi = ref.read(groupApiProvider);

      final groups = await groupApi.getAll();
      final users = await userApi.getList(search: _searchQuery.isNotEmpty ? _searchQuery : null);

      setState(() {
        _groups = groups;
        _users = users;
        // Default to '0' (All Members) if not set
        _selectedGroupId ??= 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('加载失败：$e');
    }
  }

  // Computed
  List<User> get _filteredUsers {
    List<User> result = _users;
    // Filter by group only if not '0' (All Members)
    if (_selectedGroupId != null && _selectedGroupId != 0) {
      result = result.where((u) => u.groupId == _selectedGroupId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((u) => u.nickname.toLowerCase().contains(q) || u.username.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  String get _selectedGroupName {
    if (_selectedGroupId == 0) return '所有成员';
    if (_groups.isEmpty) return '加载中...';
    return _groups.firstWhere((g) => g.id == _selectedGroupId, orElse: () => UserGroup(id: 0, name: '所有成员')).name;
  }

  bool get _isAdmin {
    final user = ref.read(authNotifierProvider).user;
    return user?.role == 'admin';
  }

  // Actions
  void _handleAddGroup() async {
    String? newName;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('新建分组'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '请输入分组名称'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            ElevatedButton(
              onPressed: () {
                newName = controller.text.trim();
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName!.isNotEmpty) {
      try {
        final groupApi = ref.read(groupApiProvider);
        await groupApi.create(name: newName!);
        _loadData();
      } catch (e) {
        _showApiError('创建分组', e);
      }
    }
  }

  void _handleAddUser() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AddUserDialog(groups: _groups, initialGroupId: _selectedGroupId),
    );
    if (changed == true) {
      _loadData(); // Reload after add
    }
  }

  void _handleEditUser(User user) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AddUserDialog(groups: _groups, initialUser: user),
    );
    if (changed == true) {
      _loadData(); // Reload after edit
    }
  }

  void _handleBind2FA(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => TwoFactorDialog(user: user),
    );

    if (confirmed == true) {
      // Update user 2FA status
      final userApi = ref.read(userApiProvider);
      await userApi.update(user.id, {'is_2fa_bound': true});
      _loadData();
      if (mounted) {
        showTopNotice(context, '2FA 绑定成功: ${user.nickname}', level: NoticeLevel.success);
      }
    } else if (confirmed == false) {
      // no-op
    } else {
      _showError('2FA 绑定失败');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showTopNotice(context, message, level: NoticeLevel.error);
  }

  void _showApiError(String action, Object error) {
    if (error is ApiError) {
      final msg = error.message;
      if (error.code == 403 || msg.contains('管理员权限')) {
        _showError('$action失败：需要管理员权限');
        return;
      }
      _showError('$action失败：$msg');
    } else {
      _showError('$action失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.shieldOff, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text('无权限访问用户账户', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('请联系管理员开通权限', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.go('/dashboard'),
                icon: const Icon(LucideIcons.home, size: 16),
                label: const Text('返回首页'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = context.isNarrow;

          final sidebar = GroupSidebar(
            width: isNarrow ? null : 240,
            groups: _groups,
            selectedGroupId: _selectedGroupId,
            onSelectGroup: (id) => setState(() => _selectedGroupId = id),
            onAddGroup: _handleAddGroup,
          );

          final main = Column(
            children: [
              _buildTopBar(isNarrow),
              Expanded(
                child: UserGrid(
                  users: _filteredUsers,
                  onEditUser: _handleEditUser,
                  onBind2FA: _handleBind2FA,
                ),
              ),
            ],
          );

          if (!isNarrow) {
            return Row(
              children: [
                sidebar,
                Expanded(child: main),
              ],
            );
          }
          return main;
        },
      ),
    );
  }

  Widget _buildTopBar(bool isNarrow) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isNarrow ? 12 : 24, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (isNarrow)
                IconButton(
                  onPressed: _showGroupSelectorSheet,
                  icon: const Icon(LucideIcons.menu, size: 20),
                  tooltip: '选择分组',
                ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        _selectedGroupName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_filteredUsers.length} 成员',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 12),
                SizedBox(width: 260, child: _buildSearchField()),
                const SizedBox(width: 12),
                _buildAddUserButton(),
              ],
            ],
          ),
          if (isNarrow) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 12),
                _buildAddUserButton(compact: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索成员...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon:
              Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildAddUserButton({bool compact = false}) {
    return ElevatedButton.icon(
      onPressed: _handleAddUser,
      icon: const Icon(LucideIcons.userPlus, size: 16),
      label: compact
          ? const Text('添加',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold))
          : const Text('添加成员',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  void _showGroupSelectorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: GroupSidebar(
            width: null,
            groups: _groups,
            selectedGroupId: _selectedGroupId,
            onSelectGroup: (id) {
              Navigator.pop(context);
              setState(() => _selectedGroupId = id);
            },
            onAddGroup: () {
              Navigator.pop(context);
              _handleAddGroup();
            },
          ),
        ),
      ),
    );
  }
}
