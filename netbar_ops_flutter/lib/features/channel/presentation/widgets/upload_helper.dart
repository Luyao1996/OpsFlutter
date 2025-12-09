// 上传辅助 - 条件导入入口
import 'dart:typed_data';

import 'upload_helper_stub.dart'
    if (dart.library.io) 'upload_helper_io.dart';

/// 上传文件项
class UploadFileItem {
  final String name;
  final String type;
  final bool isDirectory;
  final String relativePath;
  final Uint8List? bytes;

  UploadFileItem({
    required this.name,
    required this.type,
    required this.isDirectory,
    required this.relativePath,
    this.bytes,
  });
}

/// 平台文件辅助抽象接口
abstract class PlatformFileHelper {
  /// 选择目录并获取所有文件
  Future<List<UploadFileItem>> pickDirectory();

  /// 从路径读取目录内容（用于拖拽上传）
  Future<List<UploadFileItem>> readDirectoryFromPath(String path);

  /// 检查路径是否为目录
  bool isDirectory(String path);

  /// 从系统剪贴板读取文件路径（Windows 支持）
  Future<List<String>> getClipboardFilePaths();

  /// 从文件路径列表读取文件内容
  Future<List<UploadFileItem>> readFilesFromPaths(List<String> paths);
}

/// 获取平台文件辅助实例
PlatformFileHelper get platformFileHelper => getPlatformFileHelper();

