import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import 'file_downloader.dart';
import 'update_api.dart';

/// 被控端下载服务。
/// 流程：
///   1. 顺序遍历三个 host，找到能拉到 launch.json 的那个
///   2. GET /StartChannel/release/launch.json（GBK 编码）
///   3. 取 files["被控端安装.exe"].md5
///   4. GET /StartChannel/release/{md5}.dat
///   5. 保存为"被控端安装.exe"
///   6. MD5 校验
class ControllerDownloader implements FileDownloader {
  static const String _launcherPath = '/StartChannel/release/launch.json';
  static const String _baseDownloadPath = '/StartChannel/release';
  static const String _kTargetFileName = '被控端安装.exe';

  @override
  String get targetFileName => _kTargetFileName;

  final Dio _dio;

  ControllerDownloader({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));

  /// 下载被控端安装文件到本地。
  @override
  Future<File> download({
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    // 1. 三 host 并发竞速拉 launch.json，最快返回 200 的获胜
    _stdoutLog('=== 被控端下载：开始竞速 ===');
    final String host;
    final Map<String, dynamic> json;
    try {
      final result = await UpdateApi().raceFetchManifest(
        _launcherPath,
        cancelToken: cancelToken,
        onLog: _stdoutLog,
      );
      host = result.host;
      // launch.json 是 GBK 编码（中文 key 会乱码 UTF-8 解码），_decodeBytes 内部
      // 先尝试 UTF-8 严格模式，失败 fallback 到 GBK
      final decoded = _decodeBytes(result.body);
      json = jsonDecode(decoded) as Map<String, dynamic>;
      _stdoutLog('✓ 选中 host=$host');
    } catch (e) {
      throw FileDownloadException('获取版本信息失败：$e');
    }

    // 2. 解析 md5
    final files = json['files'] as Map<String, dynamic>?;
    if (files == null) {
      throw FileDownloadException('版本信息格式错误（缺少 files）');
    }
    // 调试：打印所有 key（确认中文 key 是否正确解析）
    _stdoutLog('files keys 数量 = ${files.length}');
    _stdoutLog('files keys = ${files.keys.toList()}');
    _stdoutLog('查找 key = $targetFileName (codeUnits=${targetFileName.codeUnits})');
    final fileMeta = files[targetFileName] as Map<String, dynamic>?;
    if (fileMeta == null) {
      throw FileDownloadException('版本信息中找不到 $targetFileName');
    }
    final expectedMd5 = (fileMeta['md5'] as String?)?.trim();
    if (expectedMd5 == null || expectedMd5.isEmpty) {
      throw FileDownloadException('未找到文件 MD5');
    }
    _log('INFO', 'parseLauncher', 'md5=$expectedMd5');
    _stdoutLog('解析到 md5=$expectedMd5');

    // 3. 下载 dat
    final datUrl = '$host$_baseDownloadPath/$expectedMd5.dat';
    final saveDir = await _downloadDir();
    final savePath = '${saveDir.path}${Platform.pathSeparator}$targetFileName';
    final saveFile = File(savePath);
    if (saveFile.existsSync()) {
      await saveFile.delete();
    }
    _stdoutLog('→ 下载 dat: $datUrl');
    _stdoutLog('  保存到: $savePath');
    _log('INFO', 'downloadDat', 'url=$datUrl save=$savePath');

    try {
      await _dio.download(
        datUrl,
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
      _log('ERROR', 'md5Mismatch',
          'expected=$expectedMd5 actual=$actualMd5');
      try { await saveFile.delete(); } catch (_) {}
      throw FileDownloadException('文件校验失败（MD5 不匹配）');
    }

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

  /// 服务端返回的 launch.json 是 **GBK 编码**（无 charset 声明），
  /// 直接 utf8 解码会把中文 key 变成 `�` 替换字符。
  /// 这里先尝试严格 UTF-8 解码（兼容未来切换到 UTF-8 的情况），失败 fallback 到 GBK。
  String _decodeBytes(List<int> bytes) {
    try {
      // 严格模式：遇到非 UTF-8 字节立刻抛错
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      _stdoutLog('  (UTF-8 解码失败，fallback 到 GBK)');
      return gbk.decode(bytes);
    }
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'controller_dl', op, '-', msg);
  }

  /// 同时写到标准输出（VS Code/IDE 控制台）和 Flutter 日志通道。
  /// 用于让用户能直接在控制台看到完整下载链路。
  void _stdoutLog(String msg) {
    // ignore: avoid_print
    print('[ControllerDownload] $msg');
    developer.log(msg, name: 'ControllerDownload');
  }
}
