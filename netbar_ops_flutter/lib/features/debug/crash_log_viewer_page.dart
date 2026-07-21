// ============================================================================
// TODO: 验证完崩溃日志机制后整个 lib/features/debug/ 目录可以删除
//       同时移除 user_profile_dialog.dart 里的 _buildCrashLogViewerButton 入口
// ============================================================================
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/exit_reason_reporter.dart';
import 'crash_log_export_helper.dart';

// iOS 端屏蔽微信字样（过审整改）: iOS 用中性文案，其他平台保留原文案
bool get _isIOSPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 查看崩溃日志页面
///
/// 当系统分享面板没有微信，或者分享文件失败时的兜底方案。
/// 100% 可用：用户能直接看到日志内容，点"复制全部"后到微信粘贴发给开发者。
class CrashLogViewerPage extends StatefulWidget {
  const CrashLogViewerPage({super.key});

  @override
  State<CrashLogViewerPage> createState() => _CrashLogViewerPageState();
}

class _CrashLogViewerPageState extends State<CrashLogViewerPage> {
  List<File> _files = [];
  File? _selectedFile;
  String _content = '';
  String? _baseDirPath;
  bool _loading = true;
  String? _error;
  String? _exitHint;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      Directory base;
      if (kIsWeb) {
        setState(() {
          _loading = false;
          _error = 'Web 版不支持查看日志';
        });
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        base = await getApplicationDocumentsDirectory();
      } else {
        base = File(Platform.resolvedExecutable).parent;
      }
      _baseDirPath = base.path;

      final files = <File>[];
      for (final sub in ['webrtc_logs', 'crash_logs']) {
        final dir = Directory('${base.path}${Platform.pathSeparator}$sub');
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            if (entity is File) files.add(entity);
          }
        }
      }
      files.sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final hint = await getLastAbnormalExitHint();

      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
        _exitHint = hint;
      });

      if (files.isNotEmpty) {
        await _selectFile(files.first);
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载日志失败: $e';
      });
    }
  }

  Future<void> _selectFile(File f) async {
    try {
      final raw = await f.readAsString();
      // 只显示最近 N KB，避免巨大文件卡 UI
      const maxBytes = 256 * 1024;
      String shown;
      if (raw.length > maxBytes) {
        shown = '...[省略 ${raw.length - maxBytes} 字节，仅显示末尾 ${maxBytes ~/ 1024}KB]...\n\n'
            '${raw.substring(raw.length - maxBytes)}';
      } else {
        shown = raw;
      }
      setState(() {
        _selectedFile = f;
        _content = shown;
      });
    } catch (e) {
      setState(() {
        _selectedFile = f;
        _content = '读取失败: $e';
      });
    }
  }

  Future<void> _copyAll() async {
    if (_content.isEmpty) return;
    final filename = _selectedFile == null
        ? ''
        : _selectedFile!.path.split(Platform.pathSeparator).last;
    final header = '=== 日志文件: $filename ===\n'
        '=== 设备: ${Platform.operatingSystem} ${Platform.operatingSystemVersion} ===\n'
        '=== 复制时间: ${DateTime.now().toIso8601String()} ===\n\n';
    await Clipboard.setData(ClipboardData(text: header + _content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isIOSPlatform
            ? '已复制全部日志到剪贴板，粘贴发送给开发者即可'
            : '已复制全部日志到剪贴板，去微信粘贴发送即可'),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF2563EB),
      ),
    );
  }

  Future<void> _handleExportZip() async {
    await shareLogsAsZip(context: context, files: _files);
  }

  Future<void> _handleClearLogs() async {
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可清理的日志')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理所有崩溃日志？'),
        content: Text('将删除 ${_files.length} 个日志文件，操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    int deleted = 0;
    int failed = 0;
    for (final f in List<File>.from(_files)) {
      try {
        f.deleteSync();
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failed == 0
            ? '已清理 $deleted 个日志文件'
            : '已清理 $deleted 个，失败 $failed 个'),
        backgroundColor: failed == 0 ? const Color(0xFF10B981) : const Color(0xFFEA580C),
      ),
    );
    // 刷新
    setState(() {
      _loading = true;
      _files = [];
      _selectedFile = null;
      _content = '';
    });
    await _loadFiles();
  }

  Future<void> _copyPath() async {
    if (_baseDirPath == null) return;
    await Clipboard.setData(ClipboardData(text: _baseDirPath!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制路径: $_baseDirPath')),
    );
  }

  String _formatFileLabel(File f) {
    final name = f.path.split(Platform.pathSeparator).last;
    final stat = f.statSync();
    final sizeKb = (stat.size / 1024).toStringAsFixed(1);
    final m = stat.modified;
    final mStr =
        '${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')} '
        '${m.hour.toString().padLeft(2, '0')}:${m.minute.toString().padLeft(2, '0')}';
    return '$name  ($sizeKb KB, $mStr)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('崩溃日志查看'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: '重新加载',
            onPressed: () {
              setState(() {
                _loading = true;
                _files = [];
                _selectedFile = null;
                _content = '';
                _error = null;
              });
              _loadFiles();
            },
          ),
          IconButton(
            icon: const Icon(LucideIcons.copy),
            tooltip: '复制全部',
            onPressed: _content.isEmpty ? null : _copyAll,
          ),
          IconButton(
            icon: const Icon(LucideIcons.package, color: Color(0xFF2563EB)),
            tooltip: '打包全部日志并分享',
            onPressed: _loading || _files.isEmpty ? null : _handleExportZip,
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Color(0xFFDC2626)),
            tooltip: '清理所有日志',
            onPressed: _loading ? null : _handleClearLogs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildExitBanner(),
                Expanded(
                  child: _error != null
                      ? Center(child: Text(_error!))
                      : _files.isEmpty
                          ? _buildEmpty()
                          : _buildBody(),
                ),
              ],
            ),
    );
  }

  /// 置顶提示：上次异常退出原因 + 引导用户通过微信把日志分享给开发者。
  Widget _buildExitBanner() {
    final hasExit = _exitHint != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: hasExit ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasExit) ...[
            Row(
              children: [
                const Icon(LucideIcons.alertTriangle,
                    size: 16, color: Color(0xFFDC2626)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _exitHint!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Row(
            children: [
              const Icon(LucideIcons.messageCircle,
                  size: 16, color: Color(0xFF2563EB)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _isIOSPlatform
                      ? '请点右上角"打包"按钮导出日志，再分享给开发者，便于快速定位问题。'
                      : '请点右上角"打包"按钮导出日志，再通过微信分享给开发者，便于快速定位问题。',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.fileText, size: 48, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 12),
          const Text('暂无日志', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          if (_baseDirPath != null)
            Text(
              '目录: $_baseDirPath',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(LucideIcons.copy, size: 16),
            label: const Text('复制路径'),
            onPressed: _copyPath,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // 文件选择栏
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          color: const Color(0xFFF3F4F6),
          child: Row(
            children: [
              const Icon(LucideIcons.file, size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<File>(
                    isExpanded: true,
                    value: _selectedFile,
                    items: _files
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(
                                _formatFileLabel(f),
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (f) {
                      if (f != null) _selectFile(f);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // 内容区
        Expanded(
          child: Container(
            color: const Color(0xFF111827),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _content.isEmpty ? '(空)' : _content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFFE5E7EB),
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        // 底部操作栏
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('复制全部到剪贴板'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _content.isEmpty ? null : _copyAll,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
