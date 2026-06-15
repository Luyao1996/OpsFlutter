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
  /// 用户的细分权限列表（后端返回的 permissions 数组）
  final List<Role> permissions;

  PermissionService({required this.groupId, required this.isManager, this.permissions = const []});

  /// 总部管理员：group_id 为空（0 或 null）
  bool get isTopManager => groupId == null || groupId == 0;

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

  /// 检查用户是否拥有指定的细分权限
  /// 对标 Vue 端 usePermission.js 的 hasDetailPermission 方法
  /// 总部管理员拥有所有权限，否则检查 permissions 列表
  bool hasDetailPermission(String permName) {
    if (isTopManager) return true;
    return permissions.any((p) => p.name == permName);
  }

  /// 按权限 id 检查细分权限（推荐，对齐 Web 端 hasDetailPermission 传
  /// PERMISSION_IDS 数字 id 的形态；后端改文案不影响判断）。
  /// 总部管理员拥有所有权限。
  bool hasDetailPermissionById(int permId) {
    if (isTopManager) return true;
    return permissions.any((p) => p.id == permId);
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
  );
});
