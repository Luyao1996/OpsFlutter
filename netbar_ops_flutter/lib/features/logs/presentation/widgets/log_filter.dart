import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/log_types.dart';

class LogFilter extends StatefulWidget {
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

  @override
  State<LogFilter> createState() => _LogFilterState();
}

class _LogFilterState extends State<LogFilter> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _submitDebounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.search);
  }

  @override
  void didUpdateWidget(covariant LogFilter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search && _searchController.text != widget.search) {
      _searchController.text = widget.search;
    }
  }

  @override
  void dispose() {
    _submitDebounce?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _submitSearch([String? value]) {
    final text = (value ?? _searchController.text).trim();
    _submitDebounce?.cancel();
    _submitDebounce = Timer(const Duration(milliseconds: 50), () {
      widget.onSearchChanged(text);
    });
  }

  String _formatRange(DateTimeRange range) {
    String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(range.start)} ~ ${fmt(range.end)}';
  }

  Widget _buildDateRangeButton({
    required String label,
    required VoidCallback onPick,
    required VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: onPick,
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
            Icon(LucideIcons.calendar, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(
                    LucideIcons.x,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<DateTimeRange?> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = widget.timeRange ??
        DateTimeRange(
          start: today.subtract(const Duration(days: 6)),
          end: today,
        );

    final theme = Theme.of(context);
	    final datePickerTheme = theme.copyWith(
	      colorScheme: theme.colorScheme.copyWith(
	        primary: AppColors.iosBlue,
	        onPrimary: Colors.white,
	        surface: Colors.white,
	      ),
	      dialogTheme: DialogThemeData(
	        backgroundColor: Colors.white,
	        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
	      ),
	      datePickerTheme: DatePickerThemeData(
	        backgroundColor: Colors.white,
	        surfaceTintColor: Colors.white,
	        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
	        headerBackgroundColor: Colors.white,
	        todayBorder: BorderSide(color: AppColors.iosBlue.withOpacity(0.35)),
	        todayForegroundColor: WidgetStatePropertyAll(AppColors.iosBlue),
	      ),
	    );

    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: today,
      initialDateRange: initial,
      helpText: '选择时间范围',
      cancelText: '取消',
      confirmText: '确认',
      builder: (dialogContext, child) {
        final size = MediaQuery.sizeOf(dialogContext);
        final isNarrow = size.width < 600;
        final themed = Theme(data: datePickerTheme, child: child ?? const SizedBox.shrink());
        if (isNarrow) return themed;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 620),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: themed,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSearchField = SizedBox(
          height: 36,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              focusNode: _searchFocusNode,
              controller: _searchController,
              onTap: () => _searchFocusNode.requestFocus(),
              onChanged: (_) {},
              onSubmitted: _submitSearch,
              textAlignVertical: TextAlignVertical.center,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索日志内容/ID...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: _submitSearch,
                  icon: Icon(
                    LucideIcons.search,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  tooltip: '搜索',
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
        );
        final searchField =
            isPhone ? baseSearchField : SizedBox(width: 260, child: baseSearchField);

        final moduleDropdown = _buildDropdown<LogModule>(
          '所有模块',
          widget.moduleFilter,
          LogModule.values,
          (m) => moduleLabels[m]!,
          widget.onModuleFilterChanged,
          expand: isPhone,
        );
        final levelDropdown = _buildDropdown<LogLevel>(
          '所有状态',
          widget.levelFilter,
          LogLevel.values,
          (l) => (levelConfig[l]!['label'] as String),
          widget.onLevelFilterChanged,
          expand: isPhone,
        );

        final dateButton = _buildDateRangeButton(
          label: widget.timeRange == null ? '时间范围' : _formatRange(widget.timeRange!),
          onPick: () async {
            final picked = await _pickDateRange(context);
            if (picked != null) widget.onTimeRangeChanged(picked);
          },
          onClear: widget.timeRange == null ? null : () => widget.onTimeRangeChanged(null),
        );

        final exportLabel = (constraints.maxWidth < 360) ? '导出' : '导出报表';
        final refreshButton = IconButton(
          onPressed: widget.onRefresh,
          icon: Icon(LucideIcons.refreshCw, size: 18, color: Colors.grey.shade500),
          tooltip: '刷新',
          constraints: const BoxConstraints.tightFor(width: 40, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        );
        final exportButton = _buildButton(exportLabel, LucideIcons.download, () {}, isPrimary: false);

        if (isPhone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: filters
              Row(
                children: [
                  Expanded(child: moduleDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: levelDropdown),
                  const SizedBox(width: 12),
                  Expanded(child: dateButton),
                ],
              ),
              const SizedBox(height: 8),
              // Row 2: search + actions
              Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 12),
                  refreshButton,
                  const SizedBox(width: 8),
                  exportButton,
                ],
              ),
            ],
          );
        }

        final desktopModuleDropdown = SizedBox(
          width: 140,
          child: _buildDropdown<LogModule>(
            '所有模块',
            widget.moduleFilter,
            LogModule.values,
            (m) => moduleLabels[m]!,
            widget.onModuleFilterChanged,
            width: 140,
            expand: false,
          ),
        );
        final desktopLevelDropdown = SizedBox(
          width: 140,
          child: _buildDropdown<LogLevel>(
            '所有状态',
            widget.levelFilter,
            LogLevel.values,
            (l) => (levelConfig[l]!['label'] as String),
            widget.onLevelFilterChanged,
            width: 140,
            expand: false,
          ),
        );
        final desktopDateButton = SizedBox(width: 180, child: dateButton);

        final filters = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            searchField,
            desktopModuleDropdown,
            desktopLevelDropdown,
            desktopDateButton,
          ],
        );

        final actions = Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            refreshButton,
            exportButton,
          ],
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(child: filters),
              actions,
            ],
          ),
        );
      },
    );
  }

  Widget _buildDropdown<T>(
    String defaultLabel,
    T? value,
    List<T> items,
    String Function(T) labelBuilder,
    ValueChanged<T?> onChanged,
    {double? width, bool expand = false}
  ) {
    return Container(
      width: width,
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
          isExpanded: expand,
          isDense: expand,
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
