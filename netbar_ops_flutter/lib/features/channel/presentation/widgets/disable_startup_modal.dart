import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../netbar/data/area_api.dart';
import '../../data/startup_item_api.dart';

/// IP范围输入模型
class IpRangeInput {
  String start;
  String end;

  IpRangeInput({this.start = '', this.end = ''});
}

/// 禁用启动项弹窗 - 与 Web DisableStartupModal.vue 1:1 对齐
class DisableStartupModal extends StatefulWidget {
  final String itemName;
  final bool currentlyEnabled;
  final List<NetbarArea> areas;
  final EnabledState? currentState; // 当前禁用状态（如果已禁用）

  const DisableStartupModal({
    super.key,
    required this.itemName,
    required this.currentlyEnabled,
    this.areas = const [],
    this.currentState,
  });

  @override
  State<DisableStartupModal> createState() => _DisableStartupModalState();
}

class _DisableStartupModalState extends State<DisableStartupModal> {
  // 禁用时长：'permanent' 或天数
  bool _isPermanent = true;
  final _daysController = TextEditingController(text: '7');

  // 禁用策略：'global' 或 'specific'
  String _strategy = 'global';

  // 指定区域禁用
  List<String> _disabledAreas = [];

  // 指定IP范围禁用
  List<IpRangeInput> _disabledIpRanges = [];

  @override
  void initState() {
    super.initState();
    // 如果已有禁用状态，初始化表单
    if (widget.currentState != null && !widget.currentState!.status) {
      final state = widget.currentState!;
      // 判断是永久禁用还是临时禁用
      // duration 为 'permanent' 或 null 时是永久禁用，否则是临时禁用（天数）
      if (state.duration != null && state.duration != 'permanent') {
        _isPermanent = false;
        final days = state.durationDays ?? (state.duration is int ? state.duration : int.tryParse(state.duration.toString()));
        if (days != null) {
          _daysController.text = days.toString();
        }
      } else {
        _isPermanent = true;
      }
      _strategy = state.strategy;
      _disabledAreas = List.from(state.disabledAreas ?? []);
      _disabledIpRanges = state.disabledIpRanges
              ?.map((r) => IpRangeInput(start: r.start, end: r.end))
              .toList() ??
          [];
    }
  }

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  void _handleAreaChange(String areaName) {
    setState(() {
      if (_disabledAreas.contains(areaName)) {
        _disabledAreas.remove(areaName);
      } else {
        _disabledAreas.add(areaName);
      }
    });
  }

  void _addIpRange() {
    setState(() {
      _disabledIpRanges.add(IpRangeInput());
    });
  }

  void _removeIpRange(int index) {
    setState(() {
      _disabledIpRanges.removeAt(index);
    });
  }

  EnabledState _buildEnabledState() {
    final days = int.tryParse(_daysController.text) ?? 7;
    return EnabledState(
      status: false,
      duration: _isPermanent ? 'permanent' : days,
      strategy: _strategy,
      disabledAreas: _strategy == 'specific' ? _disabledAreas : null,
      disabledIpRanges: _strategy == 'specific' && _disabledIpRanges.isNotEmpty
          ? _disabledIpRanges
              .where((r) => r.start.isNotEmpty && r.end.isNotEmpty)
              .map((r) => IpRange(start: r.start, end: r.end))
              .toList()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '禁用启动项 · ${widget.itemName}',
      maxWidth: 500,
      bodyPadding: EdgeInsets.zero,
      body: _buildContent(),
      footer: _buildFooter(),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 禁用时长
          _buildSection(
            title: '禁用时长',
            icon: LucideIcons.clock,
            child: Column(
              children: [
                _buildRadioTile(
                  title: '永久禁用',
                  subtitle: '直到手动启用',
                  value: true,
                  groupValue: _isPermanent,
                  onChanged: (v) => setState(() => _isPermanent = v),
                ),
                const SizedBox(height: 8),
                _buildRadioTile(
                  title: '临时禁用',
                  subtitle: '指定天数后自动启用',
                  value: false,
                  groupValue: _isPermanent,
                  onChanged: (v) => setState(() => _isPermanent = v),
                  trailing: !_isPermanent
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 60,
                              child: TextField(
                                controller: _daysController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('天', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                          ],
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 禁用策略
          _buildSection(
            title: '禁用策略',
            icon: LucideIcons.target,
            child: Column(
              children: [
                _buildRadioTile(
                  title: '全局禁用',
                  subtitle: '所有区域和IP都禁用',
                  value: 'global',
                  groupValue: _strategy,
                  onChanged: (v) => setState(() => _strategy = v),
                ),
                const SizedBox(height: 8),
                _buildRadioTile(
                  title: '指定范围禁用',
                  subtitle: '仅在指定区域或IP范围禁用',
                  value: 'specific',
                  groupValue: _strategy,
                  onChanged: (v) => setState(() => _strategy = v),
                ),
              ],
            ),
          ),

          // 指定范围详情（仅当策略为 specific 时显示）
          if (_strategy == 'specific') ...[
            const SizedBox(height: 24),
            _buildSpecificRangeSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecificRangeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 指定区域
          Row(
            children: [
              Icon(LucideIcons.mapPin, size: 14, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text('指定禁用区域', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.areas.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.areas.map((area) {
                final isSelected = _disabledAreas.contains(area.name);
                return GestureDetector(
                  onTap: () => _handleAreaChange(area.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue.shade100 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _handleAreaChange(area.name),
                            activeColor: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(area.name, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Text('当前网吧未配置区域', style: TextStyle(fontSize: 13, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),

          const SizedBox(height: 20),

          // 指定IP范围
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.network, size: 14, color: Colors.blue.shade600),
                  const SizedBox(width: 8),
                  Text('指定禁用IP范围', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                ],
              ),
              TextButton.icon(
                onPressed: _addIpRange,
                icon: const Icon(LucideIcons.plus, size: 12),
                label: const Text('添加', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_disabledIpRanges.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
              ),
              child: Center(
                child: Text('暂无IP范围限制', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              ),
            )
          else
            ...List.generate(_disabledIpRanges.length, (index) => _buildIpRangeItem(index)),
        ],
      ),
    );
  }

  Widget _buildIpRangeItem(int index) {
    final range = _disabledIpRanges[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: TextEditingController(text: range.start),
              onChanged: (v) => range.start = v,
              decoration: InputDecoration(
                hintText: '起始IP',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('—', style: TextStyle(color: Colors.grey.shade400)),
          ),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: range.end),
              onChanged: (v) => range.end = v,
              decoration: InputDecoration(
                hintText: '结束IP',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _removeIpRange(index),
            icon: Icon(LucideIcons.trash2, size: 14, color: Colors.red.shade400),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  Widget _buildRadioTile<T>({
    required String title,
    required String subtitle,
    required T value,
    required T groupValue,
    required ValueChanged<T> onChanged,
    Widget? trailing,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.iosBlue.withValues(alpha: 0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppColors.iosBlue : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? AppColors.iosBlue : Colors.grey.shade400, width: 2),
              ),
              child: isSelected
                  ? Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.iosBlue)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isSelected ? AppColors.iosBlue : Colors.grey.shade800)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
          // 如果当前已禁用，显示"取消禁用"按钮
          if (!widget.currentlyEnabled)
            TextButton.icon(
              onPressed: () {
                // 返回一个启用状态
                Navigator.of(context).pop(EnabledState(status: true, strategy: 'global'));
              },
              icon: Icon(LucideIcons.playCircle, size: 16, color: Colors.green.shade600),
              label: Text('取消禁用', style: TextStyle(fontSize: 14, color: Colors.green.shade600)),
            )
          else
            const SizedBox(),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(_buildEnabledState());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                child: const Text('确认禁用', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
      ],
    );
  }
}

/// 显示禁用启动项弹窗的便捷函数
Future<EnabledState?> showDisableStartupModal(
  BuildContext context, {
  required String itemName,
  required bool currentlyEnabled,
  List<NetbarArea> areas = const [],
  EnabledState? currentState,
}) {
  return showAdaptive<EnabledState>(
    context,
    (context) => DisableStartupModal(
      itemName: itemName,
      currentlyEnabled: currentlyEnabled,
      areas: areas,
      currentState: currentState,
    ),
    routeName: '/dialog/disable-startup',
  );
}
