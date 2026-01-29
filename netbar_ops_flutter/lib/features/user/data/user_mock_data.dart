/// 角色（与后端 role 字段映射）
enum UserRole {
  admin,
  user,
}

const roleLabels = {
  UserRole.admin: '管理员',
  UserRole.user: '普通用户',
};

/// 角色对象模型 - 适配后端返回的 roles 数组中的对象 {id, name}
class RoleObject {
  final int id;
  final String name;

  RoleObject({required this.id, required this.name});

  factory RoleObject.fromJson(Map<String, dynamic> json) {
    return RoleObject(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
    );
  }
}

/// 用户模型 - 适配后端 /api/group 返回的 users 数组
class User {
  final int id;
  final String username;
  final String nickname;
  final String roleRaw;
  final List<UserRole> roles;
  /// 后端返回的角色对象列表 [{id, name}, ...]
  final List<RoleObject> roleObjects;
  /// 角色ID列表（从 roleObjects 中提取）
  final List<int> roleIds;
  final int? groupId;
  final String? phoneNumber;
  final bool isManager;
  final int? tokenRefreshTtl;
  final bool isBindWx;
  final bool isBind2fa;
  /// 该用户可访问的网吧列表（通过网吧账号组推导，管理员接口返回）
  final List<int> netbarIds;
  /// 该用户在当前网吧内所属的组ID列表（网吧成员接口返回）
  final List<int> netbarGroupIds;
  final String? email;
  final String? phone;
  final bool is2FABound;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  User({
    required this.id,
    this.username = '',
    required this.nickname,
    this.roleRaw = 'user',
    required this.roles,
    this.roleObjects = const [],
    this.roleIds = const [],
    this.groupId,
    this.phoneNumber,
    this.isManager = false,
    this.tokenRefreshTtl,
    this.isBindWx = false,
    this.isBind2fa = false,
    this.netbarIds = const [],
    this.netbarGroupIds = const [],
    this.email,
    this.phone,
    this.is2FABound = false,
    this.createdAt,
    this.updatedAt,
  });

  /// 登录有效时长（小时）
  double? get refreshTtlHours => tokenRefreshTtl != null ? tokenRefreshTtl! / 3600 : null;

  factory User.fromJson(Map<String, dynamic> json) {
    // 判断是否是管理员
    final isManager = json['is_manager'] == true || json['is_manager'] == 1;
    final mappedRole = isManager ? UserRole.admin : UserRole.user;

    final username = (json['username'] ?? '').toString();
    final nickname = (json['nickname'] ?? json['name'] ?? username).toString();

    final netbarIds = (json['netbar_ids'] as List?)
            ?.map((e) => int.tryParse(e.toString()) ?? 0)
            .where((v) => v > 0)
            .toList() ??
        const <int>[];
    final groupIds = (json['group_ids'] as List?)
            ?.map((e) => int.tryParse(e.toString()) ?? 0)
            .where((v) => v > 0)
            .toList() ??
        const <int>[];

    // 解析 roles 数组 - 后端返回 [{id, name}, ...] 格式
    List<UserRole> roles = [mappedRole];
    List<RoleObject> roleObjects = [];
    List<int> roleIds = [];

    if (json['roles'] is List) {
      final rolesList = json['roles'] as List;
      // 解析角色对象列表
      roleObjects = rolesList
          .where((e) => e is Map<String, dynamic>)
          .map((e) => RoleObject.fromJson(e as Map<String, dynamic>))
          .toList();
      // 提取角色ID列表
      roleIds = roleObjects.map((r) => r.id).where((id) => id > 0).toList();
      // 如果有角色，设置为admin
      roles = rolesList.isNotEmpty ? [UserRole.admin] : [UserRole.user];
    }

    return User(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      username: username,
      nickname: nickname,
      roleRaw: isManager ? 'admin' : 'user',
      roles: roles,
      roleObjects: roleObjects,
      roleIds: roleIds,
      groupId: json['group_id'] != null ? int.tryParse(json['group_id'].toString()) : null,
      phoneNumber: json['phone_number']?.toString(),
      isManager: isManager,
      tokenRefreshTtl: json['token_refresh_ttl'] != null
          ? int.tryParse(json['token_refresh_ttl'].toString())
          : null,
      isBindWx: json['is_bind_wx'] == true || json['is_bind_wx'] == 1,
      isBind2fa: json['is_bind_2fa'] == true || json['is_bind_2fa'] == 1,
      netbarIds: netbarIds,
      netbarGroupIds: groupIds,
      email: json['email']?.toString(),
      phone: json['phone']?.toString() ?? json['phone_number']?.toString(),
      is2FABound: json['is_bind_2fa'] == true || json['is_bind_2fa'] == 1 || json['is_2fa_bound'] == true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }
}

/// 用户分组模型 - 适配后端 /api/group 返回的数据
class UserGroup {
  final int id;
  final String name;
  final int? parentId;
  final List<User> users;

  UserGroup({
    required this.id,
    required this.name,
    this.parentId,
    this.users = const [],
  });

  factory UserGroup.fromJson(Map<String, dynamic> json) {
    final usersJson = json['users'] as List? ?? [];
    return UserGroup(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      parentId: json['parent_id'] != null ? int.tryParse(json['parent_id'].toString()) : null,
      users: usersJson.map((e) => User.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
