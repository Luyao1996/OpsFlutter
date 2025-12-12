import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/log_types.dart';

class LogFilter extends StatelessWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;
  final LogModule? moduleFilter;
  final ValueChanged<LogModule?> onModuleFilterChanged;
  final LogLevel? levelFilter;
  final ValueChanged<LogLevel?> onLevelFilterChanged;
  final DateTimeRange? timeRange;
  final ValueChanged<DateTimeRange?> onTimeRangeChanged;
  final VoidCallback onRefresh;

  const LogFilter({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.moduleFilter,
    required this.onModuleFilterChanged,
    required this.levelFilter,
    required this.onLevelFilterChanged,
    required this.timeRange,
    required this.onTimeRangeChanged,
    required this.onRefresh,
  });

  String _formatRange(DateTimeRange range) {
    String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(range.start)} ~ ${fmt(range.end)}';
  }

  Future<DateTimeRange?> _showInlineRangePicker(BuildContext context, DateTimeRange? current, DateTime now) async {
    DateTime tempStart = current?.start ?? DateTime(now.year, now.month, now.day);
    DateTime tempEnd = current?.end ?? now;

    return showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('选择时间范围', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                CalendarDatePicker(
                  initialDate: tempStart,
                  firstDate: DateTime(now.year - 5),
                  lastDate: now,
                  onDateChanged: (d) {
                    tempStart = d;
                    if (tempEnd.isBefore(tempStart)) tempEnd = tempStart;
                  },
                ),
                const Divider(),
                CalendarDatePicker(
                  initialDate: tempEnd,
                  firstDate: tempStart,
                  lastDate: now,
                  onDateChanged: (d) {
                    tempEnd = d;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, DateTimeRange(start: tempStart, end: tempEnd)),
                      child: const Text('确认'),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          // Left Group
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Search
                Container(
                  width: 260,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    onChanged: (v) {},
                    onSubmitted: onSearchChanged,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '搜索日志内容/ID...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(bottom: 10),
                    ),
                  ),
                ),
                // Module Dropdown
                _buildDropdown<LogModule>(
                  '所有模块',
                  moduleFilter,
                  LogModule.values,
                  (m) => moduleLabels[m]!,
                  onModuleFilterChanged,
                ),
                // Level Dropdown
                _buildDropdown<LogLevel>(
                  '所有状态',
                  levelFilter,
                  LogLevel.values,
                  (l) => (levelConfig[l]!['label'] as String),
                  onLevelFilterChanged,
                ),
                // Date Button
                _buildButton(
                  timeRange == null ? '时间范围' : _formatRange(timeRange!),
                  LucideIcons.calendar,
                  () async {
                    final now = DateTime.now();
                    final picked = await _showInlineRangePicker(context, timeRange, now);
                    if (picked != null) onTimeRangeChanged(picked);
                  },
                ),
              ],
            ),
          ),
          // Right Group
          Row(
            children: [
              IconButton(
                onPressed: onRefresh,
                icon: Icon(LucideIcons.refreshCw, size: 18, color: Colors.grey.shade500),
                tooltip: '刷新',
              ),
              const SizedBox(width: 8),
              _buildButton('导出报表', LucideIcons.download, () {}, isPrimary: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>(
    String defaultLabel,
    T? value,
    List<T> items,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(defaultLabel, style: const TextStyle(fontSize: 13)),
          icon: Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade400),
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          onChanged: onChanged,
          items: [
            DropdownMenuItem<T>(
              value: null,
              child: Text(defaultLabel),
            ),
            ...items.map((item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelBuilder(item)),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label, IconData icon, VoidCallback onPressed, {bool isPrimary = false}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
