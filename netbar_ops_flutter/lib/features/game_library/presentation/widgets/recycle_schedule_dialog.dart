import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/game_constants.dart';

/// 「执行时间」弹窗：weekdays + HH:mm
///
/// 与 Web 端 `planScheduleVisible` 子弹窗对齐：草稿模式，取消不污染主 state。
class RecycleScheduleDialog extends StatefulWidget {
  final List<int> initialWeekdays;
  final String initialTime; // 'HH:mm'

  const RecycleScheduleDialog({
    super.key,
    required this.initialWeekdays,
    required this.initialTime,
  });

  /// 用户点确定返回 `(weekdays, time)`；取消返回 null。
  static Future<({List<int> weekdays, String time})?> show(
    BuildContext context, {
    required List<int> weekdays,
    required String time,
  }) {
    return showDialog<({List<int> weekdays, String time})>(
      context: context,
      builder: (_) => RecycleScheduleDialog(
        initialWeekdays: weekdays,
        initialTime: time,
      ),
    );
  }

  @override
  State<RecycleScheduleDialog> createState() => _RecycleScheduleDialogState();
}

class _RecycleScheduleDialogState extends State<RecycleScheduleDialog> {
  late Set<int> _weekdays;
  late String _time; // HH:mm

  @override
  void initState() {
    super.initState();
    _weekdays = Set<int>.from(widget.initialWeekdays);
    _time = _normalizeTime(widget.initialTime);
  }

  String _normalizeTime(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(t);
    if (m == null) return RecycleDefaults.time;
    final h = int.parse(m.group(1)!).clamp(0, 23);
    final mm = int.parse(m.group(2)!).clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final init = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 6,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final r = await showTimePicker(
      context: context,
      initialTime: init,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (r == null) return;
    setState(() {
      _time =
          '${r.hour.toString().padLeft(2, '0')}:${r.minute.toString().padLeft(2, '0')}';
    });
  }

  void _onConfirm() {
    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择一天',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          backgroundColor: Color(0xFFB45309),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 输出按 Go time.Weekday（Sun=0..Sat=6）排序，保持后端语义一致
    final weekdays = _weekdays.toList()..sort();
    Navigator.of(context).pop((weekdays: weekdays, time: _time));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('执行时间', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('每周执行日',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final opt in kWeekdayOptions)
                  _weekdayChip(opt),
              ],
            ),
            const SizedBox(height: 14),
            const Text('执行时间',
                style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.access_time,
                        size: 14, color: Color(0xFF6B7280)),
                    const SizedBox(width: 6),
                    Text(_time,
                        style: const TextStyle(
                            fontSize: 13, color: Colors.black87)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.iosBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: _onConfirm,
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _weekdayChip(WeekdayOption opt) {
    final active = _weekdays.contains(opt.value);
    return InkWell(
      onTap: () {
        setState(() {
          if (!_weekdays.remove(opt.value)) _weekdays.add(opt.value);
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.iosBlue : Colors.white,
          border: Border.all(
            color: active ? AppColors.iosBlue : const Color(0xFFD1D5DB),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          opt.label,
          style: TextStyle(
            fontSize: 12,
            color: active ? Colors.white : const Color(0xFF374151),
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
