import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/update_downloader.dart';
import '../domain/models/release_info.dart';
import '../providers.dart';

/// 下载/安装阶段。
enum _Phase {
  /// 正在从网络下载（含 preparing 检查阶段，UI 视觉一致）
  downloading,

  /// 下载完成，正在校验 size + MD5
  verifying,

  /// 校验通过，准备安装。展示文件路径 + 自动延迟 1.5s 后触发 install
  ready,

  /// 出错（下载/校验/安装任一阶段失败）
  error,
}

/// 下载进度对话框。
/// 调用方：showDialog(barrierDismissible: false, builder: (_) => UpdateProgressDialog(...))
/// 结果：true = 已开始安装；false = 用户取消；null = 下载失败
class UpdateProgressDialog extends ConsumerStatefulWidget {
  final ReleaseInfo release;
  final String host;
  final bool isForced;

  const UpdateProgressDialog({
    super.key,
    required this.release,
    required this.host,
    required this.isForced,
  });

  @override
  ConsumerState<UpdateProgressDialog> createState() =>
      _UpdateProgressDialogState();
}

class _UpdateProgressDialogState
    extends ConsumerState<UpdateProgressDialog> {
  final CancelToken _cancelToken = CancelToken();
  int _received = 0;
  int _total = 0;
  String? _error;
  _Phase _phase = _Phase.downloading;
  File? _readyFile;
  bool _installTriggered = false;

  @override
  void initState() {
    super.initState();
    _total = widget.release.size;
    _start();
  }

  Future<void> _start() async {
    final service = ref.read(updateServiceProvider);
    try {
      final file = await service.downloadOnly(
        widget.release,
        widget.host,
        onProgress: (rcv, total) {
          if (!mounted) return;
          setState(() {
            _received = rcv;
            _total = total > 0 ? total : widget.release.size;
          });
        },
        onPhase: (phase) {
          if (!mounted) return;
          setState(() {
            switch (phase) {
              case DownloadPhase.preparing:
              case DownloadPhase.downloading:
                _phase = _Phase.downloading;
                break;
              case DownloadPhase.verifying:
                _phase = _Phase.verifying;
                break;
            }
          });
        },
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _readyFile = file;
      });
      // 给用户 1.5 秒看到路径再自动触发安装。Windows 上 install 内会 exit(0)，
      // 这里的 widget 会随主进程一起销毁。Android 拉起安装页后用户可取消。
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      // 这 1.5s 内用户可能已经手点了"立即安装"，避免重复触发
      if (_installTriggered) return;
      _triggerInstall();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  Future<void> _triggerInstall() async {
    final file = _readyFile;
    if (file == null) return;
    // 标记 install 已发起，让自动延迟段不再重复触发；用户手点不受此标记限制，
    // 这样系统安装页被取消后用户能重新点"立即安装"再装一次。
    _installTriggered = true;
    try {
      await ref.read(updateServiceProvider).install(file);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  Future<void> _openContainingFolder() async {
    final file = _readyFile;
    if (file == null || !Platform.isWindows) return;
    try {
      // explorer.exe /select,"<path>" 会打开文件夹并高亮该文件
      await Process.start(
        'explorer.exe',
        ['/select,', file.path],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  Future<void> _copyPath() async {
    final file = _readyFile;
    if (file == null) return;
    await Clipboard.setData(ClipboardData(text: file.path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制安装包路径')),
      );
    }
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('dialog disposed');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = !widget.isForced && _phase != _Phase.ready;
    return PopScope(
      canPop: canPop,
      child: AlertDialog(
        title: Text(_titleForPhase()),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'v${widget.release.version} (build ${widget.release.buildNumber})',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _buildBody(),
            ],
          ),
        ),
        actions: _buildActions(),
      ),
    );
  }

  String _titleForPhase() {
    switch (_phase) {
      case _Phase.downloading:
        return '正在下载更新';
      case _Phase.verifying:
        return '正在校验文件';
      case _Phase.ready:
        return '准备安装';
      case _Phase.error:
        return '更新失败';
    }
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.downloading:
        final progress = _total > 0 ? _received / _total : 0.0;
        final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
        final recvMb = (_received / 1024 / 1024).toStringAsFixed(2);
        final totalMb = (_total / 1024 / 1024).toStringAsFixed(2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: _total > 0 ? progress : null),
            const SizedBox(height: 8),
            Text('$percent%  ($recvMb / $totalMb MB)'),
          ],
        );

      case _Phase.verifying:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            LinearProgressIndicator(),
            SizedBox(height: 8),
            Text('正在校验文件…'),
          ],
        );

      case _Phase.ready:
        return _buildReadyBody();

      case _Phase.error:
        return _buildErrorBody();
    }
  }

  Widget _buildReadyBody() {
    final file = _readyFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 6),
            Expanded(child: Text('文件已下载完成，即将自动安装')),
          ],
        ),
        if (file != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    file.path,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF374151),
                      fontFamily: 'monospace',
                    ),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '复制路径',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: _copyPath,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '若未自动开始安装，请手动双击该文件完成安装。',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBody() {
    final file = _readyFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _error ?? '未知错误',
          style: const TextStyle(color: Colors.red, height: 1.5),
        ),
        if (file != null) ...[
          const SizedBox(height: 12),
          const Text('安装包已下载到本地，您可以手动安装：',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    file.path,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF374151),
                      fontFamily: 'monospace',
                    ),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: '复制路径',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: _copyPath,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions() {
    switch (_phase) {
      case _Phase.downloading:
      case _Phase.verifying:
        if (widget.isForced) return const [];
        return [
          TextButton(
            onPressed: () {
              if (!_cancelToken.isCancelled) {
                _cancelToken.cancel('user cancel');
              }
              Navigator.of(context).pop(false);
            },
            child: const Text('取消'),
          ),
        ];

      case _Phase.ready:
        return [
          if (Platform.isWindows && _readyFile != null)
            TextButton.icon(
              onPressed: _openContainingFolder,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('打开所在文件夹'),
            ),
          FilledButton.icon(
            onPressed: _triggerInstall,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('立即安装'),
          ),
        ];

      case _Phase.error:
        return [
          TextButton(
            onPressed: () {
              setState(() {
                _phase = _Phase.downloading;
                _error = null;
                _received = 0;
                _readyFile = null;
                _installTriggered = false;
              });
              _start();
            },
            child: const Text('重试'),
          ),
          if (!widget.isForced)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('关闭'),
            ),
        ];
    }
  }
}
