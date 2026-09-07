import '../../../shared/utils/natural_sort.dart';
import '../data/game_constants.dart';
import '../data/game_models.dart';

/// 游戏列表排序 —— 移植自 toolboxPage `composables/netbar/game-library/helpers.js`
/// 的 GAME_SORT_FIELDS（8 个字段，含各自的默认方向）。
///
/// 下载任务页字段完全不同（进度/速度/机号），不复用这套。

/// 状态按「离可用有多远」排：未下载 → 可更新 → 已下载；
/// 已废弃在列表里本来就过滤掉了，排最后兜底。
int _stateRank(GameItem g) => switch (g.rowState) {
      GameRowState.pending => 1,
      GameRowState.upgrade => 2,
      GameRowState.installed => 3,
      GameRowState.deprecated => 4,
    };

/// 数值字段缺省时返回 null（而不是 0），让 sortByGetter 把这些行恒沉底 ——
/// 否则「按热度降序」时一堆没有热度的游戏会跟热度 0 混在一起顶到前面。
Object? _numOrNull(num? v) => (v == null || v == 0) ? null : v;

enum GameSortField { platform, category, state, size, gid, popularity, updated, installed }

class GameSortSpec {
  final GameSortField field;
  final String label;

  /// 切到该字段时套用的默认方向（大小/热度/时间这类"越大越关心"的默认降序，其余升序）
  final SortOrder defaultOrder;
  final Object? Function(GameItem) getter;

  const GameSortSpec({
    required this.field,
    required this.label,
    required this.defaultOrder,
    required this.getter,
  });
}

final List<GameSortSpec> kGameSortFields = [
  GameSortSpec(
    field: GameSortField.platform,
    label: '按平台',
    defaultOrder: SortOrder.ascending,
    getter: (g) => kPlatformLabel[g.platform] ?? g.platform,
  ),
  GameSortSpec(
    field: GameSortField.category,
    label: '按分类',
    defaultOrder: SortOrder.ascending,
    getter: (g) => g.category,
  ),
  GameSortSpec(
    field: GameSortField.state,
    label: '按状态',
    defaultOrder: SortOrder.ascending,
    getter: _stateRank,
  ),
  GameSortSpec(
    field: GameSortField.size,
    label: '按大小',
    defaultOrder: SortOrder.descending,
    getter: (g) => _numOrNull(g.sizeBytes),
  ),
  GameSortSpec(
    field: GameSortField.gid,
    label: '按序号',
    defaultOrder: SortOrder.ascending,
    getter: (g) => g.gid,
  ),
  GameSortSpec(
    field: GameSortField.popularity,
    label: '按热度',
    defaultOrder: SortOrder.descending,
    getter: (g) => _numOrNull(g.popularity),
  ),
  GameSortSpec(
    field: GameSortField.updated,
    label: '按最后修改',
    defaultOrder: SortOrder.descending,
    getter: (g) => _numOrNull(g.idcUpdateTs),
  ),
  GameSortSpec(
    field: GameSortField.installed,
    label: '按是否下载',
    defaultOrder: SortOrder.descending,
    // 与筛选栏「已下载」同口径（story 平台 local_version>0 也算已下载）
    getter: (g) => g.isInstalledIncludingStory,
  ),
];

GameSortSpec? gameSortSpec(GameSortField? field) {
  if (field == null) return null;
  for (final f in kGameSortFields) {
    if (f.field == field) return f;
  }
  return null;
}

/// 排序必须排在过滤之后、分页切片之前：列表是触底分片渲染的，只排已渲染那一截
/// 会出现「越往下滚顺序越乱」，得在全量结果上排完再切。
List<GameItem> sortGames(
  List<GameItem> games,
  GameSortField? field,
  SortOrder? order,
) {
  final spec = gameSortSpec(field);
  if (spec == null) return games;
  return sortByGetter(games, spec.getter, order ?? spec.defaultOrder);
}
