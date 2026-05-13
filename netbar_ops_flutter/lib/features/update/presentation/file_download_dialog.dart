import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/file_downloader.dart';

/// 通用文件下载进度对话框。
/// 接收任意 [FileDownloader] 实现，串联：下载、显示进度、完成后打开文件夹/文件、失败重试。
///
/// 用法：
/// ```dart
/// FileDownloadDialog.show(context, ApkDownloader(), title: '下载 APP');
/// FileDownloadDialog.show(context, ControllerDownloader(), title: '下载被控端');
/// ```
class FileDownloadDialog extends StatefulWidget {
  final FileDownloader downloader;
  final String title;

  const FileDownloadDialog({
    super.key,
    required this.downloader,
    required this.title,
  });

  static Future<void> show(
    BuildContext context,
    FileDownloader downloader, {
    required String title,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FileDownloadDialog(downloader: downloader, title: title),
    );
  }

  @override
  State<FileDownloadDialog> createState() => _FileDownloadDialogState();
}

class _FileDownloadDialogState extends State<FileDownloadDialog> {
  CancelToken _cancelToken = CancelToken();

  int _received = 0;
  int _total = 0;
  String? _error;
  File? _completedFile;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _received = 0;
      _total = 0;
      _completedFile = null;
    });
    try {
      final file = await widget.downloader.download(
        onProgress: (r, t) {
          if (!mounted) return;
          setState(() {
            _received = r;
            _total = t;
          });
        },
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() => _completedFile = file);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _retry() async {
    if (_cancelToken.isCancelled) {
      _cancelToken = CancelToken();
    }
    await _start();
  }

  Future<void> _openFolder() async {
    if (_completedFile == null) return;
    try {
      await launchUrl(
        Uri.file(_completedFile!.parent.path),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  Future<void> _openFile() async {
    if (_completedFile == null) return;
    try {
      await OpenFilex.open(_completedFile!.path);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('disposed');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _received / _total : 0.0;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    final mbRecv = (_received / 1024 / 1024).toStringAsFixed(2);
    final mbTotal = (_total / 1024 / 1024).toStringAsFixed(2);

    final titleText = _error != null
        ? '${widget.title}失败'
        : (_completedFile != null ? '${widget.title}完成' : widget.title);

    return PopScope(
      canPop: _error != null || _completedFile != null,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              _error != null
                  ? Icons.error_outline
                  : (_completedFile != null
                      ? Icons.check_circle_outline
                      : Icons.download_rounded),
              color: _error != null
                  ? Colors.red
                  : (_completedFile != null ? Colors.green : Colors.blue),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(titleText)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, height: 1.5),
                ),
              ] else if (_completedFile != null) ...[
                const Text('已保存到：', style: TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                SelectableText(
                  _completedFile!.path,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ] else ...[
                Text(
                  widget.downloader.targetFileName,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: _total > 0 ? progress : null),
                const SizedBox(height: 8),
                Text(
                  _total > 0
                      ? '$percent%   ($mbRecv / $mbTotal MB)'
                      : '正在准备下载...',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_error != null) ...[
            TextButton(onPressed: _retry, child: const Text('重试')),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ] else if (_completedFile != null) ...[
            TextButton(onPressed: _openFolder, child: const Text('打开文件夹')),
            TextButton(onPressed: _openFile, child: const Text('打开文件')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('完成'),
            ),
          ] else ...[
            TextButton(
              onPressed: () {
                if (!_cancelToken.isCancelled) {
                  _cancelToken.cancel('user cancel');
                }
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
          ],
        ],
      ),
    );
  }
}
