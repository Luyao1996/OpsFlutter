import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/game_constants.dart';
import '../data/game_library_api.dart';
import '../data/game_models.dart';

/// 按 subdomain_full 维度的 API 实例
final gameLibraryApiProvider =
    Provider.family<GameLibraryApi, String>((ref, subdomain) {
  return GameLibraryApi(subdomain);
});

/// 游戏管理对话框的核心数据状态
class GameLibraryState {
  final List<GameItem> games;
  final List<DownloadTask> downloads;
  final Map<String, PlatformSnapshot> snapshots;
  final bool loading;
  final String? listError;
  final String? downloadError;
  final RecyclePlan? recyclePlan;
  final bool planSaving;
  /// 闲置 Tab 多选 rowKey 集合（'<platform>:<gid>'）
  final Set<String> selectedRowKeys;
  /// 批删进度：null 表示空闲；非 null 时 {done,total}
  final BulkProgress? bulkProgress;

  const GameLibraryState({
    this.games = const [],
    this.downloads = const [],
    this.snapshots = const {},
    this.loading = false,
    this.listError,
    this.downloadError,
    this.recyclePlan,
    this.planSaving = false,
    this.selectedRowKeys = const {},
    this.bulkProgress,
  });

  GameLibraryState copyWith({
    List<GameItem>? games,
    List<DownloadTask>? downloads,
    Map<String, PlatformSnapshot>? snapshots,
    bool? loading,
    Object? listError = _sentinel,
    Object? downloadError = _sentinel,
    Object? recyclePlan = _sentinel,
    bool? planSaving,
    Set<String>? selectedRowKeys,
    Object? bulkProgress = _sentinel,
  }) {
    return GameLibraryState(
      games: games ?? this.games,
      downloads: downloads ?? this.downloads,
      snapshots: snapshots ?? this.snapshots,
      loading: loading ?? this.loading,
      listError: identical(listError, _sentinel)
          ? this.listError
          : listError as String?,
      downloadError: identical(downloadError, _sentinel)
          ? this.downloadError
          : downloadError as String?,
      recyclePlan: identical(recyclePlan, _sentinel)
          ? this.recyclePlan
          : recyclePlan as RecyclePlan?,
      planSaving: planSaving ?? this.planSaving,
      selectedRowKeys: selectedRowKeys ?? this.selectedRowKeys,
      bulkProgress: identical(bulkProgress, _sentinel)
          ? this.bulkProgress
          : bulkProgress as BulkProgress?,
    );
  }

  /// 已下载游戏（按 isInstalledIncludingStory 判定）
  List<GameItem> get localGames =>
      games.where((g) => g.isInstalledIncludingStory).toList(growable: false);

  /// 闲置游戏：localGames 过滤 (!isDeprecated && !isProtectedCategory
  /// && (lastLaunchTs==null||0||<cutoff))
  /// retainDays 来自 recyclePlan.retainDays；为空/无效回落 RecycleDefaults.retainDays
  List<GameItem> get idleGames {
    final raw = recyclePlan?.retainDays;
    final days = (raw != null && raw > 0) ? raw : RecycleDefaults.retainDays;
    final cutoff =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) - days * 86400;
    return localGames.where((g) {
      if (g.isDeprecated) return false;
      if (g.isProtectedCategory) return false;
      final ts = g.lastLaunchTs ?? 0;
      return ts == 0 || ts < cutoff;
    }).toList(growable: false);
  }

  /// 不健康的平台
  List<String> get unhealthyPlatforms => kAllPlatforms
      .where((p) => snapshots[p]?.unhealthy == true)
      .toList(growable: false);

  /// 离线（available == false）的平台
  List<String> get unavailablePlatforms => kAllPlatforms
      .where((p) => snapshots[p]?.available == false)
      .toList(growable: false);

  /// 全部分类（去重排序）
  List<String> get categories {
    final set = <String>{};
    for (final g in games) {
      final c = g.category;
      if (c != null && c.isNotEmpty) set.add(c);
    }
    final list = set.toList()..sort();
    return list;
  }
}

/// 批删进度：done/total（done 含失败计数）
class BulkProgress {
  final int done;
  final int total;
  const BulkProgress({required this.done, required this.total});
}

const _sentinel = Object();

/// 一个 dialog 实例对应一个 notifier；通过 family + autoDispose 在关闭后自动回收
final gameLibraryNotifierProvider = StateNotifierProvider.autoDispose
    .family<GameLibraryNotifier, GameLibraryState, String>(
  (ref, subdomain) {
    final api = ref.watch(gameLibraryApiProvider(subdomain));
    final notifier = GameLibraryNotifier(api);
    ref.onDispose(notifier._stopPolling);
    return notifier;
  },
);

class GameLibraryNotifier extends StateNotifier<GameLibraryState> {
  GameLibraryNotifier(this._api) : super(const GameLibraryState());

  final GameLibraryApi _api;
  Timer? _pollTimer;
  bool _disposed = false;

  /// 全量刷新（列表 + 下载并发）
  Future<void> refresh({String? platform}) async {
    if (_disposed) return;
    state = state.copyWith(loading: true);
    final results = await Future.wait([
      _fetchLists(platform),
      _fetchDownloading(platform),
    ]);
    if (_disposed) return;
    final listsResult = results[0] as _ListsFetch;
    final dlResult = results[1] as _DownloadingFetch;

    // 合并 snapshots（lists 与 downloading 都会带回平台健康字段）
    final mergedSnapshots = <String, PlatformSnapshot>{
      ...listsResult.snapshots,
      ...dlResult.snapshots,
    };

    state = state.copyWith(
      games: listsResult.games ?? state.games,
      downloads: dlResult.tasks ?? state.downloads,
      snapshots: mergedSnapshots.isEmpty ? state.snapshots : mergedSnapshots,
      loading: false,
      listError: listsResult.error,
      downloadError: dlResult.error,
    );
  }

  /// 仅刷新 downloads（用于 2s 轮询）
  Future<void> refreshDownloading({String? platform}) async {
    if (_disposed) return;
    final dlResult = await _fetchDownloading(platform);
    if (_disposed) return;
    final merged = {...state.snapshots, ...dlResult.snapshots};
    state = state.copyWith(
      downloads: dlResult.tasks ?? state.downloads,
      snapshots: merged,
      downloadError: dlResult.error,
    );
  }

  /// 启动 2s 轮询（仅 downloads）
  void startDownloadPolling({String? platform}) {
    _stopPolling();
    _pollTimer = Timer.periodic(
      kDownloadPollInterval,
      (_) => refreshDownloading(platform: platform),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void stopDownloadPolling() => _stopPolling();

  // ---------------------------------------------------------------------------
  // PR-2：闲置 Tab 回收策略 + 批量删除
  // ---------------------------------------------------------------------------

  /// 拉取持久化的回收策略（GET /game_library/config）
  /// 失败/拉不到时静默：保持当前 recyclePlan（可能仍为 null）
  Future<void> fetchRecyclePlan() async {
    if (_disposed) return;
    final raw = await _api.getGameConfig();
    if (_disposed) return;
    if (raw == null) {
      return;
    }
    final plan = RecyclePlan.fromConfigJson(raw);
    state = state.copyWith(recyclePlan: plan);
  }

  /// 提交 recyclePlan 当前值（含 UI 占用%/天数/weekdays/time/del_flags）
  /// enabled=true 时强制 icafe8/cloud 启用；enabled=false 时关闭（platforms 传空）
  /// 返回 ({ok, errorMessage})；ok 时 state.recyclePlan 已用后端回填值更新
  Future<({bool ok, String? error})> submitPlan({
    required bool enabled,
  }) async {
    if (_disposed) return (ok: false, error: 'disposed');
    final cur = state.recyclePlan ?? RecyclePlan.empty;
    state = state.copyWith(planSaving: true);
    final res = await _api.saveRecyclePlan(plan: cur, enabled: enabled);
    if (_disposed) return (ok: false, error: 'disposed');
    if (!res.ok) {
      state = state.copyWith(planSaving: false);
      return (ok: false, error: res.error);
    }
    // 后端回填（含 goodgame/story forced-false），用 timer_active 兜底 enabled
    final basePlan = res.plan ?? cur;
    final finalPlan = basePlan.copyWith(
      enabled: res.timerActive ?? enabled,
    );
    state = state.copyWith(
      planSaving: false,
      recyclePlan: finalPlan,
    );
    return (ok: true, error: null);
  }

  /// 顶部「确定」：更新阈值/天数后提交；不改变 enabled 状态
  Future<({bool ok, String? error})> confirmThresholds({
    required int freeThresholdUi,
    required int retainDays,
  }) async {
    if (_disposed) return (ok: false, error: 'disposed');
    final cur = state.recyclePlan ?? RecyclePlan.empty;
    state = state.copyWith(
      recyclePlan: cur.copyWith(
        freeThresholdUi: freeThresholdUi,
        retainDays: retainDays,
      ),
    );
    return submitPlan(enabled: cur.enabled);
  }

  /// 切换"自动删除"开关；target=true 时调用方需先校验 weekdays 非空 + 阈值已填
  /// 失败时 state.recyclePlan.enabled 回滚
  Future<({bool ok, String? error})> toggleAutoDelete(bool target) async {
    if (_disposed) return (ok: false, error: 'disposed');
    // 先乐观把 enabled 反过来（让 UI 立刻反映）
    final cur = state.recyclePlan ?? RecyclePlan.empty;
    state = state.copyWith(
      recyclePlan: cur.copyWith(enabled: target),
    );
    final r = await submitPlan(enabled: target);
    if (!r.ok && !_disposed) {
      // 回滚
      final back = state.recyclePlan ?? RecyclePlan.empty;
      state = state.copyWith(
        recyclePlan: back.copyWith(enabled: !target),
      );
    }
    return r;
  }

  /// 执行时间确定（draft → recyclePlan → submit，并 enable=true）
  Future<({bool ok, String? error})> confirmSchedule({
    required List<int> weekdays,
    required String time,
  }) async {
    if (_disposed) return (ok: false, error: 'disposed');
    final cur = state.recyclePlan ?? RecyclePlan.empty;
    state = state.copyWith(
      recyclePlan: cur.copyWith(
        weekdays: List<int>.from(weekdays),
        time: time,
      ),
    );
    return submitPlan(enabled: true);
  }

  /// 单条删除（永久删除 + 清盘）
  /// 返回 ({ok, status, resultCode, error})：
  /// - ok=true 表示 HTTP 200 且 results[gid]=='ok'
  /// - 403 status 用于 UI 给出"仅本机回环"专属文案
  /// - resultCode 是后端 results[gid] 原文，便于 UI 走 not_owner / not_in_progress 分支
  Future<({bool ok, int status, String? resultCode, String? error})>
      deleteSingle(GameItem row) async {
    if (_disposed) {
      return (ok: false, status: 0, resultCode: null, error: 'disposed');
    }
    final res = await _api.deleteGame(platform: row.platform, gid: row.gid);
    if (_disposed) {
      return (
        ok: false,
        status: res.status,
        resultCode: null,
        error: 'disposed',
      );
    }
    if (!res.ok) {
      return (
        ok: false,
        status: res.status,
        resultCode: null,
        error: res.error,
      );
    }
    final rc = res.results[row.gid];
    return (
      ok: rc == 'ok',
      status: res.status,
      resultCode: rc,
      error: null,
    );
  }

  /// 批量删除（串行 await，必须串行避免并发清盘冲突 / 504 worker timeout）
  /// 边删边更新 state.bulkProgress；结束后 bulkProgress 重置 null
  Future<BatchDeleteResult> deleteBulk(List<GameItem> targets) async {
    if (_disposed || targets.isEmpty) {
      return const BatchDeleteResult(success: 0, failures: []);
    }
    state = state.copyWith(
      bulkProgress: BulkProgress(done: 0, total: targets.length),
    );
    var success = 0;
    final failures = <BatchDeleteFailure>[];

    for (var i = 0; i < targets.length; i++) {
      if (_disposed) break;
      final row = targets[i];
      final res = await _api.deleteGame(platform: row.platform, gid: row.gid);
      if (_disposed) break;
      if (!res.ok) {
        final reason = res.status == 403
            ? 'game_library 仅允许本机调用 delete_game，请通过网吧本地管理界面操作'
            : (res.error ?? 'HTTP ${res.status}');
        failures.add(BatchDeleteFailure(
          name: row.name ?? row.gid.toString(),
          reason: reason,
        ));
      } else {
        final rc = res.results[row.gid];
        if (rc == 'ok') {
          success++;
        } else {
          failures.add(BatchDeleteFailure(
            name: row.name ?? row.gid.toString(),
            reason: _formatOpResult(rc),
          ));
        }
      }
      if (!_disposed) {
        state = state.copyWith(
          bulkProgress: BulkProgress(done: i + 1, total: targets.length),
        );
      }
    }
    if (!_disposed) {
      state = state.copyWith(bulkProgress: null);
    }
    return BatchDeleteResult(success: success, failures: failures);
  }

  String _formatOpResult(String? rc) {
    if (rc == null || rc.isEmpty) return '未知错误';
    if (rc == 'err: not connected') return '平台连接断开';
    if (rc == 'platform_stopped') return '平台 worker 已停止';
    if (rc.startsWith('err:')) return rc.substring(4).trim();
    return rc;
  }

  // ---- 多选维护 -------------------------------------------------------------

  void toggleSelect(String rowKey) {
    if (_disposed) return;
    final next = Set<String>.from(state.selectedRowKeys);
    if (!next.remove(rowKey)) next.add(rowKey);
    state = state.copyWith(selectedRowKeys: next);
  }

  void selectAll(Iterable<String> rowKeys) {
    if (_disposed) return;
    state = state.copyWith(selectedRowKeys: Set<String>.from(rowKeys));
  }

  void clearSelection() {
    if (_disposed) return;
    if (state.selectedRowKeys.isEmpty) return;
    state = state.copyWith(selectedRowKeys: const {});
  }

  Future<_ListsFetch> _fetchLists(String? platform) async {
    try {
      final r = await _api.getGameLists(platform: platform);
      return _ListsFetch(games: r.games, snapshots: r.snapshots);
    } catch (e) {
      return _ListsFetch(snapshots: const {}, error: e.toString());
    }
  }

  Future<_DownloadingFetch> _fetchDownloading(String? platform) async {
    try {
      final r = await _api.getDownloading(platform: platform);
      return _DownloadingFetch(tasks: r.tasks, snapshots: r.snapshots);
    } catch (e) {
      return _DownloadingFetch(snapshots: const {}, error: e.toString());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}

class _ListsFetch {
  final List<GameItem>? games;
  final Map<String, PlatformSnapshot> snapshots;
  final String? error;
  _ListsFetch({this.games, required this.snapshots, this.error});
}

class _DownloadingFetch {
  final List<DownloadTask>? tasks;
  final Map<String, PlatformSnapshot> snapshots;
  final String? error;
  _DownloadingFetch({this.tasks, required this.snapshots, this.error});
}
