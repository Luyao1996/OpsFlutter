import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import 'file_downloader.dart';
import 'update_api.dart';

/// Android APK 下载服务（PC 用户下载到本机，可传给同事/扫码到手机）。
///
/// 流程：
///   1. 顺序遍历三个 host，找到能拉到 version.json 的那个
///   2. 解析 android.releases[0] -> path / md5 / version / buildNumber
///   3. GET <host><path> 下载 APK
///   4. 保存为 NetBar-Ops-{version}-{build}.apk（无版本号信息则用固定名）
///   5. MD5 校验
class ApkDownloader implements FileDownloader {
  static const String _versionJsonPath = '/netbaropsflutter/version.json';
  static const String _kFallbackFileName = 'NetBar-Ops.apk';

  final Dio _dio;

  /// 真正的文件名在 download 内部根据 version.json 内容生成；
  /// 在那之前先返回 fallback，以便 dialog 初始显示。
  String _fileName = _kFallbackFileName;

  @override
  String get targetFileName => _fileName;

  ApkDownloader({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  @override
  Future<File> download({
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    // 1. 三 host 并发竞速拉 version.json，最快返回 200 的获胜
    _stdoutLog('=== APK 下载：开始竞速 ===');
    final String host;
    final Map<String, dynamic> json;
    try {
      final result = await UpdateApi().raceFetchManifest(
        _versionJsonPath,
        cancelToken: cancelToken,
        onLog: _stdoutLog,
      );
      host = result.host;
      // version.json 是 UTF-8（release 工具生成）
      final decoded = utf8.decode(result.body, allowMalformed: true);
      json = jsonDecode(decoded) as Map<String, dynamic>;
      _stdoutLog('✓ 选中 host=$host');
    } catch (e) {
      throw FileDownloadException('获取版本信息失败：$e');
    }

    // 2. 解析 android.releases[0]
    final android = json['android'] as Map<String, dynamic>?;
    if (android == null) {
      throw FileDownloadException('版本信息缺少 android 节');
    }
    final releases = android['releases'] as List?;
    if (releases == null || releases.isEmpty) {
      throw FileDownloadException('暂无可下载的 APK 版本');
    }
    final latest = releases.first as Map<String, dynamic>;
    final relativePath = latest['path'] as String?;
    final expectedMd5 = (latest['md5'] as String?)?.trim();
    final version = latest['version'] as String?;
    final build = (latest['buildNumber'] as num?)?.toInt();
    final size = (latest['size'] as num?)?.toInt() ?? 0;

    if (relativePath == null || relativePath.isEmpty) {
      throw FileDownloadException('版本信息缺少 path');
    }
    if (expectedMd5 == null || expectedMd5.isEmpty) {
      throw FileDownloadException('版本信息缺少 md5');
    }

    // 文件名带版本号便于识别
    if (version != null && build != null) {
      _fileName = 'NetBar-Ops-$version-$build.apk';
    } else {
      _fileName = _kFallbackFileName;
    }
    _stdoutLog('版本 $version (build $build), size=$size, md5=$expectedMd5');
    _stdoutLog('文件名: $_fileName');

    // 3. 下载 APK
    final apkUrl = '$host$relativePath';
    final saveDir = await _downloadDir();
    final savePath = '${saveDir.path}${Platform.pathSeparator}$_fileName';
    final saveFile = File(savePath);
    if (saveFile.existsSync()) {
      await saveFile.delete();
    }
    _stdoutLog('→ 下载: $apkUrl');
    _stdoutLog('  保存到: $savePath');
    _log('INFO', 'downloadApk', 'url=$apkUrl save=$savePath');

    try {
      await _dio.download(
        apkUrl,
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          validateStatus: (code) => code != null && code < 400,
        ),
      );
    } catch (e) {
      if (saveFile.existsSync()) {
        try { await saveFile.delete(); } catch (_) {}
      }
      throw FileDownloadException('下载失败：$e');
    }

    // 4. MD5 校验
    final actualMd5 = await _calcMd5(saveFile);
    if (actualMd5.toLowerCase() != expectedMd5.toLowerCase()) {
      _stdoutLog('  ✗ MD5 不匹配 expected=$expectedMd5 actual=$actualMd5');
      _log('ERROR', 'md5Mismatch', 'expected=$expectedMd5 actual=$actualMd5');
      try { await saveFile.delete(); } catch (_) {}
      throw FileDownloadException('文件校验失败（MD5 不匹配）');
    }

    _stdoutLog('下载完成: $savePath');
    _log('INFO', 'downloadComplete', 'path=$savePath');
    return saveFile;
  }

  Future<Directory> _downloadDir() async {
    Directory? dir;
    try {
      dir = await getDownloadsDirectory();
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<String> _calcMd5(File f) async {
    final digest = await md5.bind(f.openRead()).first;
    return digest.toString();
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'apk_dl', op, '-', msg);
  }

  void _stdoutLog(String msg) {
    // ignore: avoid_print
    print('[ApkDownload] $msg');
    developer.log(msg, name: 'ApkDownload');
  }
}
