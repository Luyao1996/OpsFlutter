import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'game_constants.dart';
import 'game_models.dart';

/// game_library HTTP API 封装
///
/// 设计要点（与 Web 端 toolboxPage 对齐）：
/// 1. 使用独立 Dio 实例，不挂任何业务拦截器、不带 Authorization
///    （后端 game_library 是网吧本地服务，CORS 全开、无需鉴权；
///     不带 token 也避免触发主站 401 流程）
/// 2. 通过 https://<subdomain_full> 直连
/// 3. 写接口（do_download / cancle_download / top_download）参数走 URL query，body 为空
/// 4. 4MB 级响应：ResponseType.plain + compute(jsonDecode) 在 worker isolate 解析
/// 5. gzip 由 HttpClient autoUncompress 自动处理，无需手动解压
class GameLibraryApi {
  GameLibraryApi(this.subdomainFull);

  /// 网吧 subdomain_full，例如 "xxxx.frps.wwls.net"
  final String subdomainFull;

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: const {'Accept': 'application/json'},
  ));

  String _buildUrl(String path, [Map<String, dynamic>? query]) {
    var url = 'https://$subdomainFull$path';
    if (query != null && query.isNotEmpty) {
      final pairs = <String>[];
      query.forEach((k, v) {
        if (v == null) return;
        final s = v.toString();
        if (s.isEmpty) return;
        pairs.add('${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(s)}');
      });
      if (pairs.isNotEmpty) url += '?${pairs.join('&')}';
    }
    return url;
  }

  /// GET /game_library/lists
  /// 4MB 级响应，主线程零阻塞解析
  Future<GameLibraryListsResult> getGameLists({String? platform}) async {
    final url = _buildUrl('/game_library/lists',
        platform != null ? {'platform': platform} : null);
    final resp = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = resp.data;
    if (raw == null || raw.isEmpty) {
      return GameLibraryListsResult(games: [], snapshots: {});
    }
    return await compute(_parseListsRaw, raw);
  }

  /// GET /game_library/downloading
  /// 单次响应通常很小（仅下载中的几条），走主线程解析即可
  Future<GameLibraryDownloadingResult> getDownloading({String? platform}) async {
    final url = _buildUrl('/game_library/downloading',
        platform != null ? {'platform': platform} : null);
    final resp = await _dio.get<dynamic>(url);
    final data = resp.data;
    if (data is! Map) {
      return GameLibraryDownloadingResult(tasks: [], snapshots: {});
    }
    return _parseDownloading(data.cast<String, dynamic>());
  }

  /// GET /game_library/disk_info?letter=R,T
  /// 查询指定盘符的容量。letter 逗号分隔、大小写不敏感（与 Web 端一致）。
  /// 响应：{ "R:": {err, available_bytes, total_bytes, volume_label, is_ssd, ...}, ..., "ts": ... }
  /// 返回以盘符首字母大写为 key 的 map；letter 为空或请求失败返回空 map（不抛、不阻断下载）。
  Future<Map<String, DiskInfo>> getDiskInfo({required String letter}) async {
    if (letter.isEmpty) return const {};
    final url = _buildUrl('/game_library/disk_info', {'letter': letter});
    try {
      final resp = await _dio.get<dynamic>(url);
      final data = resp.data;
      if (data is! Map) return const {};
      final out = <String, DiskInfo>{};
      data.forEach((k, v) {
        final key = k.toString();
        // 仅盘符键形如 "R:"；排除顶层 ts 等非盘符字段
        if (!RegExp(r'^[A-Za-z]:$').hasMatch(key)) return;
        if (v is! Map) return;
        final lt = key[0].toUpperCase();
        out[lt] = DiskInfo.fromJson(lt, v.cast<String, dynamic>());
      });
      return out;
    } on DioException {
      return const {};
    } catch (_) {
      return const {};
    }
  }

  /// POST /game_library/do_download?seat=&platform=&gid=
  Future<GameOpResult> doDownload({
    required String seat,
    required String platform,
    required int gid,
    String? from,
    String? letter,
  }) =>
      _opWrite('/game_library/do_download', {
        'seat': seat,
        'platform': platform,
        'gid': gid,
        if (from != null) 'from': from,
        if (letter != null && letter.isNotEmpty) 'letter': letter,
      });

  /// POST /game_library/cancle_download?seat=&platform=&gid=
  /// 注意拼写：cancle 历史遗留
  Future<GameOpResult> cancleDownload({
    required String seat,
    required String platform,
    required int gid,
  }) =>
      _opWrite('/game_library/cancle_download', {
        'seat': seat,
        'platform': platform,
        'gid': gid,
      });

  /// POST /game_library/top_download?seat=&platform=&gid=
  /// story 平台不支持，调用方需自行拦截
  Future<GameOpResult> topDownload({
    required String seat,
    required String platform,
    required int gid,
  }) =>
      _opWrite('/game_library/top_download', {
        'seat': seat,
        'platform': platform,
        'gid': gid,
      });

  /// POST /game_library/delete_game?platform=&gid=
  /// ⚠️ 仅本机回环允许（127.x/::1/localhost），跨机一律 403
  /// 调用方需处理 403 的专属文案
  Future<GameOpResult> deleteGame({
    required String platform,
    required int gid,
  }) =>
      _opWrite('/game_library/delete_game', {
        'platform': platform,
        'gid': gid,
      });

  /// GET /game_library/config
  /// 返回 raw map；调用方通过 RecyclePlan.fromConfigJson 提取 .recycle
  Future<Map<String, dynamic>?> getGameConfig() async {
    final url = _buildUrl('/game_library/config');
    try {
      final resp = await _dio.get<dynamic>(url);
      final data = resp.data;
      if (data is Map) return data.cast<String, dynamic>();
      return null;
    } on DioException {
      return null; // 失败时静默返回 null，调用方按未配置处理
    }
  }

  /// POST /game_library/delete_plan
  /// 整体替换式：每次都要传完整对象（非 merge patch）
  /// 入参用 UI 视角的 plan；内部做 100-X 反转 + 强制 platforms 规则
  /// 返回 { ok, status, plan?, timerActive?, error? }：plan 是后端回填后的真实值（含 forced-false）
  Future<RecyclePlanSaveResult> saveRecyclePlan({
    required RecyclePlan plan,
    required bool enabled,
    bool clearAll = false,
  }) async {
    final url = _buildUrl('/game_library/delete_plan');
    final ftUi = plan.freeThresholdUi;
    final apiFt = ftUi != null ? (100 - ftUi) : 0;
    // platforms：enabled 时强制 icafe8/cloud=true、goodgame/story=false（后端也会强制）
    // disabled 时传空对象，等价"关闭"
    final platforms = enabled
        ? const {
            kPlatformIcafe8: true,
            kPlatformCloud: true,
            kPlatformGoodgame: false,
            kPlatformStory: false,
          }
        : const <String, bool>{};
    // clearAll：删除任务——只发空值最短形式（文档「关闭快捷路径」），不传
    // free_threshold/retain_days，避免 0 经 100-X 反转污染成 UI 100%（其它字段缺省）。
    final body = clearAll
        ? <String, dynamic>{
            'platforms': const <String, bool>{},
            'weekdays': const <int>[],
            'time': '',
          }
        : <String, dynamic>{
            'free_threshold': apiFt,
            'retain_days': plan.retainDays,
            'weekdays': plan.weekdays,
            'time': plan.time,
            'del_flags': plan.delFlags,
            'platforms': platforms,
          };
    try {
      final resp = await _dio.post<dynamic>(
        url,
        data: body,
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.json,
        ),
      );
      final status = resp.statusCode ?? 0;
      final data = resp.data;
      if (data is Map) {
        final root = data.cast<String, dynamic>();
        return RecyclePlanSaveResult(
          ok: status >= 200 && status < 300,
          status: status,
          plan: RecyclePlan.fromConfigJson(root),
          timerActive:
              root['timer_active'] is bool ? root['timer_active'] as bool : null,
        );
      }
      return RecyclePlanSaveResult(
        ok: status >= 200 && status < 300,
        status: status,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final body = e.response?.data;
      String? error;
      if (body is Map) {
        error = (body['message'] ?? body['error'])?.toString();
      } else if (body is String) {
        error = body;
      }
      error ??= e.message;
      return RecyclePlanSaveResult(ok: false, status: status, error: error);
    }
  }

  Future<GameOpResult> _opWrite(String path, Map<String, dynamic> query) async {
    final url = _buildUrl(path, query);
    try {
      final resp = await _dio.post<dynamic>(url);
      final status = resp.statusCode ?? 0;
      final data = resp.data;
      if (data is! Map) {
        return GameOpResult(
          ok: status >= 200 && status < 300,
          status: status,
          error: data == null ? null : data.toString(),
        );
      }
      return _parseOpResult(status, data.cast<String, dynamic>());
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final body = e.response?.data;
      String? error;
      if (body is Map) {
        error = (body['message'] ?? body['error'])?.toString();
      } else if (body is String) {
        error = body;
      }
      error ??= e.message;
      return GameOpResult(ok: false, status: status, error: error);
    }
  }
}

/// /lists 解析：跑在 worker isolate（compute 入口必须是顶层/静态函数）
GameLibraryListsResult _parseListsRaw(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    return GameLibraryListsResult(games: [], snapshots: {});
  }
  return _parseLists(decoded.cast<String, dynamic>());
}

GameLibraryListsResult _parseLists(Map<String, dynamic> data) {
  final platforms = data['platforms'];
  if (platforms is! Map) {
    return GameLibraryListsResult(games: [], snapshots: {});
  }
  final games = <GameItem>[];
  final snapshots = <String, PlatformSnapshot>{};
  for (final p in kAllPlatforms) {
    final snap = platforms[p];
    if (snap is! Map) continue;
    final snapMap = snap.cast<String, dynamic>();
    snapshots[p] = PlatformSnapshot.fromJson(snapMap, p);
    final items = snapMap['items'];
    if (items is Map) {
      items.forEach((_, v) {
        if (v is Map) {
          games.add(GameItem.fromJson(v.cast<String, dynamic>(), p));
        }
      });
    }
  }
  return GameLibraryListsResult(games: games, snapshots: snapshots);
}

GameLibraryDownloadingResult _parseDownloading(Map<String, dynamic> data) {
  final platforms = data['platforms'];
  if (platforms is! Map) {
    return GameLibraryDownloadingResult(tasks: [], snapshots: {});
  }
  final tasks = <DownloadTask>[];
  final snapshots = <String, PlatformSnapshot>{};
  for (final p in kAllPlatforms) {
    final snap = platforms[p];
    if (snap is! Map) continue;
    final snapMap = snap.cast<String, dynamic>();
    snapshots[p] = PlatformSnapshot.fromJson(snapMap, p);
    final items = snapMap['items'];
    if (items is Map) {
      items.forEach((_, v) {
        if (v is Map) {
          tasks.add(DownloadTask.fromJson(v.cast<String, dynamic>(), p));
        }
      });
    }
  }
  return GameLibraryDownloadingResult(tasks: tasks, snapshots: snapshots);
}

GameOpResult _parseOpResult(int status, Map<String, dynamic> body) {
  // 后端返回示例：{ "results": { "12345": "ok" }, "cancelled": {...} }
  // 也可能整体包了一层 data
  final inner = (body['data'] is Map)
      ? (body['data'] as Map).cast<String, dynamic>()
      : body;
  final resultsMap = <int, String>{};
  final rawResults = inner['results'];
  if (rawResults is Map) {
    rawResults.forEach((k, v) {
      final gid = int.tryParse(k.toString());
      if (gid != null) resultsMap[gid] = v?.toString() ?? '';
    });
  }
  CancelledTask? cancelled;
  final rawCancelled = inner['cancelled'];
  if (rawCancelled is Map) {
    cancelled = CancelledTask.fromJson(rawCancelled.cast<String, dynamic>());
  }
  return GameOpResult(
    ok: status >= 200 && status < 300,
    status: status,
    results: resultsMap,
    cancelled: cancelled,
  );
}

class RecyclePlanSaveResult {
  final bool ok;
  final int status;
  final RecyclePlan? plan;
  final bool? timerActive;
  final String? error;
  RecyclePlanSaveResult({
    required this.ok,
    required this.status,
    this.plan,
    this.timerActive,
    this.error,
  });
}
