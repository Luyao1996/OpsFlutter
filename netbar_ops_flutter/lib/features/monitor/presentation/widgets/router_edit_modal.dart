import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/router_api.dart';

class RouterEditModal extends ConsumerStatefulWidget {
  final RouterInfo? router; // null = create mode
  final RouterApi api;

  const RouterEditModal({super.key, this.router, required this.api});

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
    final typesAsync = ref.watch(scriptTypesProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  _isEdit ? '修改路由器' : '新增路由器',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 20),
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
                          decoration: const InputDecoration(labelText: '路由器类型'),
                          onChanged: (v) => _selectedType = v,
                        )
                      : DropdownButtonFormField<String>(
                          value: types.contains(_selectedType) ? _selectedType : null,
                          decoration: const InputDecoration(labelText: '路由器类型'),
                          items: types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                          onChanged: (v) => setState(() => _selectedType = v),
                        ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, __) {
                    debugPrint('[RouterEditModal] scriptTypes error: $e');
                    return TextFormField(
                      initialValue: _selectedType,
                      decoration: InputDecoration(labelText: '路由器类型（加载失败: $e）'),
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
                        decoration: const InputDecoration(labelText: '登录账号'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _passCtrl,
                        decoration: const InputDecoration(labelText: '登录密码'),
                        obscureText: true,
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
                const SizedBox(height: 20),
                // Actions
                Row(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
