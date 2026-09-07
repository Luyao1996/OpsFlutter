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
  late TextEditingController _pass2Ctrl;
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
    _pass2Ctrl = TextEditingController(text: r?.pass2 ?? '');
    // 回填的类型名先 trim：类型表里的名字已经 trim 过（后端配置带前后空格），
    // 不裁掉的话下拉 value 匹配不上任何 item，编辑态会显示成"未选择"
    final type = r?.type.trim() ?? '';
    _selectedType = type.isEmpty ? null : type;
    _enabled = r?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  /// 按脚本类型名在类型表里反查（名字一律 trim 后比：后端 router_types 里是
  /// " 腾讯网吧特权 " 带空格，而记录里存的可能是不带空格的版本）。
  ScriptType? _typeOf(String? name, List<ScriptType> types) {
    if (name == null) return null;
    final key = name.trim();
    for (final t in types) {
      if (t.name.trim() == key) return t;
    }
    return null;
  }

  /// 固定地址：带 defaultHost 的类型（腾讯网吧特权 / 网吧特权服务平台）地址由平台
  /// 定死，选中后一律用类型自带的那个覆盖，输入框同时禁用。
  ///
  /// 不能只在下拉 change 时做 —— 打开一条已存在的记录时 type 是程序赋的、不触发
  /// change，那条老记录里手填过的地址就会漏网；而且类型表是异步拉的，回来得比表单
  /// 赋值晚。所以另有 [_syncWithTypes] 在类型表到达时再同步一次
  /// （对齐 toolboxPage RouterFormDialog.vue 从 @change 改成 watch 的那笔）。
  void _applyTypeSideEffects(ScriptType? hit) {
    if (hit == null) return; // 类型表还没回来，什么都不动，免得抹掉已有值
    if (hit.defaultHost.isNotEmpty) _hostCtrl.text = hit.defaultHost;
    // 切到非网页管理类型时清掉二次密码：该项已隐藏，留着值会被一起提交上去
    if (hit.deviceType != kDeviceTypeWeb) _pass2Ctrl.clear();
  }

  void _onTypeChange(String? name, List<ScriptType> types) {
    setState(() {
      _selectedType = name;
      _applyTypeSideEffects(_typeOf(name, types));
    });
  }

  /// 类型表异步到达后补一次同步：编辑态打开时 _selectedType 已由 initState 赋好，
  /// 但那会儿还查不到 deviceType/defaultHost。只做一次，之后由用户操作驱动。
  bool _typesSynced = false;
  void _syncWithTypes(List<ScriptType> types) {
    if (_typesSynced || types.isEmpty) return;
    _typesSynced = true;
    final hit = _typeOf(_selectedType, types);
    if (hit == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _applyTypeSideEffects(hit));
    });
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
        // 二次密码（仅网页管理类型填），没填就传空串
        'pass2': _pass2Ctrl.text.trim(),
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
        content: Text('确定要删除「${widget.router!.name}」吗？'),
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
    final types = typesAsync.valueOrNull ?? const <ScriptType>[];
    // 类型表异步到达后补一次同步（编辑态打开时 type 已赋好但查不到 deviceType）
    _syncWithTypes(types);
    final currentType = _typeOf(_selectedType, types);
    // 带默认地址的类型（腾讯网吧特权 / 网吧特权服务平台）地址由平台固定，不给改
    final hostLocked = currentType != null && currentType.defaultHost.isNotEmpty;
    final isWebManage = currentType?.deviceType == kDeviceTypeWeb;

    // 文案中性化：这个弹窗同时用于路由器 / 交换机 / 网页管理三类设备，
    // 写死哪一类都会在另外两类下出错（toolboxPage 那边标题直接叫「网页管理」，
    // 建路由器时是不对的，这里不跟）
    return ResponsiveDialogScaffold(
      title: _isEdit ? '修改设备' : '新增设备',
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
                  decoration: const InputDecoration(labelText: '名称 *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                ),
                const SizedBox(height: 12),
                // Host：固定地址的类型下锁死，避免改错打不开
                TextFormField(
                  controller: _hostCtrl,
                  enabled: !hostLocked,
                  decoration: InputDecoration(
                    labelText: '地址 *',
                    hintText: hostLocked ? null : '192.168.1.1:2011',
                    helperText: hostLocked ? '该类型地址已固定，无需填写' : null,
                    helperStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? '请输入地址' : null,
                ),
                const SizedBox(height: 12),
                // Type dropdown：label 带设备类型后缀，选中后自动填该类型的默认地址
                typesAsync.when(
                  data: (types) => types.isEmpty
                      ? TextFormField(
                          initialValue: _selectedType,
                          decoration: const InputDecoration(labelText: '脚本类型 *'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? '请输入类型' : null,
                          onChanged: (v) => _selectedType = v,
                        )
                      : DropdownButtonFormField<String>(
                          value: types.any((t) => t.name == _selectedType) ? _selectedType : null,
                          decoration: const InputDecoration(labelText: '脚本类型 *'),
                          validator: (v) => (v == null || v.isEmpty) ? '请选择类型' : null,
                          items: types
                              .map((t) => DropdownMenuItem(value: t.name, child: Text(t.label)))
                              .toList(),
                          onChanged: (v) => _onTypeChange(v, types),
                        ),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, __) {
                    debugPrint('[RouterEditModal] scriptTypes error: $e');
                    return TextFormField(
                      initialValue: _selectedType,
                      decoration: InputDecoration(labelText: '脚本类型 *（加载失败: $e）'),
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
                // 二次密码：仅网页管理类型显示，选填（部分平台没开这道验证）
                if (isWebManage) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass2Ctrl,
                    decoration: const InputDecoration(
                      labelText: '二次密码',
                      hintText: '没有可不填',
                    ),
                    obscureText: true,
                  ),
                ],
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
