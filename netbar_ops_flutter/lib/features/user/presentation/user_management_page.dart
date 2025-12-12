import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('2FA 绑定成功: ${user.nickname}')),
        );
      }
    } else if (confirmed == false) {
      // no-op
    } else {
      _showError('2FA 绑定失败');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
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
      body: Row(
        children: [
          // Sidebar
            GroupSidebar(
              groups: _groups,
              selectedGroupId: _selectedGroupId,
              onSelectGroup: (id) => setState(() => _selectedGroupId = id),
              onAddGroup: _handleAddGroup,
            ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Top Bar
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            _selectedGroupName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
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
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Search Box
                          Container(
                            width: 240,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '搜索成员...',
                                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                                prefixIcon: Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.only(bottom: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Add Button
                          ElevatedButton.icon(
                            onPressed: _handleAddUser,
                            icon: const Icon(LucideIcons.userPlus, size: 16),
                            label: const Text('添加成员', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.iosBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // User Grid
                Expanded(
                  child: UserGrid(
                    users: _filteredUsers,
                    onEditUser: _handleEditUser,
                    onBind2FA: _handleBind2FA,
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
