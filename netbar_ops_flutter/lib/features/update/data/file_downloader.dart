import 'dart:io';

import 'package:dio/dio.dart';

/// 通用文件下载接口。被 [FileDownloadDialog] 消费。
abstract class FileDownloader {
  /// 保存到本地的文件名（不含路径）。
  /// 可在 download 完成后才确定（如根据版本号生成），但 dialog 显示时希望已知；
  /// 实现类应在 download 启动时就设好默认值。
  String get targetFileName;

  /// 执行下载。
  Future<File> download({
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  });
}

/// 下载过程中的可读异常。
class FileDownloadException implements Exception {
  final String message;
  FileDownloadException(this.message);
  @override
  String toString() => message;
}
