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

/// 细分权限对象 - 对应后端 GET /role 返回的 permissions 数组中的 {id, name, parent_id}
/// parent_id 对应 roles 中的角色 id，用于按角色分组展示
class PermissionObject {
  final int id;
  final String name;
  final int parentId;

  PermissionObject({required this.id, required this.name, this.parentId = 0});

  factory PermissionObject.fromJson(Map<String, dynamic> json) {
    return PermissionObject(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      parentId: int.tryParse((json['parent_id'] ?? 0).toString()) ?? 0,
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
  /// 后端返回的细分权限对象列表 [{id, name, parent_id}, ...]
  final List<PermissionObject> permissionObjects;
  /// 权限ID列表（从 permissionObjects 中提取）
  final List<int> permissionIds;
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
  /// 可控网吧 ID 列表（用户管理弹窗的"可控网吧"穿梭框数据源）
  /// 兼容后端两种返回格式：merchants[{id,...}] 或 merchant_ids[]
  final List<int> merchantIds;
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
    this.permissionObjects = const [],
    this.permissionIds = const [],
    this.groupId,
    this.phoneNumber,
    this.isManager = false,
    this.tokenRefreshTtl,
    this.isBindWx = false,
    this.isBind2fa = false,
    this.netbarIds = const [],
    this.netbarGroupIds = const [],
    this.merchantIds = const [],
    this.email,
    this.phone,
    this.is2FABound = false,
    this.createdAt,
    this.updatedAt,
  });

  /// 登录有效时长（小时）
  double? get refreshTtlHours => tokenRefreshTtl != null ? tokenRefreshTtl! / 3600 : null;

  /// 解析"可控网吧"ID 列表：优先 merchants[{id,...}]，回退 merchant_ids[]
  static List<int> _parseMerchantIds(Map<String, dynamic> json) {
    final raw = json['merchants'];
    if (raw is List) {
      final ids = <int>[];
      for (final e in raw) {
        if (e is Map && e['id'] != null) {
          final id = int.tryParse(e['id'].toString()) ?? 0;
          if (id > 0) ids.add(id);
        }
      }
      return ids;
    }
    final rawIds = json['merchant_ids'];
    if (rawIds is List) {
      return rawIds
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((v) => v > 0)
          .toList();
    }
    return const [];
  }

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

    // 解析 permissions 数组 - 后端返回 [{id, name, parent_id}, ...] 格式
    List<PermissionObject> permissionObjects = [];
    List<int> permissionIds = [];
    if (json['permissions'] is List) {
      final permList = json['permissions'] as List;
      permissionObjects = permList
          .where((e) => e is Map<String, dynamic>)
          .map((e) => PermissionObject.fromJson(e as Map<String, dynamic>))
          .toList();
      permissionIds = permissionObjects.map((p) => p.id).where((id) => id > 0).toList();
    }

    return User(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      username: username,
      nickname: nickname,
      roleRaw: isManager ? 'admin' : 'user',
      roles: roles,
      roleObjects: roleObjects,
      roleIds: roleIds,
      permissionObjects: permissionObjects,
      permissionIds: permissionIds,
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
      merchantIds: _parseMerchantIds(json),
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
  final bool isInternal;
  final List<User> users;

  UserGroup({
    required this.id,
    required this.name,
    this.parentId,
    this.isInternal = false,
    this.users = const [],
  });

  factory UserGroup.fromJson(Map<String, dynamic> json) {
    final usersJson = json['users'] as List? ?? [];
    return UserGroup(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      parentId: json['parent_id'] != null ? int.tryParse(json['parent_id'].toString()) : null,
      isInternal: json['is_internal'] == true,
      users: usersJson.map((e) => User.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
