import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'upload_helper.dart';

/// 平台文件辅助 - IO 实现 (非 Web)
class _PlatformFileHelperIO implements PlatformFileHelper {
  @override
  Future<List<UploadFileItem>> pickDirectory() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return [];
    return readDirectoryFromPath(dirPath);
  }

  @override
  Future<List<UploadFileItem>> readDirectoryFromPath(String path) async {
    final root = Directory(path);
    if (!await root.exists()) return [];

    final rootName = p.basename(path);
    final normalizedRoot = rootName.replaceAll('\\', '/');

    final List<UploadFileItem> items = [];

    // 添加根目录
    items.add(UploadFileItem(
      name: rootName,
      type: 'folder',
      isDirectory: true,
      relativePath: normalizedRoot,
    ));

    // 递归遍历目录
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final rel = entity.path.substring(root.path.length + 1).replaceAll('\\', '/');
      if (rel.isEmpty) continue;
      final relPath = '$normalizedRoot/$rel'.replaceAll('\\', '/');

      if (entity is Directory) {
        final name = p.basename(entity.path);
        items.add(UploadFileItem(
          name: name,
          type: 'folder',
          isDirectory: true,
          relativePath: relPath,
        ));
      } else if (entity is File) {
        final bytes = await entity.readAsBytes();
        final name = p.basename(entity.path);
        items.add(UploadFileItem(
          name: name,
          type: _getFileType(name),
          isDirectory: false,
          relativePath: relPath,
          bytes: bytes,
        ));
      }
    }

    return items;
  }

  @override
  bool isDirectory(String path) {
    return FileSystemEntity.isDirectorySync(path);
  }

  @override
  Future<List<String>> getClipboardFilePaths() async {
    if (!Platform.isWindows) return [];

    try {
      // 使用 PowerShell 读取剪贴板中的文件路径
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'Get-Clipboard -Format FileDropList | ForEach-Object { \$_.FullName }',
        ],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );

      if (result.exitCode != 0) return [];

      final output = result.stdout as String;
      if (output.trim().isEmpty) return [];

      // 解析文件路径列表
      final paths = output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      return paths;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<UploadFileItem>> readFilesFromPaths(List<String> paths) async {
    final List<UploadFileItem> items = [];

    for (final path in paths) {
      try {
        if (isDirectory(path)) {
          // 是目录，递归读取
          final dirItems = await readDirectoryFromPath(path);
          items.addAll(dirItems);
        } else {
          // 是文件
          final file = File(path);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final name = p.basename(path);
            items.add(UploadFileItem(
              name: name,
              type: _getFileType(name),
              isDirectory: false,
              relativePath: name,
              bytes: bytes,
            ));
          }
        }
      } catch (e) {
        // 忽略读取失败的文件
      }
    }

    return items;
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'exe':
      case 'bat':
      case 'cmd':
        return 'exe';
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'json':
      case 'xml':
        return 'config';
      default:
        return 'other';
    }
  }
}

PlatformFileHelper getPlatformFileHelper() => _PlatformFileHelperIO();

