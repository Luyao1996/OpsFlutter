import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 文件图标组件 - 根据文件类型显示不同图标
class FileIcon extends StatelessWidget {
  final String type;
  final bool isDirectory;
  final double size;

  const FileIcon({
    super.key,
    required this.type,
    required this.isDirectory,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    if (isDirectory) {
      return Icon(
        LucideIcons.folderClosed,
        size: size,
        color: const Color(0xFF60A5FA), // blue-400
      );
    }

    switch (type.toLowerCase()) {
      case 'exe':
        return Icon(
          LucideIcons.fileTerminal,
          size: size,
          color: const Color(0xFF2563EB), // blue-600
        );
      case 'config':
        return Icon(
          LucideIcons.fileCode,
          size: size,
          color: const Color(0xFF16A34A), // green-600
        );
      case 'archive':
        return Icon(
          LucideIcons.fileArchive,
          size: size,
          color: const Color(0xFFF97316), // orange-500
        );
      case 'script':
        return Icon(
          LucideIcons.fileCode2,
          size: size,
          color: const Color(0xFF8B5CF6), // violet-500
        );
      case 'image':
        return Icon(
          LucideIcons.fileImage,
          size: size,
          color: const Color(0xFFEC4899), // pink-500
        );
      default:
        return Icon(
          LucideIcons.fileText,
          size: size,
          color: const Color(0xFF9CA3AF), // gray-400
        );
    }
  }

  /// 根据文件名获取文件类型
  static String getTypeFromName(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'exe':
      case 'bat':
      case 'cmd':
        return 'exe';
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'config':
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
        return 'config';
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return 'archive';
      case 'sh':
      case 'ps1':
      case 'py':
      case 'js':
      case 'ts':
        return 'script';
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'bmp':
      case 'webp':
      case 'ico':
        return 'image';
      default:
        return 'unknown';
    }
  }

  /// 判断是否为文本文件
  static bool isTextFile(String fileName) {
    final textExtensions = [
      'txt', 'md', 'ini', 'cfg', 'conf', 'config', 'json', 'xml', 'yaml', 'yml',
      'log', 'bat', 'cmd', 'sh', 'ps1', 'py', 'js', 'ts', 'html', 'css', 'reg',
    ];
    final ext = fileName.split('.').last.toLowerCase();
    return textExtensions.contains(ext);
  }
}

