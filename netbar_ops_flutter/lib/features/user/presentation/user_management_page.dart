import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/utils/top_notice.dart';
import '../data/user_api.dart';
import 'widgets/group_sidebar.dart';
import 'widgets/user_grid.dart';
import 'widgets/add_member_dialog.dart';
import 'widgets/edit_user_dialog.dart';
import 'widgets/two_factor_dialog.dart';

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  // State
  List<UserGroup> _groups = [];
  int? _selectedGroupId;
  String _searchQuery = '';
  String _groupSearchQuery = '';
  bool _isLoading = true;

  // 网吧切换监听
  ProviderSubscription<CurrentNetbar>? _netbarSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();

    // 监听网吧切换，自动刷新数据
    _netbarSubscription = ref.listenManual<CurrentNetbar>(
      currentNetbarProvider,
      (prev, next) {
        if (prev?.id != next.id || prev?.version != next.version) {
          setState(() {
            _selectedGroupId = null;
            _searchQuery = '';
            _groupSearchQuery = '';
          });
          _loadData();
        }
      },
    );
  }

  @override
  void dispose() {
    _netbarSubscription?.close();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!_isAdmin) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 使用 /api/group 接口获取分组列表（包含用户）
      final groupApi = ref.read(groupApiProvider);
      final groups = await groupApi.getList();

      setState(() {
        _groups = groups;
        // 默认 null 表示"所有成员"
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('加载失败：$e');
    }
  }

  // Computed
  List<User> get _filteredUsers {
    List<User> result = [];

    // 如果选择了特定分组，只显示该分组的用户；null 表示"所有成员"
    if (_selectedGroupId != null) {
      final group = _groups.firstWhere(
        (g) => g.id == _selectedGroupId,
        orElse: () => UserGroup(id: 0, name: ''),
      );
      result = group.users.map((u) => User(
        id: u.id,
        username: u.username,
        nickname: u.nickname,
        roleRaw: u.roleRaw,
        roles: u.roles,
        groupId: _selectedGroupId,
        phoneNumber: u.phoneNumber,
        isManager: u.isManager,
        tokenRefreshTtl: u.tokenRefreshTtl,
        isBindWx: u.isBindWx,
        isBind2fa: u.isBind2fa,
        is2FABound: u.is2FABound,
      )).toList();
    } else {
      // 显示所有分组的用户
      for (final group in _groups) {
        for (final u in group.users) {
          result.add(User(
            id: u.id,
            username: u.username,
            nickname: u.nickname,
            roleRaw: u.roleRaw,
            roles: u.roles,
            groupId: group.id,
            phoneNumber: u.phoneNumber,
            isManager: u.isManager,
            tokenRefreshTtl: u.tokenRefreshTtl,
            isBindWx: u.isBindWx,
            isBind2fa: u.isBind2fa,
            is2FABound: u.is2FABound,
          ));
        }
      }
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((u) =>
          u.nickname.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q)).toList();
    }
    return result;
  }

  String get _selectedGroupName {
    if (_selectedGroupId == null) return '所有成员';
    if (_groups.isEmpty) return '加载中...';
    return _groups.firstWhere((g) => g.id == _selectedGroupId, orElse: () => UserGroup(id: -1, name: '未知分组')).name;
  }

  bool get _isAdmin {
    final user = ref.read(authNotifierProvider).user;
    // 使用与后端一致的管理员判断逻辑
    return user?.hasAdminAccess == true;
  }

  bool get _isSuperAdmin {
    final user = ref.read(authNotifierProvider).user;
    // 总部管理员
    return user?.isTopManager == true;
  }

  // Actions
  void _handleAddGroup() => _handleGroupDialog();

  void _handleEditGroup(UserGroup group) => _handleGroupDialog(editing: group);

  Future<void> _handleGroupDialog({UserGroup? editing}) async {
    if (!_isSuperAdmin) {
      _showError(editing == null ? '仅总部管理员可创建分组' : '仅总部管理员可编辑分组');
      return;
    }
    if (editing != null && editing.isInternal) {
      _showError('该分组不可编辑');
      return;
    }
    String? newName;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: editing?.name ?? '');
        return AlertDialog(
          title: Text(editing == null ? '新建分组' : '编辑分组'),
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
              child: Text(editing == null ? '确定' : '保存'),
            ),
          ],
        );
      },
    );

    if (newName == null || newName!.isEmpty) return;
    if (editing != null && newName == editing.name) return;

    try {
      final groupApi = ref.read(groupApiProvider);
      if (editing == null) {
        await groupApi.create(name: newName!);
      } else {
        await groupApi.update(editing.id, name: newName!);
      }
      if (!mounted) return;
      showTopNotice(
        context,
        editing == null ? '分组创建成功' : '分组名称已更新',
        level: NoticeLevel.success,
      );
      _loadData();
    } catch (e) {
      _showApiError(editing == null ? '创建分组' : '编辑分组', e);
    }
  }

  void _handleAddUser() async {
    final changed = await showAdaptive<bool>(
      context,
      (context) => AddMemberDialog(
        groups: _groups,
        initialGroupId: _selectedGroupId,
      ),
      routeName: '/dialog/add-member',
    );
    if (changed == true) {
      _loadData(); // Reload after add
    }
  }

  Future<void> _handleDeleteGroup(UserGroup group) async {
    // 内置分组（is_internal=true，如总部、业主分组）不可删除
    if (group.isInternal) {
      _showError('该分组不可编辑');
      return;
    }
    if (!_isSuperAdmin) {
      _showError('仅总部管理员可删除分组');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定要删除分组 "${group.name}" 吗？\n该分组下的成员关系将被移除。'),
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

    try {
      final groupApi = ref.read(groupApiProvider);
      await groupApi.delete(group.id);
      if (!mounted) return;
      if (_selectedGroupId == group.id) {
        setState(() => _selectedGroupId = null);
      }
      showTopNotice(context, '已删除分组：${group.name}', level: NoticeLevel.success);
      _loadData();
    } catch (e) {
      _showApiError('删除分组', e);
    }
  }

  void _handleEditUser(User user) async {
    final changed = await showAdaptive<bool>(
      context,
      (context) => EditUserDialog(
        user: user,
        groups: _groups,
      ),
      routeName: '/dialog/edit-user',
    );
    if (changed == true) {
      _loadData(); // Reload after edit
    }
  }

  void _handleBind2FA(User user) async {
    final confirmed = await showAdaptive<bool>(
      context,
      (context) => TwoFactorDialog(user: user),
      routeName: '/dialog/two-factor',
    );

    if (confirmed == true) {
      _loadData();
      if (mounted) {
        showTopNotice(context, '2FA 绑定成功: ${user.nickname}', level: NoticeLevel.success);
      }
    }
  }

  void _handleBindMiniProgram(User user) async {
    try {
      final api = ref.read(userApiProvider);
      final response = await api.bindMiniProgram(user.id);

      if (!mounted) return;

      if (!mounted) return;

      // 显示二维码弹窗
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _MiniProgramQrDialog(
          userId: user.id,
          initialQrCode: response.qrCode,
          userApi: ref.read(userApiProvider),
          onClose: () {
            Navigator.of(context).pop();
            _loadData(); // 刷新列表
          },
        ),
      );
    } catch (e) {
      _showApiError('绑定小程序', e);
    }
  }

  void _handleUnbindMiniProgram(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解绑小程序'),
        content: Text('确定要解绑用户 "${user.nickname}" 的小程序吗？'),
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
            child: const Text('解绑'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(userApiProvider);
      await api.unbindMiniProgram(user.id);
      if (!mounted) return;
      showTopNotice(context, '解绑成功', level: NoticeLevel.success);
      _loadData();
    } catch (e) {
      _showApiError('解绑小程序', e);
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

  Future<void> _handleRefreshTtlChanged(User user, double hours) async {
    try {
      final ttlSeconds = (hours * 3600).round();
      final api = ref.read(userApiProvider);
      await api.setTokenRefreshTtl(user.id, ttlSeconds: ttlSeconds);
      if (!mounted) return;
      showTopNotice(context, '登录有效时长已更新', level: NoticeLevel.success);
      _loadData();
    } catch (e) {
      _showApiError('修改登录有效时长', e);
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
            groupSearchQuery: _groupSearchQuery,
            onGroupSearchChanged: (v) => setState(() => _groupSearchQuery = v),
            onDeleteGroup: _handleDeleteGroup,
            onEditGroup: _handleEditGroup,
          );

          final main = Column(
            children: [
              _buildTopBar(isNarrow),
              Expanded(
                child: UserGrid(
                  users: _filteredUsers,
                  onEditUser: _handleEditUser,
                  onBind2FA: _handleBind2FA,
                  onBindMiniProgram: _handleBindMiniProgram,
                  onUnbindMiniProgram: _handleUnbindMiniProgram,
                  isAdmin: _isAdmin,
                  onRefreshTtlChanged: _handleRefreshTtlChanged,
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
            groupSearchQuery: _groupSearchQuery,
            onGroupSearchChanged: (v) => setState(() => _groupSearchQuery = v),
            onDeleteGroup: (group) async {
              Navigator.pop(context);
              await _handleDeleteGroup(group);
            },
            onEditGroup: (group) {
              Navigator.pop(context);
              _handleEditGroup(group);
            },
          ),
        ),
      ),
    );
  }
}

/// 小程序绑定二维码弹窗
class _MiniProgramQrDialog extends StatefulWidget {
  final int userId;
  final String initialQrCode;
  final UserApi userApi;
  final VoidCallback onClose;

  const _MiniProgramQrDialog({
    required this.userId,
    required this.initialQrCode,
    required this.userApi,
    required this.onClose,
  });

  @override
  State<_MiniProgramQrDialog> createState() => _MiniProgramQrDialogState();
}

class _MiniProgramQrDialogState extends State<_MiniProgramQrDialog> {
  static const int _maxCountdown = 30;

  late String _qrCode;
  late Uint8List _qrImageBytes; // 缓存解码后的图片数据
  int _countdown = _maxCountdown;
  bool _isRefreshing = false;
  Stream<int>? _timerStream;

  @override
  void initState() {
    super.initState();
    _qrCode = widget.initialQrCode;
    _qrImageBytes = _decodeQrCode(_qrCode);
    _startCountdown();
  }

  /// 解码二维码数据
  Uint8List _decodeQrCode(String qrCode) {
    String base64Data = qrCode;
    if (base64Data.contains(',')) {
      base64Data = base64Data.split(',').last;
    }
    return base64Decode(base64Data);
  }

  void _startCountdown() {
    _timerStream = Stream.periodic(const Duration(seconds: 1), (i) => _maxCountdown - 1 - i)
        .take(_maxCountdown);
    _timerStream!.listen((sec) {
      if (mounted) {
        setState(() => _countdown = sec);
        if (sec <= 0) {
          _refreshQrCode();
        }
      }
    });
  }

  Future<void> _refreshQrCode() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      final response = await widget.userApi.bindMiniProgram(widget.userId);
      if (mounted) {
        setState(() {
          _qrCode = response.qrCode;
          _qrImageBytes = _decodeQrCode(_qrCode); // 更新缓存的图片数据
          _countdown = _maxCountdown;
          _isRefreshing = false;
        });
        _startCountdown();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 32),
                  const Text(
                    '扫码验证',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(LucideIcons.x, size: 18, color: Colors.grey.shade500),
                      padding: EdgeInsets.zero,
                      splashRadius: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '请使用网维小程序扫码验证',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 24),
              // 二维码（可点击刷新）
              GestureDetector(
                onTap: _isRefreshing ? null : _refreshQrCode,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade100),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.memory(
                        _qrImageBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true, // 防止图片切换时闪烁
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.alertCircle, size: 32, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text('加载失败', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // 刷新遮罩
                    if (_isRefreshing)
                      Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 点击刷新提示
              Text(
                '点击二维码可刷新',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 8),
              // 倒计时
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _countdown <= 10 ? Colors.orange.shade50 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '有效期 $_countdown 秒',
                  style: TextStyle(
                    fontSize: 12,
                    color: _countdown <= 10 ? Colors.orange.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // 关闭按钮
              TextButton(
                onPressed: widget.onClose,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                ),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
