import 'package:flutter/material.dart';

import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/channel_v2_api.dart';
import '../../data/channel_v2_models.dart';
import '../channel_v2_file_actions.dart';
import 'v2_file_card.dart';

/// 文件属性弹窗（对标 web FilePropsDialog.vue，248 行）。
///
/// 数据源 GET /file/attribute → `data.userFile`。
/// ⚠ 【字段陷阱】隐藏标记在本接口叫 `hidden`（V2FileAttribute.hidden），
///   在列表接口 /file/view 叫 `is_hide`（V2File.isHide）。两者**不可互相套用**，
///   混用会让隐藏开关恒为关（或恒为开）。兜底路径用的是列表字段 isHide，属于
///   有意的跨字段回退，已在下方标注。
class V2FilePropsDialog extends StatefulWidget {
  final ChannelV2Api api;
  final V2File file;

  /// 隐藏状态变更后回调 → 页面 refreshAll()（三区都可能引用同一源文件）
  final VoidCallback? onHideChanged;

  const V2FilePropsDialog({
    super.key,
    required this.api,
    required this.file,
    this.onHideChanged,
  });

  @override
  State<V2FilePropsDialog> createState() => _V2FilePropsDialogState();
}

class _V2FilePropsDialogState extends State<V2FilePropsDialog> {
  bool _loading = true;
  bool _hideLoading = false;

  String _name = '';
  bool _isFolder = false;
  int? _size;
  String _uploader = '-';
  String _createdAt = '';
  String _updatedAt = '';
  bool _hidden = false;

  /// 下发节点的文件不允许在这里改隐藏，只对资源区文件开放
  /// （对齐 FilePropsDialog.vue:100-103：没有 delivery_id 才是资源区文件）
  bool get _canEditHide => widget.file.deliveryNodeId == null;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final gid = widget.file.groupFileId;
    if (gid == null) {
      // initState 同步路径：直接置位，不能 setState（首帧尚未 build）
      _fallbackFromFile();
      _loading = false;
      return;
    }
    try {
      final attr = await widget.api.getFileAttribute(gid);
      if (!mounted) return;
      if (attr == null) {
        _fallbackFromFile();
      } else {
        _name = attr.name.isNotEmpty ? attr.name : widget.file.name;
        _isFolder = attr.isFolder;
        _size = attr.size ?? widget.file.size;
        _uploader = attr.uploader.isNotEmpty ? attr.uploader : '-';
        _createdAt = attr.createdAt;
        _updatedAt = attr.updatedAt;
        _hidden = attr.hidden;
      }
    } catch (e) {
      // 接口失败**不能空白**：退回前端已有字段渲染（对齐 :133-138,141-157）
      debugPrint('[V2FilePropsDialog] /file/attribute failed, fallback: $e');
      if (!mounted) return;
      _fallbackFromFile();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fallbackFromFile() {
    final f = widget.file;
    _name = f.name;
    _isFolder = f.isFolder;
    _size = f.size;
    _uploader = f.nickname.isNotEmpty ? f.nickname : '-';
    _createdAt = '';
    _updatedAt = f.updateTime ?? '';
    // 兜底路径只能拿列表字段 is_hide（属性接口的 hidden 拿不到）——刻意的跨字段回退
    _hidden = f.isHide;
  }

  Future<void> _toggleHide(bool val) async {
    final gid = widget.file.groupFileId;
    if (gid == null) return;
    setState(() {
      _hidden = val;
      _hideLoading = true;
    });
    try {
      if (val) {
        await widget.api.hideResource(gid);
      } else {
        await widget.api.unhideResource(gid);
      }
      if (!mounted) return;
      showTopNotice(context, val ? '已隐藏' : '已取消隐藏',
          level: NoticeLevel.success);
      widget.onHideChanged?.call();
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, v2ErrMessage(e, '操作失败'), level: NoticeLevel.error);
      setState(() => _hidden = !val); // 回滚（对齐 :171）
    } finally {
      if (mounted) setState(() => _hideLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;
    return ResponsiveDialogScaffold(
      title: (_loading ? f.isFolder : _isFolder) ? '文件夹属性' : '文件属性',
      maxWidth: 420,
      body: _loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text('加载中...',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _row('名称', _name),
                _row('类型',
                    _isFolder ? '文件夹' : (f.extension.isNotEmpty ? f.extension : '文件')),
                if (!_isFolder) _row('大小', v2FormatSize(_size).isEmpty ? '-' : v2FormatSize(_size)),
                if (_uploader.isNotEmpty) _row('上传人', _uploader),
                if (_createdAt.isNotEmpty) _row('上传时间', _createdAt),
                if (_updatedAt.isNotEmpty) _row('修改时间', _updatedAt),
                if (f.groupName.isNotEmpty || f.sourceName.isNotEmpty)
                  _row('所属',
                      f.sourceName.isNotEmpty ? f.sourceName : f.groupName),
                if (f.groupFileId != null)
                  _row('文件 ID', '${f.groupFileId}', mono: true),
                if (f.deliveryNodeId != null)
                  _row('下发 ID', '${f.deliveryNodeId}', mono: true),
                if (_canEditHide)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 80,
                          child: Text('隐藏',
                              style: TextStyle(
                                  fontSize: 13, color: Color(0xFF6B7280))),
                        ),
                        Checkbox(
                          value: _hidden,
                          visualDensity: VisualDensity.compact,
                          onChanged: _hideLoading
                              ? null
                              : (v) => _toggleHide(v == true),
                        ),
                        Text(
                          '隐藏此${_isFolder ? '文件夹' : '文件'}',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF1F2937)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: mono ? 12 : 13,
                color: mono ? const Color(0xFF6B7280) : const Color(0xFF1F2937),
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
