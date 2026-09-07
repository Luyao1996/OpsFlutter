import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../../../../shared/utils/top_notice.dart';

/// 终端备注编辑器（全屏对话框，保存成功后 pop 出新的 HTML 串）。
///
/// 原先是 terminal_detail_page.dart 里的私有类，提取出来给三处共用：
/// 终端详情页、监控页卡片上的备注角标、备注搜索的结果项 —— 与 toolboxPage
/// 「卡片上直接编辑备注」的入口方式对齐。
class RemarkEditDialog extends StatefulWidget {
  final String terminalName;
  final String initialHtml;
  final Future<void> Function(String html) onSave;
  const RemarkEditDialog({
    super.key,
    required this.terminalName,
    required this.initialHtml,
    required this.onSave,
  });

  @override
  State<RemarkEditDialog> createState() => _RemarkEditDialogState();
}

class _RemarkEditDialogState extends State<RemarkEditDialog> {
  late quill.QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController.basic();
    if (widget.initialHtml.isNotEmpty) {
      try {
        // 预处理：给无 style 的 <p> 注入 text-align:left
        // 原因：flutter_quill_delta_from_html 1.5.3 的 paragraphToOp 仅在
        // blockAttributes(align/direction/indent) 非空时才插段末 \n（见 default_html_to_ops.dart:75-78），
        // 否则相邻 <p>...</p><p>...</p> 会拼成一行。给 <p> 加 align 强制触发分段。
        final preprocessed = _ensureParagraphAlign(widget.initialHtml);
        final delta = HtmlToDelta().convert(preprocessed);
        _controller = quill.QuillController(
          document: quill.Document.fromDelta(delta),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        debugPrint('[RemarkEdit] HtmlToDelta failed: $e — fallback to empty doc');
      }
    }
  }

  /// 给所有无 style/align/dir 属性的 `<p>` 注入 `style="text-align:left;"`。
  /// 兜底 flutter_quill_delta_from_html 段落分隔符丢失的 bug；
  /// 已有样式属性的段落保持不变，避免覆盖用户原有 align。
  String _ensureParagraphAlign(String html) {
    return html.replaceAllMapped(
      RegExp(r'<p(\s+[^>]*)?>'),
      (m) {
        final attrs = m.group(1) ?? '';
        if (attrs.contains('style=') ||
            attrs.contains('align=') ||
            attrs.contains('dir=')) {
          return m.group(0)!;
        }
        return '<p$attrs style="text-align:left;">';
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final deltaJson = _controller.document.toDelta().toJson();
      // inlineStylesFlag: true → 所有样式以 inline `style="..."` 输出而非 CSS class
      // (color/background/text-align/font/size/indent 全部受益)。
      // 否则输出 `class="ql-color-red"` 等无法被 HtmlToDelta 反向识别，导致 round-trip 丢样式。
      final converter = QuillDeltaToHtmlConverter(
        List<Map<String, dynamic>>.from(deltaJson),
        ConverterOptions(
          converterOptions: OpConverterOptions(inlineStylesFlag: true),
        ),
      );
      final html = converter.convert();
      await widget.onSave(html);
      if (!mounted) return;
      showTopNotice(context, '备注已保存', level: NoticeLevel.success);
      Navigator.of(context).pop(html);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 标题栏
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.terminalName} - 备注信息',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 18),
                  splashRadius: 18,
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          // 富文本工具栏（flutter_quill 11.x：参数 config + 类名 ...Config）
          quill.QuillSimpleToolbar(
            controller: _controller,
            config: const quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: true,
              showAlignmentButtons: true,
              showBackgroundColorButton: true,
              showColorButton: true,
              showLink: true,
              showListBullets: true,
              showListNumbers: true,
              showListCheck: true,
              showQuote: true,
              showCodeBlock: true,
              showFontFamily: true,
              showFontSize: true,
              showHeaderStyle: true,
              showIndent: true,
              showStrikeThrough: false,
              showInlineCode: false,
              showSubscript: false,
              showSuperscript: false,
              showSearchButton: false,
            ),
          ),
          const Divider(height: 1),
          // 编辑区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: quill.QuillEditor.basic(
                controller: _controller,
                focusNode: _focusNode,
                config: const quill.QuillEditorConfig(
                  placeholder: '请输入备注内容...',
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _handleSave,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
