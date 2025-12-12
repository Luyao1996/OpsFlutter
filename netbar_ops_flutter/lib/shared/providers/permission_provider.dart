import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_providers.dart';

/// 统一权限判断，与 Vue 端保持一致
class PermissionService {
  final String role;
  final int groupId;

  PermissionService({required this.role, required this.groupId});

  bool get isAdmin => role == 'admin';
  int get userGroupId => groupId;

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
    role: user?.role ?? 'user',
    groupId: user?.groupId ?? 0,
  );
});
