import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/network/slow_request_file_logger.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';

/// 慢请求日志查看页面
class SlowRequestLogsPage extends StatefulWidget {
  const SlowRequestLogsPage({super.key});

  @override
  State<SlowRequestLogsPage> createState() => _SlowRequestLogsPageState();
}

class _SlowRequestLogsPageState extends State<SlowRequestLogsPage> {
  List<_LogFileInfo> _files = [];
  _LogFileInfo? _selectedFile;
  String _content = '';
  bool _loadingFiles = true;
  bool _loadingContent = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loadingFiles = true);
    try {
      await SlowRequestFileLogger.instance.init();
      final dirPath = SlowRequestFileLogger.instance.logDirPath;
      if (dirPath == null) {
        setState(() {
          _files = [];
          _loadingFiles = false;
        });
        return;
      }
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        setState(() {
          _files = [];
          _loadingFiles = false;
        });
        return;
      }
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('slow_http_'))
          .map((f) {
        final stat = f.statSync();
        return _LogFileInfo(
          file: f,
          name: f.path.split(Platform.pathSeparator).last,
          size: stat.size,
          modified: stat.modified,
        );
      }).toList();
      // 最新在前
      files.sort((a, b) => b.modified.compareTo(a.modified));
      // 刷新后重新选中：优先选之前选中的同名文件，否则选第一个
      _LogFileInfo? toSelect;
      if (_selectedFile != null) {
        toSelect = files.cast<_LogFileInfo?>().firstWhere(
          (f) => f!.name == _selectedFile!.name,
          orElse: () => files.isNotEmpty ? files.first : null,
        );
      } else if (files.isNotEmpty) {
        toSelect = files.first;
      }
      setState(() {
        _files = files;
        _selectedFile = null;
        _loadingFiles = false;
      });
      if (toSelect != null) {
        _selectFile(toSelect);
      }
    } catch (e) {
      setState(() {
        _files = [];
        _loadingFiles = false;
      });
    }
  }

  Future<void> _selectFile(_LogFileInfo info) async {
    setState(() {
      _selectedFile = info;
      _loadingContent = true;
    });
    try {
      final content = await info.file.readAsString();
      if (mounted) {
        setState(() {
          _content = content;
          _loadingContent = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _content = '读取失败: $e';
          _loadingContent = false;
        });
      }
    }
  }

  Future<void> _exportFile() async {
    if (_selectedFile == null) return;
    try {
      final bytes = await _selectedFile!.file.readAsBytes();
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '导出慢请求日志',
        fileName: _selectedFile!.name,
        type: FileType.custom,
        allowedExtensions: const ['log'],
        bytes: Uint8List.fromList(bytes),
      );
      if (saved != null && mounted) {
        showTopNotice(context, '已导出: ${_selectedFile!.name}',
            level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '导出失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('将删除所有慢请求日志文件，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除全部'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final dirPath = SlowRequestFileLogger.instance.logDirPath;
    if (dirPath == null) return;
    try {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          f.deleteSync();
        }
      }
      setState(() {
        _files = [];
        _selectedFile = null;
        _content = '';
      });
      if (mounted) {
        showTopNotice(context, '已清除全部日志', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '清除失败: $e', level: NoticeLevel.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final pagePadding =
        isPhone ? const EdgeInsets.all(12) : const EdgeInsets.all(24);

    return Padding(
      padding: pagePadding,
      child: Column(
        children: [
          _buildToolbar(isPhone),
          SizedBox(height: isPhone ? 12 : 16),
          Expanded(
            child: _loadingFiles
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? _buildEmpty()
                    : isPhone
                        ? _buildPhoneLayout()
                        : _buildDesktopLayout(),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(bool isPhone) {
    return Container(
      padding: EdgeInsets.all(isPhone ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 20, color: Colors.orange.shade600),
          const SizedBox(width: 8),
          Text(
            '慢请求日志',
            style: TextStyle(
              fontSize: isPhone ? 15 : 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(>1秒)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const Spacer(),
          if (_selectedFile != null)
            _buildActionButton(
              icon: LucideIcons.download,
              label: isPhone ? null : '导出',
              onTap: _exportFile,
              color: AppColors.iosBlue,
            ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: LucideIcons.refreshCw,
            label: isPhone ? null : '刷新',
            onTap: _loadFiles,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            icon: LucideIcons.trash2,
            label: isPhone ? null : '清除全部',
            onTap: _files.isEmpty ? null : _clearAll,
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    String? label,
    VoidCallback? onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: onTap != null ? color.withOpacity(0.08) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: onTap != null ? color : Colors.grey.shade400),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: onTap != null ? color : Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.checkCircle, size: 48, color: Colors.green.shade300),
          const SizedBox(height: 12),
          Text(
            '暂无慢请求日志',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
          Text(
            '所有请求响应时间均在 1 秒内',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  /// 桌面端：左侧文件列表 + 右侧内容
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: _buildFileList(),
        ),
        const SizedBox(width: 16),
        Expanded(child: _buildContentView()),
      ],
    );
  }

  /// 手机端：文件列表或内容（单列切换）
  Widget _buildPhoneLayout() {
    if (_selectedFile == null) {
      return _buildFileList();
    }
    return Column(
      children: [
        // 返回按钮
        InkWell(
          onTap: () => setState(() => _selectedFile = null),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.arrowLeft,
                    size: 16, color: AppColors.iosBlue),
                const SizedBox(width: 4),
                Text('返回文件列表',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.iosBlue)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildContentView()),
      ],
    );
  }

  Widget _buildFileList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '日志文件 (${_files.length})',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final f = _files[index];
                final isSelected = _selectedFile?.file.path == f.file.path;
                // 从文件名提取日期：slow_http_2026-04-11.log → 2026-04-11
                final dateStr = f.name
                    .replaceFirst('slow_http_', '')
                    .replaceFirst('.log', '');
                return InkWell(
                  onTap: () => _selectFile(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.iosBlue.withOpacity(0.08)
                          : null,
                      border: Border(
                        left: BorderSide(
                          color:
                              isSelected ? AppColors.iosBlue : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.fileText,
                          size: 16,
                          color: isSelected
                              ? AppColors.iosBlue
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? AppColors.iosBlue
                                      : Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatSize(f.size),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentView() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.fileCode, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedFile?.name ?? '选择一个日志文件',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                if (_selectedFile != null)
                  Text(
                    '${_formatSize(_selectedFile!.size)} · ${DateFormat('HH:mm:ss').format(_selectedFile!.modified)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 内容
          Expanded(
            child: _loadingContent
                ? const Center(child: CircularProgressIndicator())
                : _content.isEmpty
                    ? Center(
                        child: Text('日志为空',
                            style: TextStyle(color: Colors.grey.shade400)))
                    : Scrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _content,
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _LogFileInfo {
  final File file;
  final String name;
  final int size;
  final DateTime modified;

  _LogFileInfo({
    required this.file,
    required this.name,
    required this.size,
    required this.modified,
  });
}
