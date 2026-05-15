import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/logging/webrtc_crash_logger.dart';

class UpdateDownloadException implements Exception {
  final String message;
  UpdateDownloadException(this.message);
  @override
  String toString() => 'UpdateDownloadException: $message';
}

typedef DownloadProgress = void Function(int received, int total);

/// 下载/校验所处阶段。供 UI 在"100% 之后到 install 之前"的空白期分阶段反馈，
/// 避免被误以为卡死。
enum DownloadPhase {
  /// 准备阶段：检查是否已有可复用的本地文件
  preparing,

  /// 正在从网络下载
  downloading,

  /// 下载完成，正在校验大小/MD5
  verifying,
}

typedef PhaseCallback = void Function(DownloadPhase phase);

/// 断点续传 + MD5 校验下载器。
class UpdateDownloader {
  final Dio _dio;

  UpdateDownloader({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              // receiveTimeout 不设，下载大文件可能耗时较长
            ));

  /// 下载 [url] 到 [savePath]，支持断点续传。
  /// 完成后校验 MD5，通过则将临时文件 rename 为最终路径。
  ///
  /// 优化：进入主下载流程前先检查 [savePath] 是否已存在且 size + MD5 完全匹配，
  /// 如果是，直接返回已存在的文件，跳过网络下载。这能让"下载完成但 install 卡住后
  /// 用户取消重试"的场景从"重下整个文件"变成"秒级进入安装阶段"。
  ///
  /// [onPhase] 用于 UI 感知"下载完成 → 校验中 → 准备安装"的阶段切换，
  /// 避免 100% 之后的空白期被误以为卡死。
  ///
  /// 返回最终文件。
  Future<File> download({
    required String url,
    required String savePath,
    required String expectedMd5,
    required int expectedSize,
    required DownloadProgress onProgress,
    CancelToken? cancelToken,
    PhaseCallback? onPhase,
  }) async {
    onPhase?.call(DownloadPhase.preparing);

    // === 已下载文件复用：savePath 已存在且 size + MD5 都匹配 → 直接返回 ===
    final finalFileEarly = File(savePath);
    if (finalFileEarly.existsSync()) {
      try {
        final existingSize = await finalFileEarly.length();
        if (existingSize == expectedSize) {
          onPhase?.call(DownloadPhase.verifying);
          final existingMd5 = await _calcMd5(finalFileEarly);
          if (existingMd5.toLowerCase() == expectedMd5.toLowerCase()) {
            _log('INFO', 'download',
                'reuse existing path=$savePath size=$existingSize');
            // 立即把进度推到 100%，UI 不会卡在 0%
            onProgress(existingSize, expectedSize);
            return finalFileEarly;
          }
          _log('INFO', 'download',
              'existing md5 mismatch, redownload path=$savePath');
        } else {
          _log('INFO', 'download',
              'existing size mismatch (got=$existingSize expected=$expectedSize), redownload');
        }
        // 校验失败 → 删掉重下
        await finalFileEarly.delete();
      } catch (e) {
        _log('WARN', 'download', 'check existing file failed: $e');
        // 出错也走正常下载流程
      }
    }

    final tmpPath = '$savePath.tmp';
    final tmpFile = File(tmpPath);
    final dir = tmpFile.parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);

    int alreadyDownloaded = 0;
    if (tmpFile.existsSync()) {
      alreadyDownloaded = await tmpFile.length();
      if (alreadyDownloaded >= expectedSize) {
        // 已经下满，可能上次校验失败遗留，删除重下
        await tmpFile.delete();
        alreadyDownloaded = 0;
      }
    }

    onPhase?.call(DownloadPhase.downloading);
    _log('INFO', 'download',
        'url=$url start=$alreadyDownloaded expected=$expectedSize');

    final raf = await tmpFile.open(mode: FileMode.append);
    try {
      final options = Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        headers: alreadyDownloaded > 0
            ? {'Range': 'bytes=$alreadyDownloaded-'}
            : null,
        // 对 206 / 200 都视为正常
        validateStatus: (code) => code == 200 || code == 206,
      );

      final resp = await _dio.getUri<ResponseBody>(
        Uri.parse(url),
        options: options,
        cancelToken: cancelToken,
      );
      final body = resp.data;
      if (body == null) {
        throw UpdateDownloadException('empty body');
      }

      int received = alreadyDownloaded;
      final stream = body.stream;
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = stream.listen(
        (chunk) async {
          sub.pause();
          try {
            await raf.writeFrom(chunk);
            received += chunk.length;
            onProgress(received, expectedSize);
            sub.resume();
          } catch (e) {
            sub.cancel();
            if (!completer.isCompleted) completer.completeError(e);
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;
    } finally {
      await raf.close();
    }

    onPhase?.call(DownloadPhase.verifying);

    // 校验大小
    final finalSize = await tmpFile.length();
    if (finalSize != expectedSize) {
      _log('ERROR', 'download',
          'size mismatch: got=$finalSize expected=$expectedSize');
      throw UpdateDownloadException(
          '文件大小不匹配（实际 $finalSize / 期望 $expectedSize）');
    }

    // 校验 MD5
    final actualMd5 = await _calcMd5(tmpFile);
    if (actualMd5.toLowerCase() != expectedMd5.toLowerCase()) {
      _log('ERROR', 'download', 'md5 mismatch: got=$actualMd5 expected=$expectedMd5');
      await tmpFile.delete();
      throw UpdateDownloadException('文件校验失败');
    }

    // rename
    final finalFile = File(savePath);
    if (finalFile.existsSync()) {
      await finalFile.delete();
    }
    final renamed = await tmpFile.rename(savePath);
    _log('INFO', 'download', 'done path=$savePath size=$finalSize');
    return renamed;
  }

  Future<String> _calcMd5(File f) async {
    final digest = await md5.bind(f.openRead()).first;
    return digest.toString();
  }

  void _log(String level, String op, String msg) {
    WebRtcCrashLogger.I.log(level, 'update', op, '-', msg);
  }
}
