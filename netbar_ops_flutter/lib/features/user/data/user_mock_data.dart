/// 角色（与后端 role 字段映射）
enum UserRole {
  admin,
  user,
}

const roleLabels = {
  UserRole.admin: '管理员',
  UserRole.user: '普通用户',
};

class User {
  final int id;
  final String username;
  final String nickname;
  final String roleRaw;
  final List<UserRole> roles;
  final int? groupId;
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
    required this.username,
    required this.nickname,
    required this.roleRaw,
    required this.roles,
    this.groupId,
    this.netbarIds = const [],
    this.netbarGroupIds = const [],
    this.email,
    this.phone,
    required this.is2FABound,
    this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    final roleStr = (json['role'] ?? 'user').toString();
    final mappedRole =
        (roleStr == 'admin' || roleStr == 'super_admin') ? UserRole.admin : UserRole.user;
    final username = (json['username'] ?? '').toString();
    final name = (json['name'] ?? username).toString();
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

    return User(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      username: username,
      nickname: name,
      roleRaw: roleStr,
      roles: [mappedRole],
      groupId: json['group_id'] != null ? int.tryParse(json['group_id'].toString()) : null,
      netbarIds: netbarIds,
      netbarGroupIds: groupIds,
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      is2FABound: json['is_2fa_bound'] ?? false,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()),
    );
  }
}

class UserGroup {
  final int id;
  final String name;
  final int? parentId;

  UserGroup({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory UserGroup.fromJson(Map<String, dynamic> json) {
    return UserGroup(
      id: int.tryParse((json['id'] ?? 0).toString()) ?? 0,
      name: (json['name'] ?? '').toString(),
      parentId: json['parent_id'] != null ? int.tryParse(json['parent_id'].toString()) : null,
    );
  }
}
