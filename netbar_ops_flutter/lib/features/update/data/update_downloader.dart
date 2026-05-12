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
  /// 返回最终文件。
  Future<File> download({
    required String url,
    required String savePath,
    required String expectedMd5,
    required int expectedSize,
    required DownloadProgress onProgress,
    CancelToken? cancelToken,
  }) async {
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
