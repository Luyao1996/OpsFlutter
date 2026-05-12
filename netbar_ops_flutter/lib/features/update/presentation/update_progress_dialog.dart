import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/release_info.dart';
import '../providers.dart';

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
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _total = widget.release.size;
    _start();
  }

  Future<void> _start() async {
    final service = ref.read(updateServiceProvider);
    try {
      await service.downloadAndInstall(
        widget.release,
        widget.host,
        onProgress: (rcv, total) {
          if (!mounted) return;
          setState(() {
            _received = rcv;
            _total = total > 0 ? total : widget.release.size;
          });
        },
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() => _done = true);
      // 安装已发起。Windows 上 service.downloadAndInstall 内部会 exit(0)，
      // 这里到不了；Android 拉起安装页后用户可能取消，弹窗保留让用户重试。
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
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
    final progress = _total > 0 ? _received / _total : 0.0;
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(1);
    final recvMb = (_received / 1024 / 1024).toStringAsFixed(2);
    final totalMb = (_total / 1024 / 1024).toStringAsFixed(2);

    return PopScope(
      canPop: !widget.isForced && _error == null && !_done,
      child: AlertDialog(
        title: Text(_error != null
            ? '更新失败'
            : (_done ? '准备安装' : '正在下载更新')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'v${widget.release.version} (build ${widget.release.buildNumber})',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!,
                    style: const TextStyle(color: Colors.red, height: 1.5)),
              ] else if (_done) ...[
                const Text('下载完成，已发起安装。'),
              ] else ...[
                LinearProgressIndicator(value: _total > 0 ? progress : null),
                const SizedBox(height: 8),
                Text('$percent%  ($recvMb / $totalMb MB)'),
              ],
            ],
          ),
        ),
        actions: [
          if (_error != null) ...[
            TextButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _received = 0;
                });
                _start();
              },
              child: const Text('重试'),
            ),
            if (!widget.isForced)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
          ] else if (!_done && !widget.isForced) ...[
            TextButton(
              onPressed: () {
                if (!_cancelToken.isCancelled) {
                  _cancelToken.cancel('user cancel');
                }
                Navigator.of(context).pop(false);
              },
              child: const Text('取消'),
            ),
          ],
        ],
      ),
    );
  }
}
