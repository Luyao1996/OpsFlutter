import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/resource_path_display.dart';
import '../../data/resource_api.dart' as res;
import 'exe_picker_dialog.dart';

class ExecutablePathPickerField extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final FormFieldValidator<String>? validator;
  final ValueChanged<res.Resource>? onSelected;
  final bool enabled;

  const ExecutablePathPickerField({
    super.key,
    required this.controller,
    required this.decoration,
    this.validator,
    this.onSelected,
    this.enabled = true,
  });

  @override
  ConsumerState<ExecutablePathPickerField> createState() => _ExecutablePathPickerFieldState();
}

class _ExecutablePathPickerFieldState extends ConsumerState<ExecutablePathPickerField> {
  bool _opening = false;
  late final TextEditingController _displayController;
  res.Resource? _selectedResource;
  late final VoidCallback _externalListener;
  static const int _displayMaxLength = 48;

  bool get _hasValue => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _displayController = TextEditingController(text: widget.controller.text);
    _externalListener = () {
      if (_selectedResource == null) {
        final raw = widget.controller.text;
        final zoneGuess = detectZoneFromPath(raw);
        final display = zoneGuess != null
            ? formatPathWithZone(raw, zoneGuess, maxLength: _displayMaxLength)
            : raw;
        if (_displayController.text != display) {
          _displayController.text = display;
        }
      }
      if (mounted) setState(() {});
    };
    widget.controller.addListener(_externalListener);
  }

  @override
  void didUpdateWidget(covariant ExecutablePathPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_externalListener);
      widget.controller.addListener(_externalListener);
      _externalListener();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalListener);
    _displayController.dispose();
    super.dispose();
  }

  List<ExeZoneOption> _buildVisibleZones() {
    final auth = ref.read(authNotifierProvider);
    final user = auth.user;
    final isTopManager = user?.isTopManager == true;
    final groupId = user?.groupId ?? 0;

    final zones = <ExeZoneOption>[
      const ExeZoneOption(label: '总公司资源', zone: 'HEADQUARTERS', netbarId: 0),
      // 非总部管理员（分部管理员或普通用户）显示分公司资源
      if (!isTopManager && groupId > 0)
        ExeZoneOption(label: '分公司资源', zone: 'BRANCH', netbarId: groupId),
      const ExeZoneOption(label: '共享区资源', zone: 'SHARED', netbarId: null),
    ];
    return zones;
  }

  Future<void> _openPicker() async {
    if (!widget.enabled || _opening) return;
    setState(() => _opening = true);
    try {
      final visibleZones = _buildVisibleZones();
      final selected = await showDialog<res.Resource>(
        context: context,
        builder: (context) => ExePickerDialog(visibleZones: visibleZones),
      );
      if (!mounted || selected == null) return;
      _selectedResource = selected;
      widget.controller.text = selected.path.isNotEmpty ? selected.path : selected.name;
      final zoneForDisplay =
          detectZoneFromPath(widget.controller.text) ?? selected.zone;
      _displayController.text = formatPathWithZone(
        widget.controller.text,
        zoneForDisplay,
        maxLength: _displayMaxLength,
      );
      widget.onSelected?.call(selected);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _clear() {
    widget.controller.clear();
    _displayController.clear();
    _selectedResource = null;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _displayController,
      readOnly: true,
      enabled: widget.enabled,
      validator: widget.validator,
      onTap: _openPicker,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: widget.decoration.copyWith(
        suffixIcon: _hasValue
            ? IconButton(
                onPressed: _clear,
                icon: Icon(LucideIcons.x, size: 16, color: Colors.grey.shade500),
                tooltip: '清除',
              )
            : IconButton(
                onPressed: _openPicker,
                icon: Icon(LucideIcons.chevronDown, size: 16, color: Colors.grey.shade500),
                tooltip: '选择可执行文件',
              ),
      ),
    );
  }
}
