// ============================================================================
// TODO: 验证完崩溃日志机制后整个 lib/features/debug/ 目录可以删除
// ============================================================================
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 把传入的日志文件打包成 zip，存放在 temp 目录，并通过系统分享面板分享。
///
/// - [files] 待打包的日志文件列表
/// - [onMessage] 用于显示提示信息（成功 / 失败 / 取消等）
///
/// zip 文件名：`crash_logs_yyyyMMdd_HHmmss.zip`
/// zip 内目录结构：保留最后两段（webrtc_logs/xxx.log / crash_logs/xxx.log）
Future<void> shareLogsAsZip({
  required BuildContext context,
  required List<File> files,
  void Function(String message, {bool isError})? onMessage,
}) async {
  void notify(String msg, {bool isError = false}) {
    if (onMessage != null) {
      onMessage(msg, isError: isError);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF10B981),
        ),
      );
    }
  }

  if (files.isEmpty) {
    notify('没有可导出的日志');
    return;
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final ts = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final zipPath =
        '${tempDir.path}${Platform.pathSeparator}crash_logs_$ts.zip';

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    for (final f in files) {
      final parts = f.path.split(Platform.pathSeparator);
      final relPath = parts.length >= 2
          ? '${parts[parts.length - 2]}/${parts[parts.length - 1]}'
          : parts.last;
      encoder.addFile(f, relPath);
    }
    await encoder.close();

    final zipFile = File(zipPath);
    final sizeKb = (zipFile.lengthSync() / 1024).toStringAsFixed(1);

    if (!context.mounted) return;
    final result = await Share.shareXFiles(
      [XFile(zipPath, mimeType: 'application/zip')],
      subject: '崩溃日志包-$ts',
      text:
          '设备: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n文件数: ${files.length}\n大小: $sizeKb KB',
    );
    if (!context.mounted) return;
    if (result.status == ShareResultStatus.dismissed ||
        result.status == ShareResultStatus.unavailable) {
      notify('分享面板已关闭。如未看到微信，请改用"复制全部"按钮', isError: true);
    }
  } catch (e) {
    notify('打包失败: $e', isError: true);
  }
}

/// 收集崩溃日志文件（webrtc_logs/ + crash_logs/）
///
/// 移动端从 ApplicationDocumentsDirectory 取，桌面端从 exe 同级取。
Future<List<File>> collectCrashLogFiles() async {
  final files = <File>[];
  try {
    Directory base;
    if (Platform.isAndroid || Platform.isIOS) {
      base = await getApplicationDocumentsDirectory();
    } else {
      base = File(Platform.resolvedExecutable).parent;
    }
    for (final sub in ['webrtc_logs', 'crash_logs']) {
      final dir = Directory('${base.path}${Platform.pathSeparator}$sub');
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is File) files.add(entity);
        }
      }
    }
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  } catch (_) {}
  return files;
}
