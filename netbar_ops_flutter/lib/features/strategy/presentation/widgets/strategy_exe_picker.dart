import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 执行文件选择结果：虚拟路径 + 源文件 id。
/// [groupFileId] 提交时作为 `startup[group_file_id]`（对齐 web
/// StrategyAddDialog.vue:741 `row.group_file_id ?? row.id`）。
typedef StrategyExePicked = ({String path, int? groupFileId});

/// 注入式执行文件选择器（T8c-2 新增）。
///
/// 【为什么要注入，留痕】共享层原有的 [ExePickerDialog] 走的是**资源中心**
/// （resource_api → /file/view）；web 的策略表单选执行文件走的却是
/// **下发文件区**（FileSelectDialog source='delivery' → /delivery/tree，
/// StrategyAddDialog.vue:247-250）——两者是不同的文件域，资源中心里能选到的文件
/// 未必已经下发到目标网吧，选出来的路径客户端根本取不到。
///
/// 但 [ExePickerDialog] 是 V1 两个旧页面正在用的实现，不能改它本体。
/// 故共享层只留一个可选注入点：**默认 null = 沿用各弹窗原有的执行文件控件**
/// （新增弹窗 = ExecutablePathPickerField，编辑弹窗 = 只读文本框），
/// channel_v2 调用时注入下发树选择器。V1 不传 → 代码路径与改动前完全一致。
typedef StrategyExePicker = Future<StrategyExePicked?> Function(
    BuildContext context);

/// 由注入选择器驱动的只读路径输入框。
/// 外观刻意与 [ExecutablePathPickerField] 保持一致（只读 + 右侧清除/展开按钮），
/// 差别只在点开后弹哪个选择器。
class StrategyInjectedExeField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final StrategyExePicker picker;

  /// 选中回调：调用方据此更新 startup[group_file_id]
  final ValueChanged<StrategyExePicked> onPicked;

  /// 清空回调：路径清空时同步把 group_file_id 置空
  /// （对齐 web clearStartupPath，StrategyAddDialog.vue:581-584）
  final VoidCallback? onCleared;

  final bool enabled;

  const StrategyInjectedExeField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.picker,
    required this.onPicked,
    this.validator,
    this.onCleared,
    this.enabled = true,
  });

  @override
  State<StrategyInjectedExeField> createState() =>
      _StrategyInjectedExeFieldState();
}

class _StrategyInjectedExeFieldState extends State<StrategyInjectedExeField> {
  bool _opening = false;

  bool get _hasValue => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternalChange);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() {});
  }

  Future<void> _open() async {
    if (!widget.enabled || _opening) return;
    setState(() => _opening = true);
    try {
      final picked = await widget.picker(context);
      if (!mounted || picked == null) return;
      widget.controller.text = picked.path;
      widget.onPicked(picked);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _clear() {
    widget.controller.clear();
    widget.onCleared?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      readOnly: true,
      enabled: widget.enabled,
      validator: widget.validator,
      onTap: _open,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: widget.decoration.copyWith(
        suffixIcon: _hasValue
            ? IconButton(
                onPressed: _clear,
                icon: Icon(LucideIcons.x, size: 16, color: Colors.grey.shade500),
                tooltip: '清除',
              )
            : IconButton(
                onPressed: _open,
                icon: Icon(LucideIcons.chevronDown,
                    size: 16, color: Colors.grey.shade500),
                tooltip: '选择执行文件',
              ),
      ),
    );
  }
}
