// Web 文件选择抽象接口
// 用于条件导入，支持在 Web 和 IO 平台上选择目录
import 'dart:typed_data';

import 'web_file_picker_stub.dart'
    if (dart.library.html) 'web_file_picker_web.dart';

/// Web 文件信息数据类
class WebFileInfo {
  final String name;
  final String relativePath;
  final Uint8List bytes;
  final bool isDirectory;

  WebFileInfo({
    required this.name,
    required this.relativePath,
    required this.bytes,
    required this.isDirectory,
  });
}

/// Web 文件选择器接口
abstract class WebFilePicker {
  /// 是否支持目录选择
  bool get supportsDirectory;

  /// 选择目录（仅 Web 支持）
  Future<List<WebFileInfo>> pickDirectory();

  /// 选择多个文件
  Future<List<WebFileInfo>> pickFiles();
}

/// 获取 Web 文件选择器实例
WebFilePicker get webFilePicker => getWebFilePicker();

