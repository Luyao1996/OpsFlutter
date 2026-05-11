import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/providers/upload_queue_provider.dart';
import '../../../../shared/utils/top_notice.dart';
import '../web_file_picker.dart';
import 'upload_helper.dart';

/// 上传弹窗
class UploadModal extends ConsumerStatefulWidget {
  final String zone;
  final int? parentId;
  final int? netbarId;
  final VoidCallback onSuccess;

  const UploadModal({
    super.key,
    required this.zone,
    this.parentId,
    this.netbarId,
    required this.onSuccess,
  });

  @override
  ConsumerState<UploadModal> createState() => _UploadModalState();
}

class _UploadModalState extends ConsumerState<UploadModal> {
  bool _isDragging = false;
  String? _error;
  final List<_UploadItem> _items = [];

  void _handleDragEnter() => setState(() => _isDragging = true);
  void _handleDragLeave() => setState(() => _isDragging = false);

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.name.isNotEmpty) {
              _items.add(
                _UploadItem(
                  name: file.name,
                  type: _getFileType(file.name),
                  isDirectory: false,
                  bytes: file.bytes,
                  relativePath: file.name,
                ),
              );
            }
          }
        });
      }
    } catch (e) {
      setState(() => _error = '选择文件失败: $e');
    }
  }

  Future<void> _pickDirectory() async {
    // Mobile/phone: directory picking UX is inconsistent; keep file picking only.
    if (context.isPhone) {
      if (!mounted) return;
      showTopNotice(context, '移动端暂不支持选择文件夹上传，请选择文件', level: NoticeLevel.warning);
      return;
    }
    // Web 平台使用 WebFilePicker
    if (kIsWeb) {
      await _pickDirectoryWeb();
      return;
    }
    // 非 Web 平台使用原有逻辑
    await _pickDirectoryNative();
  }

  Future<void> _pickDirectoryWeb() async {
    try {
      final files = await webFilePicker.pickDirectory();
      if (files.isEmpty) return;

      setState(() {
        for (final file in files) {
          _items.add(
            _UploadItem(
              name: file.name,
              type: file.isDirectory ? 'folder' : _getFileType(file.name),
              isDirectory: file.isDirectory,
              bytes: file.isDirectory ? null : file.bytes,
              relativePath: file.relativePath,
            ),
          );
        }
      });
    } catch (e) {
      setState(() => _error = '选择目录失败: $e');
    }
  }

  Future<void> _pickDirectoryNative() async {
    try {
      final files = await platformFileHelper.pickDirectory();
      if (files.isEmpty) return;

      setState(() {
        for (final file in files) {
          _items.add(
            _UploadItem(
              name: file.name,
              type: file.type,
              isDirectory: file.isDirectory,
              bytes: file.bytes,
              relativePath: file.relativePath,
            ),
          );
        }
      });
    } catch (e) {
      setState(() => _error = '选择目录失败: $e');
    }
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
      case 'zip':
      case 'rar':
      case '7z':
        return 'archive';
      default:
        return 'file';
    }
  }

  Future<void> _handleUpload() async {
    if (_items.isEmpty) return;
    try {
      // 检查是否需要解压ZIP
      final fileItems = _items.where((item) => !item.isDirectory).toList();
      final zipItems = fileItems.where((item) => item.isZipFile).toList();

      bool extractZip = false;
      // 如果只有一个文件且是ZIP，或者全是ZIP文件，弹窗询问
      if (zipItems.isNotEmpty &&
          (fileItems.length == 1 || zipItems.length == fileItems.length)) {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ZIP文件处理'),
            content: Text(
              zipItems.length == 1
                  ? '检测到ZIP文件 "${zipItems.first.name}"，是否在服务器端自动解压？'
                  : '检测到 ${zipItems.length} 个ZIP文件，是否在服务器端自动解压？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('直接上传'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('解压上传'),
              ),
            ],
          ),
        );
        extractZip = result ?? false;
      }

      final notifier = ref.read(uploadQueueProvider.notifier);
      final tasks = <UploadTask>[];
      var counter = 0;

      for (final item in _items) {
        final id =
            'upload-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
        if (item.isDirectory) {
          tasks.add(
            UploadTask(
              id: id,
              name: item.name,
              size: 0,
              isDirectory: true,
              relativePath: item.relativePath,
              parentId: widget.parentId,
              zone: widget.zone,
              netbarId: widget.netbarId,
              bytes: null,
              progress: 100,
              status: UploadStatus.success,
            ),
          );
        } else {
          if (item.bytes == null) {
            throw Exception('文件 ${item.name} 读取失败');
          }
          tasks.add(
            UploadTask(
              id: id,
              name: item.name,
              size: item.bytes!.length,
              isDirectory: false,
              relativePath: item.relativePath,
              parentId: widget.parentId,
              zone: widget.zone,
              netbarId: widget.netbarId,
              bytes: item.bytes,
              extractZip: extractZip && item.isZipFile,
            ),
          );
        }
      }

      notifier.enqueue(tasks);
      widget.onSuccess();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '上传失败: $e');
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    final isSheet = context.isNarrow;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(isPhone: isPhone, isSheet: isSheet),
        Flexible(child: _buildContent(isPhone: isPhone)),
        _buildFooter(isSheet: isSheet),
      ],
    );

    if (isSheet) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: body),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.xl,
        ),
        child: body,
      ),
    );
  }

  Widget _buildHeader({required bool isPhone, required bool isSheet}) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, isSheet ? 12 : 20, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.iosBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.upload,
              size: 20,
              color: AppColors.iosBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '上传文件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  isPhone ? '点击选择文件' : '拖拽文件或点击选择',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, size: 20, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildContent({required bool isPhone}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          if (!isPhone)
            // Desktop/Web: drag area
            MouseRegion(
              onEnter: (_) => _handleDragEnter(),
              onExit: (_) => _handleDragLeave(),
              child: GestureDetector(
                onTap: _pickFiles,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 150,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? AppColors.iosBlue.withValues(alpha: 0.05)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isDragging
                          ? AppColors.iosBlue
                          : Colors.grey.shade300,
                      width: _isDragging ? 2 : 1,
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.uploadCloud,
                          size: 40,
                          color: _isDragging
                              ? AppColors.iosBlue
                              : Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isDragging ? '释放以上传' : '拖拽文件到此处',
                          style: TextStyle(
                            fontSize: 14,
                            color: _isDragging
                                ? AppColors.iosBlue
                                : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '或点击选择文件',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(LucideIcons.file, size: 16),
                  label: const Text('选择文件'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.iosBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!isPhone)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(LucideIcons.file, size: 16),
                    label: const Text('选择文件'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickDirectory,
                    icon: const Icon(LucideIcons.folderPlus, size: 16),
                    label: const Text('选择文件夹'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '提示：移动端仅支持选择文件上传',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Expanded(child: _buildFileList()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(fontSize: 12, color: Colors.red.shade600),
            ),
          ],
        ],
      ),
    );
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '--';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'exe':
        return LucideIcons.play;
      case 'config':
        return LucideIcons.fileText;
      case 'archive':
        return LucideIcons.archive;
      default:
        return LucideIcons.file;
    }
  }

  Widget _buildFileList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 列表头
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                '待上传文件 (${_items.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _items.clear()),
                icon: Icon(
                  LucideIcons.trash2,
                  size: 14,
                  color: Colors.red.shade400,
                ),
                label: Text(
                  '清空',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade400),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        // 文件列表
        Expanded(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _items.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, index) {
              final item = _items[index];
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    // 文件图标
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.iosBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        item.isDirectory
                            ? LucideIcons.folder
                            : _getFileIcon(item.type),
                        size: 18,
                        color: AppColors.iosBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 文件信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatFileSize(item.bytes?.length),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 状态/操作
                    // 保持布局占位，防止跳动
                    if (false)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(AppColors.iosBlue),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: () => _removeItem(index),
                        icon: Icon(
                          LucideIcons.x,
                          size: 16,
                          color: Colors.grey.shade400,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        splashRadius: 16,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFooter({required bool isSheet}) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, isSheet ? 20 : 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        borderRadius: isSheet
            ? BorderRadius.zero
            : const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade600)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _items.isEmpty ? null : _handleUpload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('上传'),
          ),
        ],
      ),
    );
  }
}

class _UploadItem {
  final String name;
  final String type;
  final bool isDirectory;
  final String? content;
  final List<int>? bytes;
  final String relativePath;
  bool extractZip;

  _UploadItem({
    required this.name,
    required this.type,
    required this.isDirectory,
    this.content,
    this.bytes,
    required this.relativePath,
    this.extractZip = false,
  });

  /// 检查是否为ZIP文件
  bool get isZipFile => name.toLowerCase().endsWith('.zip');

  String get parentRelativePath {
    final normalized = relativePath.contains('\\')
        ? relativePath.replaceAll('\\', '/')
        : relativePath;
    if (!normalized.contains('/')) return '';
    return normalized.substring(0, normalized.lastIndexOf('/'));
  }

  int get relativePathDepth =>
      relativePath.split('/').where((p) => p.isNotEmpty).length;

  String? get contentOrString {
    if (content != null) return content;
    if (bytes == null) return null;
    try {
      return String.fromCharCodes(bytes!);
    } catch (_) {
      return null;
    }
  }
}
