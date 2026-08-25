import '../../../shared/providers/permission_provider.dart';
import 'strategy_models.dart';

/// 策略（Tactic）操作权限判定 —— T8c-0 共享层，供 V2 通道管理的策略弹窗调用。
///
/// 口径来源：web NetbarStrategyDialog.vue:226-239
/// ```js
/// const canEdit   = (row) => isManager.value
/// const canDelete = (row) => {
///   if (!isManager.value) return false
///   if (row.group_id == 0) return isHeadquartersAdmin.value  // 总部创建的仅总部管理员可删
///   return true
/// }
/// ```
///
/// ⚠ 绝对不要用 `PermissionService.canOperateGroupConfig` 来判策略：
/// 它对 `creatorGroupId == 0`（总部创建）直接 `return true`（任何人都能操作），
/// 与这里"总部创建的策略只有总部管理员能删"的语义**正好相反**，
/// 用错会让分部管理员删掉总部下发的策略。两者不是同一套规则，不可互相替代。
extension StrategyPermission on PermissionService {
  /// 能否编辑策略：只要是管理员（总部/分部都行）
  bool canEditStrategy(TacticItem row) {
    // 占位行（无策略网吧）没有可编辑的实体
    if (row.isPlaceholder) return false;
    return isManager;
  }

  /// 能否删除策略：管理员前提下，总部创建的（groupId==0）仅总部管理员可删
  bool canDeleteStrategy(TacticItem row) {
    if (row.isPlaceholder) return false;
    if (!isManager) return false;
    // web 判的是 row.group_id；后端另有 creator_group_id，
    // 两者在策略行上同源（NetbarStrategyDialog.vue:250 `row.creator_group_id ?? row.group_id`），
    // 这里以 groupId 为准、groupId 缺失时回退 creatorGroupId。
    final ownerGroupId = row.groupId ?? row.creatorGroupId;
    if (ownerGroupId == null || ownerGroupId == 0) {
      return isTopManager;
    }
    return true;
  }

  /// 原始口径版本（不依赖 TacticItem，供只拿得到 groupId 的调用方使用）
  bool canDeleteStrategyByGroupId(int? strategyGroupId) {
    if (!isManager) return false;
    if (strategyGroupId == null || strategyGroupId == 0) return isTopManager;
    return true;
  }
}
