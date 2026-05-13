import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
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

  /// 完成后是否显示"打开文件"按钮。
  /// - APK 在手机/PC 都有意义（手机调起安装器、PC 双击执行）
  /// - 被控端 .exe 在手机端无意义（Android 打不开），调用方传 false
  final bool showOpenFile;

  const FileDownloadDialog({
    super.key,
    required this.downloader,
    required this.title,
    this.showOpenFile = true,
  });

  static Future<void> show(
    BuildContext context,
    FileDownloader downloader, {
    required String title,
    bool showOpenFile = true,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FileDownloadDialog(
        downloader: downloader,
        title: title,
        showOpenFile: showOpenFile,
      ),
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

  /// 手机端：通过系统分享面板分享文件（用户可选择微信、QQ 等）。
  Future<void> _shareFile() async {
    if (_completedFile == null) return;
    try {
      await Share.shareXFiles(
        [XFile(_completedFile!.path)],
        subject: widget.downloader.targetFileName,
      );
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
            // 手机端：分享（弹系统分享面板，可选微信/QQ 等）；桌面端：打开文件夹
            if (Platform.isAndroid || Platform.isIOS)
              TextButton(onPressed: _shareFile, child: const Text('分享'))
            else
              TextButton(onPressed: _openFolder, child: const Text('打开文件夹')),
            // "打开文件" 按钮：
            // - 桌面端：始终显示（exe/apk 都能本机直接打开）
            // - 手机端：按 showOpenFile 控制（APK=true，被控端.exe=false）
            if (!(Platform.isAndroid || Platform.isIOS) || widget.showOpenFile)
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
