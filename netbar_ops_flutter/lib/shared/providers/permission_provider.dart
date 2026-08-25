import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_providers.dart';
import '../../features/auth/data/auth_api.dart' show Role;

// ===== 后端细分权限 id 常量 =====
// 对齐 toolboxPage src/constants/permissions.js PERMISSION_IDS：
// 按 id 判断，后端改权限文案时不会失效。

/// 启禁用锁屏（终端详情「2FA管理」弹窗内的锁屏开关，对齐 toolboxPage LOCK_SCREEN=16）
const int kPermLockScreen = 16;

/// 应用添加（应用中心：添加/取消添加到分组）
const int kPermNetbarAppAdd = 22;

/// 配置应用（应用策略配置）
const int kPermNetbarAppConfig = 23;

/// 统一权限判断，与后端 toolbox 保持一致
class PermissionService {
  final int? groupId;
  final bool isManager;
  /// 用户的细分权限列表（后端返回的平铺 permissions 数组）
  final List<Role> permissions;
  /// 用户绑定的权限组（后端 roles[]，每个组内嵌 permissions[] 权限点）
  final List<Role> roles;

  PermissionService({
    required this.groupId,
    required this.isManager,
    this.permissions = const [],
    this.roles = const [],
  });

  /// 总部管理员：group_id 为空（0 或 null）且 is_manager 为 true
  /// （对齐 toolboxPage permissions.js isHeadquartersAdmin = 总部人员 && is_manager；
  ///  总部普通成员不是管理员，走 permissions 数组细分权限）
  bool get isTopManager => (groupId == null || groupId == 0) && isManager;

  /// 分部管理员：group_id > 0 且 is_manager 为 true
  bool get isSubManager => (groupId != null && groupId! > 0) && isManager;

  /// 普通用户：group_id > 0 且 is_manager 为 false
  bool get isNormalUser => (groupId != null && groupId! > 0) && !isManager;

  /// 是否有管理权限（总部管理员或分部管理员）
  bool get isAdmin => isTopManager || isSubManager;

  /// 是否是超级管理员（总部管理员）
  bool get isSuperAdmin => isTopManager;

  /// 是否为总部用户（不一定是管理员）
  bool get isHQUser => groupId == null || groupId == 0;

  int get userGroupId => groupId ?? 0;

  /// 细分权限判定，对标 Vue 端 usePermission.js 的 hasDetailPermission：
  /// 1. 总部管理员放行全部；
  /// 2. 有权限组且组内下发了权限点 → 只认 roles[].permissions[]，匹配不到即无权限
  ///    （后端平铺 permissions 会做"父展开"，直接用会把父模块误判成已授权）；
  /// 3. 否则回退平铺 permissions。
  bool _match(bool Function(Role p) matcher) {
    if (isTopManager) return true;

    // 只要任一权限组带回了嵌套权限点，就以权限组为唯一依据
    if (roles.isNotEmpty && roles.any((r) => r.permissions != null)) {
      for (final r in roles) {
        final list = r.permissions;
        if (list != null && list.any(matcher)) return true;
      }
      return false;
    }

    // 防御回退：roles 为空（旧个人权限模型），或版本升级后首次冷启动读到的旧缓存
    // ——roles 有值但没有嵌套 permissions。此时若直接判 false，用户权限会整体归零，
    // 所以退回平铺 permissions，等联网刷新到带嵌套的数据后再走上面的精确分支。
    return permissions.any(matcher);
  }

  /// 按权限名称检查细分权限
  bool hasDetailPermission(String permName) => _match((p) => p.name == permName);

  /// 按权限 id 检查细分权限（推荐，对齐 Web 端 hasDetailPermission 传
  /// PERMISSION_IDS 数字 id 的形态；后端改文案不影响判断）。
  bool hasDetailPermissionById(int permId) => _match((p) => p.id == permId);

  /// 组配置可操作性（对齐 toolboxPage permissions.js:183-198 canOperateGroupConfig）：
  /// - 总部配置（creatorGroupId 为 0/null）任何人都可操作；
  /// - 总部人员可操作所有配置；
  /// - 小组配置仅本组人员可操作。
  bool canOperateGroupConfig(int? creatorGroupId) {
    if (creatorGroupId == null || creatorGroupId == 0) return true;
    if (isHQUser) return true;
    return creatorGroupId == userGroupId;
  }

  /// zone: PUBLIC/HEADQUARTERS/BRANCH
  /// netbarId: 当前网吧 id（仅 PUBLIC 需要）
  /// 普通用户：只能编辑 PUBLIC；HEADQUARTERS/BRANCH 仅查看/下载
  bool canEditZone(String zone, {int? netbarId}) {
    if (zone == 'HEADQUARTERS' || zone == 'BRANCH') return false;
    return netbarId != null; // PUBLIC: 必须选择网吧
  }

  /// 是否可下载资源：所有区域都可下载
  bool canDownloadZone(String zone) {
    return true;
  }
}

/// 权限服务 Provider
final permissionProvider = Provider<PermissionService>((ref) {
  final user = ref.watch(authNotifierProvider).user;
  return PermissionService(
    groupId: user?.groupId,
    isManager: user?.isManager ?? false,
    permissions: user?.permissions ?? const [],
    roles: user?.roles ?? const [],
  );
});
