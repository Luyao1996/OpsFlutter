import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/router_api.dart';

class RouterEditModal extends ConsumerStatefulWidget {
  final RouterInfo? router; // null = create mode
  final RouterApi api;
  /// 打开 modal 时所处网吧的 id；scriptTypesProvider 按此 key 取数，
  /// 保证 modal 操作与指定网吧绑定，不随后续切换变化。
  final int? netbarId;

  const RouterEditModal({super.key, this.router, required this.api, required this.netbarId});

  @override
  ConsumerState<RouterEditModal> createState() => _RouterEditModalState();
}

class _RouterEditModalState extends ConsumerState<RouterEditModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  String? _selectedType;
  bool _enabled = true;
  bool _saving = false;
  bool _deleting = false;

  bool get _isEdit => widget.router != null;
  bool get _busy => _saving || _deleting;

  @override
  void initState() {
    super.initState();
    final r = widget.router;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _hostCtrl = TextEditingController(text: r?.host ?? '');
    _userCtrl = TextEditingController(text: r?.user ?? '');
    _passCtrl = TextEditingController(text: r?.pass ?? '');
    _selectedType = r?.type.isNotEmpty == true ? r!.type : null;
    _enabled = r?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'host': _hostCtrl.text.trim(),
        'type': _selectedType ?? '',
        'user': _userCtrl.text.trim(),
        'pass': _passCtrl.text.trim(),
        'enabled': _enabled,
      };
      if (_isEdit) {
        await widget.api.update(widget.router!.id, data);
      } else {
        await widget.api.create(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isEdit ? "修改" : "新增"}失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除路由器「${widget.router!.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await widget.api.delete(widget.router!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typesAsync = ref.watch(scriptTypesProvider(widget.netbarId));

    return ResponsiveDialogScaffold(
      title: _isEdit ? '修改路由器' : '新增路由器',
      maxWidth: 440,
      bodyPadding: const EdgeInsets.all(24),
      body: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                // Name
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: '路由器名称 *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                ),
                const SizedBox(height: 12),
                // Host
                TextFormField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(labelText: '路由器地址 *', hintText: '192.168.1.1'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入地址' : null,
                ),
                const SizedBox(height: 12),
                // Type dropdown
                typesAsync.when(
                  data: (types) => types.isEmpty
                      ? TextFormField(
                          initialValue: _selectedType,
                          decoration: const InputDecoration(labelText: '路由器类型 *'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入类型' : null,
                          onChanged: (v) => _selectedType = v,
                        )
                      : DropdownButtonFormField<String>(
                          value: types.contains(_selectedType) ? _selectedType : null,
                          decoration: const InputDecoration(labelText: '路由器类型 *'),
                          validator: (v) => (v == null || v.isEmpty) ? '请选择类型' : null,
                          items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _selectedType = v),
                        ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, __) {
                    debugPrint('[RouterEditModal] scriptTypes error: $e');
                    return TextFormField(
                      initialValue: _selectedType,
                      decoration: InputDecoration(labelText: '路由器类型 *（加载失败: $e）'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '请输入类型' : null,
                      onChanged: (v) => _selectedType = v,
                    );
                  },
                ),
                const SizedBox(height: 12),
                // User & Pass
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _userCtrl,
                        decoration: const InputDecoration(labelText: '登录账号 *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passCtrl,
                        decoration: const InputDecoration(labelText: '登录密码 *'),
                        obscureText: true,
                        validator: (v) => (v == null || v.trim().isEmpty) ? '请输入密码' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Enabled switch
                SwitchListTile(
                  title: const Text('启用', style: TextStyle(fontSize: 14)),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppColors.iosBlue,
                ),
          ],
        ),
      ),
      footer: Row(
        children: [
          if (_isEdit)
            ElevatedButton(
              onPressed: _busy ? null : _delete,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: _deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('删除'),
            ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _busy ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? '保存' : '新增'),
          ),
        ],
      ),
    );
  }
}
