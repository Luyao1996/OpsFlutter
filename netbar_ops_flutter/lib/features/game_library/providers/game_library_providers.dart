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

  const GameLibraryState({
    this.games = const [],
    this.downloads = const [],
    this.snapshots = const {},
    this.loading = false,
    this.listError,
    this.downloadError,
  });

  GameLibraryState copyWith({
    List<GameItem>? games,
    List<DownloadTask>? downloads,
    Map<String, PlatformSnapshot>? snapshots,
    bool? loading,
    Object? listError = _sentinel,
    Object? downloadError = _sentinel,
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
    );
  }

  /// 已下载游戏（按 isInstalledIncludingStory 判定）
  List<GameItem> get localGames =>
      games.where((g) => g.isInstalledIncludingStory).toList(growable: false);

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
