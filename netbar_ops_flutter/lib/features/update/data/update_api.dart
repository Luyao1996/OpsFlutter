import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import '../domain/models/version_manifest.dart';

/// version.json 拉取 + 多域名择优。
///
/// 双源策略：新源（RustFS，上传下载同一接口）优先；
/// 新源不可达或对应文件不存在（404）时回退老源（阿里 OSS）竞速。
class UpdateApi {
  /// 新源（RustFS）。发布工具双写的主源。
  static const String primaryHost =
      'http://server.guanliyuangong.com:9000/ops-package';

  /// 老源（阿里 OSS）。仅作回退；/StartChannel 等历史内容只存在于老源。
  static const List<String> legacyHosts = [
    'http://xemaly.wangkaguanli.com:8866',
    'https://xemoss.wangkaguanli.com',
    'http://xem.oss-cn-hangzhou.aliyuncs.com',
  ];

  /// 全部候选（新优先），供下载回退按序遍历。
  static const List<String> hosts = [primaryHost, ...legacyHosts];

  static const String manifestPath = '/netbaropsflutter/version.json';

  static const String _spHostKey = 'update.fastest_host';
  static const String _spHostExpiryKey = 'update.fastest_host_expiry';
  static const Duration _hostCacheTtl = Duration(hours: 1);

  final Dio _dio;

  UpdateApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 10),
            ));

  /// 选出可用域名：新源可达就用新源；否则老源竞速。全部失败返回 null。
  ///
  /// 缓存语义：缓存命中且是新源 → 直接复用；缓存是老源也要先探一次新源，
  /// 保证新源恢复后立刻切回（否则最长 1 小时都读老源的旧 version.json）。
  Future<String?> pickFastestHost() async {
    final cached = await _loadCachedHost();
    if (cached == primaryHost) return cached;

    try {
      await _probe(primaryHost).timeout(const Duration(seconds: 3));
      await _cacheHost(primaryHost);
      _log('INFO', 'pickFastestHost', 'host=$primaryHost (primary)');
      return primaryHost;
    } catch (e) {
      _log('WARN', 'pickFastestHost', 'primary unreachable: $e');
    }

    if (cached != null) return cached;

    try {
      final winner =
          await _race(legacyHosts).timeout(const Duration(seconds: 3));
      await _cacheHost(winner);
      _log('INFO', 'pickFastestHost', 'host=$winner (legacy)');
      return winner;
    } catch (e) {
      _log('WARN', 'pickFastestHost', 'all hosts failed: $e');
      return null;
    }
  }

  Future<String> _race(List<String> hostList) {
    final completer = Completer<String>();
    var failed = 0;
    for (final h in hostList) {
      _probe(h).then((_) {
        if (!completer.isCompleted) completer.complete(h);
      }).catchError((Object e) {
        failed++;
        if (failed >= hostList.length && !completer.isCompleted) {
          completer.completeError(e);
        }
      });
    }
    return completer.future;
  }

  Future<void> _probe(String host) async {
    final resp = await _dio.headUri(Uri.parse('$host$manifestPath'),
        options: Options(
          followRedirects: true,
          // 任何 2xx/3xx 视为可达；某些 OSS 对 HEAD 返回 200。
          validateStatus: (code) => code != null && code < 400,
          receiveTimeout: const Duration(seconds: 2),
        ));
    if (resp.statusCode == null || resp.statusCode! >= 400) {
      throw DioException(
          requestOptions: resp.requestOptions, message: 'bad status');
    }
  }

  /// 拉取指定 manifest 路径：新源优先，失败/404 回退老源竞速。
  ///
  /// 新源命中（200）直接返回；新源没有该文件（如 /StartChannel/... 只在老源上）
  /// 或不可达时，落回老源三域名并发竞速（原有行为）。
  ///
  /// 返回 (host, body)。所有 host 都失败时抛 [DioException] 或封装异常。
  Future<({String host, List<int> body})> raceFetchManifest(
    String path, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 15),
    void Function(String msg)? onLog,
  }) async {
    // 新源单独尝试，最多 8 秒，避免占满整个 timeout 预算
    final primaryBudget = timeout < const Duration(seconds: 8)
        ? timeout
        : const Duration(seconds: 8);
    onLog?.call('→ 优先尝试新源: $primaryHost$path');
    try {
      final resp = await _dio
          .getUri<List<int>>(
            Uri.parse('$primaryHost$path'),
            options: Options(
              responseType: ResponseType.bytes,
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (code) => code != null && code < 400,
            ),
            cancelToken: cancelToken,
          )
          .timeout(primaryBudget);
      if (resp.statusCode == 200 && resp.data != null) {
        onLog?.call('  ✓ 新源命中 (length=${resp.data!.length})');
        _log('INFO', 'raceFetchManifest', 'win=$primaryHost path=$path');
        return (host: primaryHost, body: resp.data!);
      }
      onLog?.call('  ✗ 新源 HTTP ${resp.statusCode}，回退老源');
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) rethrow;
      onLog?.call('  ✗ 新源失败: $e，回退老源');
      _log('WARN', 'raceFetchManifest', 'primary failed: $e, fallback');
    }
    return _raceFetchFromHosts(
      legacyHosts,
      path,
      cancelToken: cancelToken,
      timeout: timeout,
      onLog: onLog,
    );
  }

  /// 在给定 host 列表上并发竞速 GET [path]，第一个返回 200 的获胜，其余被取消。
  Future<({String host, List<int> body})> _raceFetchFromHosts(
    List<String> hostList,
    String path, {
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 15),
    void Function(String msg)? onLog,
  }) {
    final completer = Completer<({String host, List<int> body})>();
    final tokens = <CancelToken>[];
    var failed = 0;
    Object? lastError;

    void cancelOthers(CancelToken keep) {
      for (final t in tokens) {
        if (t != keep && !t.isCancelled) {
          t.cancel('another host won');
        }
      }
    }

    // 监听外部 cancelToken
    cancelToken?.whenCancel.then((_) {
      if (completer.isCompleted) return;
      for (final t in tokens) {
        if (!t.isCancelled) t.cancel('outer cancelled');
      }
      completer.completeError(StateError('cancelled'));
    });

    onLog?.call('hosts 列表 = $hostList');
    for (final h in hostList) {
      final url = '$h$path';
      final token = CancelToken();
      tokens.add(token);
      onLog?.call('→ 并发尝试: $url');

      _dio.getUri<List<int>>(
        Uri.parse(url),
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
          validateStatus: (code) => code != null && code < 400,
        ),
        cancelToken: token,
      ).then((resp) {
        if (completer.isCompleted) return;
        if (resp.statusCode == 200 && resp.data != null) {
          onLog?.call('  ✓ 命中: $h (length=${resp.data!.length})');
          _log('INFO', 'raceFetchManifest', 'win=$h path=$path');
          completer.complete((host: h, body: resp.data!));
          cancelOthers(token);
        } else {
          failed++;
          lastError = 'HTTP ${resp.statusCode}';
          onLog?.call('  ✗ $h HTTP ${resp.statusCode}');
          if (failed >= hostList.length && !completer.isCompleted) {
            completer.completeError(
              StateError('所有下载源都不可用: $lastError'),
            );
          }
        }
      }).catchError((Object e) {
        if (completer.isCompleted) return;
        // 被自己取消（其他 host 赢了 / 外部取消）不计入失败
        if (e is DioException && e.type == DioExceptionType.cancel) {
          return;
        }
        failed++;
        lastError = e;
        onLog?.call('  ✗ $h 失败: $e');
        if (failed >= hostList.length && !completer.isCompleted) {
          completer.completeError(
            StateError('所有下载源都不可用: $lastError'),
          );
        }
      });
    }

    return completer.future.timeout(timeout, onTimeout: () {
      for (final t in tokens) {
        if (!t.isCancelled) t.cancel('timeout');
      }
      throw StateError('获取版本信息超时');
    });
  }

  /// 取最新 Android APK 的完整下载 URL（用于"扫码下载手机版"等场景）。
  /// 失败返回 null。内部走完整流程：测速 → 拉 manifest → 取最新 release 路径。
  Future<String?> fetchLatestApkUrl() async {
    final host = await pickFastestHost();
    if (host == null) return null;
    final manifest = await fetchManifest(host);
    if (manifest == null) return null;
    final android = manifest.android;
    if (android == null || android.releases.isEmpty) return null;
    return '$host${android.releases.first.path}';
  }

  /// 从指定 host 拉取 version.json（不落盘）。
  Future<VersionManifest?> fetchManifest(String host) async {
    try {
      final resp = await _dio.getUri<String>(
        Uri.parse('$host$manifestPath'),
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (resp.statusCode != 200 || resp.data == null) {
        _log('WARN', 'fetchManifest',
            'http=${resp.statusCode} host=$host');
        return null;
      }
      final json = jsonDecode(resp.data!) as Map<String, dynamic>;
      return VersionManifest.fromJson(json);
    } catch (e) {
      _log('WARN', 'fetchManifest', 'error=$e host=$host');
      return null;
    }
  }

  Future<String?> _loadCachedHost() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final h = sp.getString(_spHostKey);
      final expiry = sp.getInt(_spHostExpiryKey) ?? 0;
      if (h == null || expiry == 0) return null;
      if (DateTime.now().millisecondsSinceEpoch > expiry) return null;
      return h;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheHost(String host) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_spHostKey, host);
      await sp.setInt(
        _spHostExpiryKey,
        DateTime.now().add(_hostCacheTtl).millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'update', op, '-', msg);
  }
}
