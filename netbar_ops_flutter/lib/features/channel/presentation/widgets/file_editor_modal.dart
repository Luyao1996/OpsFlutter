import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/powershell.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/resource_api.dart';

class FileEditorModal extends StatefulWidget {
  final Resource file;
  final VoidCallback onSuccess;
  final bool readOnly;

  const FileEditorModal({
    super.key,
    required this.file,
    required this.onSuccess,
    this.readOnly = false,
  });

  @override
  State<FileEditorModal> createState() => _FileEditorModalState();
}

class _FileEditorModalState extends State<FileEditorModal> {
  final ResourceApi _api = ResourceApi();
  CodeLineEditingController? _codeController;
  final CodeScrollController _scrollController = CodeScrollController();
  final FocusNode _editorFocusNode = FocusNode();

  static const int _warnLimit = 2 * 1024 * 1024; // 2MB+ show warning
  static const int _previewLimit = 200 * 1024; // only preview first 200KB

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _hasChanges = false;
  bool _isFullscreen = false;
  bool _forceLoad = false;
  bool _isPreview = false;
  bool _isTooLarge = false;
  String _originalContent = '';
  final String _previewText = '';

  @override
  void initState() {
    super.initState();
    _initCodeController('');
    _loadContent();
    _requestFocus();
  }

  @override
  void dispose() {
    _codeController?.dispose();
    _scrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  Mode? _getLanguageMode(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    final langMap = <String, Mode>{
      'dart': langDart,
      'js': langJavascript,
      'ts': langTypescript,
      'json': langJson,
      'xml': langXml,
      'html': langXml,
      'css': langCss,
      'py': langPython,
      'java': langJava,
      'go': langGo,
      'sql': langSql,
      'sh': langBash,
      'ps1': langPowershell,
      'yaml': langYaml,
      'yml': langYaml,
      'md': langMarkdown,
    };
    return langMap[ext];
  }

  void _initCodeController(String text) {
    _originalContent = text;
    _codeController?.dispose();
    _codeController = CodeLineEditingController.fromText(text);
    _codeController!.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_hasChanges && _codeController!.text != _originalContent) {
      setState(() => _hasChanges = true);
    }
  }

  String _collectDocumentText() {
    return _codeController?.text ?? '';
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
      _isTooLarge = false;
    });
    try {
      // 超过 200KB 的文件不做在线预览/编辑，避免卡顿
      if (!_forceLoad) {
        final knownSize = widget.file.size;
        if (knownSize > _previewLimit) {
          _isTooLarge = true;
          _error = '文件过大，请下载后查看';
          return;
        }

        // size 不可靠时，用流式限量读取判断是否超限
        final bytes = await _api.downloadBytesLimited(
          widget.file.id,
          _previewLimit + 1,
        );
        if (bytes.length > _previewLimit) {
          _isTooLarge = true;
          _error = '文件过大，请下载后查看';
          return;
        }

        final text = utf8.decode(bytes, allowMalformed: true);
        _isPreview = false;
        _initCodeController(text);
      } else {
        // 强制加载（仅用于小文件重载）
        final raw = await _fetchContentWithFallback(widget.file.id);
        _isPreview = false;
        _initCodeController(raw);
      }
      _hasChanges = false;
    } catch (e) {
      setState(() => _error = '加载失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<String> _fetchContentWithFallback(int fileId) async {
    try {
      return await _api.getContent(fileId).timeout(const Duration(seconds: 6));
    } catch (_) {
      final bytes = await _api
          .downloadBytes(fileId)
          .timeout(const Duration(seconds: 8));
      if (bytes.isEmpty) throw Exception('文件内容为空或无法获取');
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  Future<String> _fetchPreviewContent(int fileId) async {
    final bytes = await _api
        .downloadBytesLimited(fileId, _previewLimit + 2048)
        .timeout(const Duration(seconds: 8));
    final limited = bytes.length > _previewLimit
        ? bytes.sublist(0, _previewLimit)
        : bytes;
    return utf8.decode(limited, allowMalformed: true);
  }

  Future<void> _handleSave() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.update(widget.file.id, content: _collectDocumentText());
      setState(() => _hasChanges = false);
      if (!mounted) return;
      widget.onSuccess();
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = '保存失败: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<bool> _handleClose() async {
    if (!_hasChanges) return true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的更改'),
        content: const Text('您有未保存的更改，确定要关闭吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃更改', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirm ?? false;
  }

  void _requestFocus() {
    if (!_isPreview && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocusNode.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildEditor()),
        _buildFooter(),
      ],
    );

    if (context.isNarrow) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: content),
      );
    }

    final size = MediaQuery.of(context).size;
    final dialogWidth = _isFullscreen ? size.width * 0.98 : 800.0;
    final dialogHeight = _isFullscreen ? size.height * 0.95 : 600.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.xl,
        ),
        child: content,
      ),
    );
  }

  Widget _buildHeader() {
    final isPhone = context.isPhone;
    return Container(
      padding: EdgeInsets.all(isPhone ? 16 : 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.fileEdit,
              size: 20,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_hasChanges) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '未保存',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  widget.readOnly ? '查看文件内容' : '编辑文件内容',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _isFullscreen = !_isFullscreen),
            padding: EdgeInsets.zero,
            constraints: isPhone ? const BoxConstraints.tightFor(width: 40, height: 40) : null,
            icon: Icon(
              _isFullscreen ? LucideIcons.minimize2 : LucideIcons.maximize2,
              size: 20,
              color: Colors.grey.shade500,
            ),
          ),
          IconButton(
            onPressed: () async {
              if (!mounted) return;
              final shouldClose = await _handleClose();
              if (!mounted) return;
              if (shouldClose) Navigator.of(context).pop();
            },
            padding: EdgeInsets.zero,
            constraints: isPhone ? const BoxConstraints.tightFor(width: 40, height: 40) : null,
            icon: Icon(LucideIcons.x, size: 20, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isTooLarge) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertTriangle,
              size: 48,
              color: Colors.orange.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              '文件过大，请下载后查看',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.name,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (_isPreview) {
      return Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _forceLoad = true;
                        _error = null;
                      });
                      _loadContent();
                    },
                    icon: const Icon(LucideIcons.edit3, size: 14),
                    label: const Text('强制编辑'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Container(
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _previewText,
                  style: const TextStyle(fontSize: 13, fontFamily: 'Consolas'),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null && _collectDocumentText().trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _loadContent,
                  child: const Text('重新加载'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _forceLoad = true;
                      _error = null;
                    });
                    _loadContent();
                  },
                  icon: const Icon(LucideIcons.alertTriangle, size: 16),
                  label: Text(_isPreview ? '强制编辑完整文件' : '强制加载'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (widget.readOnly) {
      final text = _collectDocumentText();
      return Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 13, fontFamily: 'Consolas'),
          ),
        ),
      );
    }

    if (_codeController == null) {
      return const Center(child: Text('编辑器初始化失败'));
    }

    final langMode = _getLanguageMode(widget.file.name);

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: CodeEditor(
        controller: _codeController!,
        scrollController: _scrollController,
        wordWrap: true,
        style: CodeEditorStyle(
          fontSize: 13,
          fontFamily: 'Consolas',
          codeTheme: langMode != null
              ? CodeHighlightTheme(
                  languages: {
                    _getExtension(widget.file.name): CodeHighlightThemeMode(
                      mode: langMode,
                    ),
                  },
                  theme: atomOneLightTheme,
                )
              : null,
        ),
        indicatorBuilder:
            (context, editingController, chunkController, notifier) {
              return Row(
                children: [
                  DefaultCodeLineNumber(
                    controller: editingController,
                    notifier: notifier,
                  ),
                ],
              );
            },
      ),
    );
  }

  String _getExtension(String filename) {
    return filename.split('.').last.toLowerCase();
  }

  Widget _buildFooter() {
    final isPhone = context.isPhone;
    return Container(
      padding: EdgeInsets.all(isPhone ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          if (_error != null)
            Expanded(
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade600),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () async {
              if (!mounted) return;
              final shouldClose = await _handleClose();
              if (!mounted) return;
              if (shouldClose) Navigator.of(context).pop();
            },
            child: Text(
              widget.readOnly ? '关闭' : '取消',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(width: 12),
          if (!widget.readOnly && !_isPreview && !_isTooLarge)
            ElevatedButton.icon(
              onPressed: _saving || !_hasChanges || _isPreview
                  ? null
                  : _handleSave,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(LucideIcons.save, size: 16),
              label: const Text('保存'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iosBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
