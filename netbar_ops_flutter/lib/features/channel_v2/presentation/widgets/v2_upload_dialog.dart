import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/v2_file_source.dart';
import '../../data/v2_upload_service.dart';

/// V2 上传弹窗（对标 web components/channel-v2/UploadDialog.vue）。
///
/// 与 web 的能力差异（平台限制，非遗漏）：
///   - 无拖入区 / Ctrl+V 粘贴：web 靠 DataTransferItem.webkitGetAsEntry 递归读目录，
///     Flutter 侧本批不做（拖拽在 T8b-2 按 desktop_drop 单独接）
///   - 移动端不渲染「选择文件夹」：系统选择器无目录树能力（V2FileSource.supportsFolderPick）
class V2UploadDialog extends StatefulWidget {
  final V2UploadService service;

  /// 上传目标目录 id（'0' = 根目录）。
  /// **打开弹窗那一刻的快照**：上传中切组/切目录不得改变已入队文件的落点
  /// （对齐 ChannelV2Page.vue:506-509 openUploadDialog 传值即固定）。
  final String folderId;

  /// 归属字段快照（如小组区的 group_id），同样是打开那一刻的值
  final Map<String, String> extraParams;

  /// 自动下发目标（"拖到下发区上传"路径才有；本批入口恒 null）
  final V2AutoDistribute? autoDistribute;

  /// 全部跑完**只回调一次**：逐个回调会让父页把两个资源区各刷 N 遍
  /// （对齐 UploadDialog.vue:337-338 的注释与实现）
  final VoidCallback? onUploaded;

  const V2UploadDialog({
    super.key,
    required this.service,
    required this.folderId,
    this.extraParams = const {},
    this.autoDistribute,
    this.onUploaded,
  });

  @override
  State<V2UploadDialog> createState() => _V2UploadDialogState();
}

class _V2UploadDialogState extends State<V2UploadDialog> {
  final List<V2UploadItem> _items = [];
  bool _isUploading = false;

  bool get _allDone =>
      _items.isNotEmpty && _items.every((f) => f.status == V2UploadStatus.done);

  int get _pendingCount => _items
      .where((f) =>
          f.status == V2UploadStatus.idle || f.status == V2UploadStatus.error)
      .length;

  bool get _canStart => !_isUploading && _pendingCount > 0;

  /// 总进度：done 记 100，其余取各自 progress
  int get _overallPercent {
    if (_items.isEmpty) return 0;
    var sum = 0;
    for (final f in _items) {
      sum += f.status == V2UploadStatus.done ? 100 : f.progress;
    }
    return (sum / _items.length).round();
  }

  // ====== 文件来源 ======

  Future<void> _pickFiles() async {
    final entries = await v2FileSource.pickFiles();
    if (entries.isEmpty || !mounted) return;
    setState(() => _items.addAll(entries.map(V2UploadItem.new)));
  }

  Future<void> _pickFolder() async {
    final entries = await v2FileSource.pickFolder();
    if (!mounted) return;
    if (entries.isEmpty) {
      showTopNotice(context, '所选文件夹为空', level: NoticeLevel.warning);
      return;
    }
    setState(() => _items.addAll(entries.map(V2UploadItem.new)));
  }

  void _removeOne(int index) {
    if (_isUploading) return;
    setState(() => _items.removeAt(index));
  }

  void _clearAll() {
    if (_isUploading) return;
    setState(_items.clear);
  }

  /// 单项取消（对齐 UploadDialog.vue:277-280：立刻标记 + 立刻置状态）
  void _cancelOne(V2UploadItem item) {
    setState(() {
      item.cancelled = true;
      item.status = V2UploadStatus.canceled;
    });
  }

  void _cancelAll() {
    setState(() {
      for (final f in _items) {
        if (f.status == V2UploadStatus.uploading ||
            f.status == V2UploadStatus.idle) {
          f.cancelled = true;
          f.status = V2UploadStatus.canceled;
        }
      }
    });
  }

  // ====== 上传 ======

  Future<void> _startUpload() async {
    if (!_canStart) return;
    final queue = _items
        .where((f) =>
            f.status == V2UploadStatus.idle || f.status == V2UploadStatus.error)
        .toList();
    if (queue.isEmpty) return;
    for (final f in queue) {
      f.status = V2UploadStatus.idle;
      f.progress = 0;
      f.error = null;
      f.cancelled = false;
    }
    setState(() => _isUploading = true);

    final result = await widget.service.uploadBatch(
      items: queue,
      folderId: widget.folderId,
      extra: widget.extraParams,
      autoDistribute: widget.autoDistribute,
      onChanged: () {
        if (mounted) setState(() {});
      },
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    // 全部跑完才回调一次
    if (result.succeeded > 0) widget.onUploaded?.call();

    if (result.failed == 0 && result.canceled == 0 && result.succeeded > 0) {
      showTopNotice(context, '全部上传完成（${result.succeeded} 个）',
          level: NoticeLevel.success);
    } else if (result.succeeded > 0) {
      showTopNotice(
        context,
        '已上传 ${result.succeeded} 个'
        '${result.failed > 0 ? '，${result.failed} 个失败' : ''}'
        '${result.canceled > 0 ? '，${result.canceled} 个已取消' : ''}',
        level: NoticeLevel.warning,
      );
    } else if (result.failed > 0) {
      showTopNotice(context, '全部上传失败', level: NoticeLevel.error);
    }

    if (result.distributedOk > 0) {
      showTopNotice(context, '已下发 ${result.distributedOk} 项',
          level: NoticeLevel.success);
    }
  }

  // ====== UI ======

  @override
  Widget build(BuildContext context) {
    // 上传中禁止关窗：State 被 dispose 后串行队列会成孤儿（无人消费进度、
    // 无人收尾），且 showCloseButton 必须同时关掉——关闭按钮直接调
    // Navigator.pop，PopScope 拦不住它
    return PopScope(
      canPop: !_isUploading,
      child: ResponsiveDialogScaffold(
        title: '上传文件',
        maxWidth: 560,
        // 固定高度：body 内是 Expanded 列表，不定高会让空态弹窗撑到屏幕 85%
        maxHeight: 520,
        scrollableBody: false,
        showCloseButton: !_isUploading,
        body: _buildBody(),
        footer: _buildFooter(),
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_items.isEmpty)
            Expanded(child: _buildEmpty())
          else ...[
            _buildListHead(),
            const SizedBox(height: 8),
            Expanded(child: _buildList()),
          ],
          if (_isUploading) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _overallPercent / 100,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF007AFF)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('$_overallPercent%',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final canPickFile = v2FileSource.supportsFilePick;
    final canPickFolder = v2FileSource.supportsFolderPick;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0x1A007AFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(LucideIcons.uploadCloud,
                size: 26, color: Color(0xFF007AFF)),
          ),
          const SizedBox(height: 14),
          const Text('选择要上传的文件',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937))),
          const SizedBox(height: 6),
          Text(
            canPickFolder ? '支持多选文件，或整个文件夹上传' : '支持多选文件',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (canPickFile)
                OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(LucideIcons.plus, size: 15),
                  label: const Text('选择文件'),
                ),
              // 移动端 / Web 不渲染该入口
              if (canPickFolder) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickFolder,
                  icon: const Icon(LucideIcons.folderPlus, size: 15),
                  label: const Text('选择文件夹'),
                ),
              ],
            ],
          ),
          if (!canPickFile && !canPickFolder)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('当前平台暂不支持上传',
                  style: TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
            ),
        ],
      ),
    );
  }

  Widget _buildListHead() {
    // 用 Expanded 而不是 Spacer：窄屏（手机全屏页）下按钮总宽接近可用宽度，
    // Spacer 只吃剩余空间不压缩文字，会直接 RenderFlex overflow
    return Row(
      children: [
        Expanded(
          child: Text('已选 ${_items.length} 个文件',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500)),
        ),
        if (v2FileSource.supportsFilePick)
          TextButton.icon(
            onPressed: _isUploading ? null : _pickFiles,
            icon: const Icon(LucideIcons.plus, size: 14),
            label: const Text('添加文件', style: TextStyle(fontSize: 12)),
          ),
        if (v2FileSource.supportsFolderPick)
          TextButton.icon(
            onPressed: _isUploading ? null : _pickFolder,
            icon: const Icon(LucideIcons.folderPlus, size: 14),
            label: const Text('添加文件夹', style: TextStyle(fontSize: 12)),
          ),
        TextButton(
          onPressed: _isUploading ? null : _clearAll,
          child: const Text('清空',
              style: TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, i) => _buildRow(_items[i], i),
    );
  }

  Widget _buildRow(V2UploadItem f, int index) {
    final bg = switch (f.status) {
      V2UploadStatus.done => const Color(0x0F16A34A),
      V2UploadStatus.error => const Color(0x0FDC2626),
      _ => const Color(0xFFF8FAFC),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Icon(_iconFor(f.name),
                size: 14, color: const Color(0xFF6B7280)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // 文件夹内文件显示相对路径，看得出会建到哪一层目录
                  f.entry.folderPath.isEmpty
                      ? f.name
                      : '${f.entry.folderPath}/${f.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatSize(f.size)} · ${_statusText(f)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: _statusColor(f.status)),
                ),
                if (f.status == V2UploadStatus.uploading) ...[
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: f.progress / 100,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF007AFF)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (f.status == V2UploadStatus.uploading)
            IconButton(
              tooltip: '取消',
              onPressed: () => _cancelOne(f),
              icon: const Icon(LucideIcons.x, size: 15),
              color: const Color(0xFF9CA3AF),
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
            )
          else
            IconButton(
              tooltip: '移除',
              onPressed: _isUploading ? null : () => _removeOne(index),
              icon: const Icon(LucideIcons.trash2, size: 15),
              color: const Color(0xFF9CA3AF),
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_isUploading)
          OutlinedButton(
            onPressed: _cancelAll,
            child: const Text('全部取消'),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_allDone ? '关闭' : '取消'),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _canStart ? _startUpload : null,
          child: Text(_isUploading
              ? '上传中…'
              : (_allDone ? '全部完成' : '开始上传 ($_pendingCount)')),
        ),
      ],
    );
  }

  String _statusText(V2UploadItem f) => switch (f.status) {
        V2UploadStatus.uploading => '${f.progress}%',
        V2UploadStatus.done => '完成',
        V2UploadStatus.error =>
          f.error?.isNotEmpty == true ? '失败：${f.error}' : '失败',
        V2UploadStatus.canceled => '已取消',
        V2UploadStatus.idle => '等待上传',
      };

  Color _statusColor(V2UploadStatus s) => switch (s) {
        V2UploadStatus.uploading => const Color(0xFF007AFF),
        V2UploadStatus.done => const Color(0xFF16A34A),
        V2UploadStatus.error => const Color(0xFFDC2626),
        _ => const Color(0xFF9CA3AF),
      };
}

/// 扩展名 → 图标（对齐 UploadDialog.vue:369-383 iconForFile 的分类）
IconData _iconFor(String name) {
  final idx = name.lastIndexOf('.');
  final ext =
      (idx <= 0 || idx == name.length - 1) ? '' : name.substring(idx + 1).toLowerCase();
  switch (ext) {
    case 'exe':
    case 'msi':
      return LucideIcons.settings;
    case 'pdf':
      return LucideIcons.fileText;
    case 'doc':
    case 'docx':
      return LucideIcons.fileText;
    case 'xls':
    case 'xlsx':
      return LucideIcons.fileSpreadsheet;
    case 'zip':
    case 'rar':
    case '7z':
      return LucideIcons.fileArchive;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
      return LucideIcons.fileImage;
    case 'mp4':
      return LucideIcons.fileVideo;
    case 'mp3':
      return LucideIcons.fileAudio;
    case 'txt':
      return LucideIcons.fileText;
    case 'ini':
    case 'cfg':
    case 'conf':
      return LucideIcons.fileCode;
    default:
      return LucideIcons.file;
  }
}

String _formatSize(int? bytes) {
  if (bytes == null) return '-';
  const units = ['B', 'KB', 'MB', 'GB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  return '${n.toStringAsFixed(n < 10 && i > 0 ? 1 : 0)} ${units[i]}';
}
