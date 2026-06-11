import 'package:flutter/material.dart';

import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/terminal_api.dart';
import '../../data/terminal_models.dart';

/// 编辑终端名称弹窗 —— 对标 toolboxPage `EditNameDialog.vue`。
/// 只编辑别名（机号前缀不可改），回显纯别名 [Terminal.alias] 而非合成显示名 [Terminal.name]。
/// 保存走中央 HTTP `POST /terminals/{id}/name`；成功 `pop(true)`，由调用方刷新数据。
/// 经 [showAdaptive] 打开：宽屏 Dialog，窄屏（手机）全屏页。
class EditNameModal extends StatefulWidget {
  final Terminal terminal;
  final TerminalApi api;

  const EditNameModal({super.key, required this.terminal, required this.api});

  @override
  State<EditNameModal> createState() => _EditNameModalState();
}

class _EditNameModalState extends State<EditNameModal> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.terminal.alias);
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveName(widget.terminal.id, _nameCtrl.text.trim());
      if (!mounted) return;
      showTopNotice(context, '保存成功', level: NoticeLevel.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '编辑名称',
      maxWidth: 360,
      bodyPadding: const EdgeInsets.all(24),
      body: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameCtrl,
          autofocus: true,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '输入新的名称',
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '名称不能为空' : null,
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
    );
  }
}
