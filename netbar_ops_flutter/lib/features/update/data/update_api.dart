import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import '../domain/models/version_manifest.dart';

/// version.json 拉取 + 多域名测速。
class UpdateApi {
  static const List<String> hosts = [
    'http://xemaly.wangkaguanli.com:8866',
    'https://xemoss.wangkaguanli.com',
    'http://xem.oss-cn-hangzhou.aliyuncs.com',
  ];

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

  /// 选出最快的域名。1 小时内有缓存则直接复用。全部失败返回 null。
  Future<String?> pickFastestHost() async {
    final cached = await _loadCachedHost();
    if (cached != null) return cached;

    try {
      final winner = await _race(hosts).timeout(const Duration(seconds: 3));
      await _cacheHost(winner);
      _log('INFO', 'pickFastestHost', 'host=$winner');
      return winner;
    } catch (e) {
      _log('WARN', 'pickFastestHost', 'all hosts failed: $e');
      return null;
    }
  }

  Future<String> _race(List<String> hosts) {
    final completer = Completer<String>();
    var failed = 0;
    for (final h in hosts) {
      _probe(h).then((_) {
        if (!completer.isCompleted) completer.complete(h);
      }).catchError((Object e) {
        failed++;
        if (failed >= hosts.length && !completer.isCompleted) {
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
