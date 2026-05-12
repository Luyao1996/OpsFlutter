import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import '../data/installer.dart';
import '../data/installer_factory.dart';
import '../data/update_api.dart';
import '../data/update_downloader.dart';
import 'models/release_info.dart';
import 'models/version_manifest.dart';
import 'update_check_result.dart';

class UpdateService {
  final UpdateApi _api;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;

  UpdateService({
    UpdateApi? api,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
  })  : _api = api ?? UpdateApi(),
        _downloader = downloader ?? UpdateDownloader(),
        _installer = installer ?? createInstaller();

  /// 启动时检查。所有异常都吞掉，最坏情况返回 skipped。
  Future<UpdateCheckResult> check() async {
    try {
      final platform = _currentPlatform();
      if (platform == null) {
        _log('INFO', 'check', 'platform not supported, skip');
        return UpdateCheckResult.skipped();
      }

      final host = await _api.pickFastestHost();
      if (host == null) {
        _log('WARN', 'check', 'no reachable host, skip');
        return UpdateCheckResult.skipped();
      }

      final manifest = await _api.fetchManifest(host);
      if (manifest == null) {
        _log('WARN', 'check', 'fetch manifest failed, skip');
        return UpdateCheckResult.skipped();
      }

      final local = await _localPackageInfo();

      final pm = manifest.forPlatform(platform);
      if (pm == null || pm.releases.isEmpty) {
        _log('INFO', 'check', 'no releases for platform=$platform');
        return UpdateCheckResult.upToDate(local.version, local.build);
      }

      final latest = pm.latest!;
      _log('INFO', 'check',
          'localVersion=${local.version} localBuild=${local.build} latest=${latest.buildNumber} min=${pm.minSupportedBuild}');

      if (local.build >= latest.buildNumber) {
        return UpdateCheckResult.upToDate(local.version, local.build);
      }

      final logs = pm.changelogsSince(local.build);
      final isForced = latest.forceUpdate || local.build < pm.minSupportedBuild;
      return UpdateCheckResult(
        status: isForced ? UpdateStatus.forced : UpdateStatus.optional,
        latest: latest,
        aggregatedChangelogs: logs,
        host: host,
        localVersion: local.version,
        localBuildNumber: local.build,
      );
    } catch (e, st) {
      _log('ERROR', 'check', 'unhandled error=$e stack=$st');
      return UpdateCheckResult.skipped();
    }
  }

  /// 下载并安装。
  Future<void> downloadAndInstall(
    ReleaseInfo release,
    String host, {
    required DownloadProgress onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = '$host${release.path}';
    final saveDir = await _downloadDir();
    final fileName = release.path.split('/').last;
    final savePath = '${saveDir.path}${Platform.pathSeparator}$fileName';

    _log('INFO', 'downloadAndInstall',
        'url=$url save=$savePath size=${release.size}');

    final file = await _downloader.download(
      url: url,
      savePath: savePath,
      expectedMd5: release.md5,
      expectedSize: release.size,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );

    await _installer.install(file);
  }

  // -------- helpers --------

  String? _currentPlatform() {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  Future<({String version, int build})> _localPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return (
        version: info.version,
        build: int.tryParse(info.buildNumber) ?? 0,
      );
    } catch (e) {
      _log('WARN', 'localPackageInfo', 'error=$e');
      return (version: '', build: 0);
    }
  }

  Future<Directory> _downloadDir() async {
    Directory base;
    if (Platform.isAndroid) {
      base = await getApplicationSupportDirectory();
    } else {
      final tmp = await getTemporaryDirectory();
      base = tmp;
    }
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'update', op, '-', msg);
  }
}
