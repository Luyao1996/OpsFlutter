import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../data/operation_log_api.dart';
import '../data/operation_log_models.dart';

/// 业务操作审计日志视图 —— 对齐 toolboxPage `views/LogPage.vue`。
///
/// - PC 端：筛选条 + 表格 + 分页器
/// - 移动端：筛选条 + 卡片列表 + 无限滚动
/// - 默认查询当天 00:00:00 ~ 23:59:59
/// - 日志类型下拉项动态来自后端 `eventMap`
class OperationLogView extends StatefulWidget {
  const OperationLogView({super.key});

  @override
  State<OperationLogView> createState() => _OperationLogViewState();
}

class _OperationLogViewState extends State<OperationLogView> {
  final OperationLogApi _api = OperationLogApi();
  final ScrollController _mobileScrollCtrl = ScrollController();
  final TextEditingController _keywordCtrl = TextEditingController();
  final TextEditingController _operatorCtrl = TextEditingController();

  DateTime _startDate = _todayStart();
  DateTime _endDate = _todayEnd();
  String? _logType;
  bool _filterExpanded = false; // 手机端详细筛选区是否展开

  List<OperationLog> _items = [];
  Map<String, String> _eventMap = const {};
  int _total = 0;
  int _page = 1;
  final int _size = 20;
  bool _loading = false;
  String? _error;

  static DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 0, 0, 0);
  }

  static DateTime _todayEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  void initState() {
    super.initState();
    _mobileScrollCtrl.addListener(_onMobileScroll);
    _fetch();
  }

  @override
  void dispose() {
    _mobileScrollCtrl.removeListener(_onMobileScroll);
    _mobileScrollCtrl.dispose();
    _keywordCtrl.dispose();
    _operatorCtrl.dispose();
    super.dispose();
  }

  bool get _noMore => _total > 0 && _items.length >= _total;

  void _onMobileScroll() {
    if (_loading || _noMore) return;
    if (_mobileScrollCtrl.position.pixels >=
        _mobileScrollCtrl.position.maxScrollExtent - 80) {
      _page += 1;
      _fetch(append: true);
    }
  }

  Future<void> _fetch({bool append = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getLogs(
        event: _logType,
        startTime: _startDate,
        endTime: _endDate,
        keyword: _keywordCtrl.text.trim(),
        user: _operatorCtrl.text.trim(),
        page: _page,
        size: _size,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _items.addAll(res.items);
        } else {
          _items = res.items;
        }
        _total = res.total;
        if (res.eventMap.isNotEmpty) _eventMap = res.eventMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _handleSearch() {
    if (_page != 1) {
      _page = 1;
    }
    _fetch();
  }

  void _resetForm() {
    setState(() {
      _startDate = _todayStart();
      _endDate = _todayEnd();
      _keywordCtrl.clear();
      _operatorCtrl.clear();
      _logType = null;
      _page = 1;
    });
    _fetch();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    final merged = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? (isStart ? 0 : 23),
      time?.minute ?? (isStart ? 0 : 59),
      isStart ? 0 : 59,
    );
    setState(() {
      if (isStart) {
        _startDate = merged;
      } else {
        _endDate = merged;
      }
    });
    _handleSearch();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    if (isPhone) {
      // 手机端：toolbar 与列表共用同一个可滚动视图，键盘弹起时整体可滚动，
      // 不再出现"toolbar 高度 + Expanded(list) 超过可用高度"的 overflow。
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: _buildMobileScrollable(),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(false),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              clipBehavior: Clip.hardEdge,
              child: _buildDesktopBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBody() {
    if (_error != null && _items.isEmpty) return _buildError();
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) return _buildEmptyState();
    return Column(
      children: [
        _buildTableHeader(),
        Divider(height: 1, color: Colors.grey.shade200),
        Expanded(child: _buildTableBody()),
        Divider(height: 1, color: Colors.grey.shade200),
        _buildPagination(),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.inbox, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            '暂无数据',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.shieldOff, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade500,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _error ?? '未知错误',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _handleSearch,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Toolbar =====
  Widget _buildToolbar(bool isPhone) {
    return Container(
      padding: EdgeInsets.all(isPhone ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: isPhone ? _buildMobileToolbar() : _buildDesktopToolbar(),
    );
  }

  Widget _buildDesktopToolbar() {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _datePickerBox(
          label: '开始时间',
          text: dateFmt.format(_startDate),
          onTap: () => _pickDate(isStart: true),
          width: 200,
        ),
        _datePickerBox(
          label: '结束时间',
          text: dateFmt.format(_endDate),
          onTap: () => _pickDate(isStart: false),
          width: 200,
        ),
        SizedBox(
          width: 220,
          child: _input(
            controller: _keywordCtrl,
            hint: '文件名/网吧名/关键词',
            icon: LucideIcons.search,
            onSubmitted: (_) => _handleSearch(),
          ),
        ),
        SizedBox(
          width: 140,
          child: _input(
            controller: _operatorCtrl,
            hint: '操作人',
            icon: LucideIcons.user,
            onSubmitted: (_) => _handleSearch(),
          ),
        ),
        SizedBox(width: 160, child: _logTypeSelector()),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _primaryButton(label: '搜索', icon: LucideIcons.search, onTap: _handleSearch),
            const SizedBox(width: 8),
            _outlineButton(label: '重置', icon: LucideIcons.rotateCcw, onTap: _resetForm),
          ],
        ),
      ],
    );
  }

  /// 手机端工具栏：搜索头（始终可见） + AnimatedSize 折叠的详细筛选区。
  /// 交互对齐 toolboxPage `LogPage.vue` 的 mobile-search-header。
  Widget _buildMobileToolbar() {
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // —— 搜索头：关键词 + 搜索 + 漏斗（toggle） ——
        Row(
          children: [
            Expanded(
              child: _input(
                controller: _keywordCtrl,
                hint: '搜索关键词...',
                icon: LucideIcons.search,
                onSubmitted: (_) => _handleSearch(),
              ),
            ),
            const SizedBox(width: 8),
            _primaryButton(
              label: '搜索',
              icon: LucideIcons.search,
              onTap: _handleSearch,
              compact: true,
            ),
            const SizedBox(width: 8),
            _filterToggleButton(),
          ],
        ),
        // —— 详细筛选区（默认折叠） ——
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _filterExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _datePickerBox(
                        label: '开始时间',
                        text: dateFmt.format(_startDate),
                        onTap: () => _pickDate(isStart: true),
                      ),
                      const SizedBox(height: 8),
                      _datePickerBox(
                        label: '结束时间',
                        text: dateFmt.format(_endDate),
                        onTap: () => _pickDate(isStart: false),
                      ),
                      const SizedBox(height: 8),
                      _input(
                        controller: _operatorCtrl,
                        hint: '操作人',
                        icon: LucideIcons.user,
                        onSubmitted: (_) => _handleSearch(),
                      ),
                      const SizedBox(height: 8),
                      _logTypeSelector(),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: _outlineButton(
                          label: '重置筛选',
                          icon: LucideIcons.rotateCcw,
                          onTap: _resetForm,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _filterToggleButton() {
    final on = _filterExpanded;
    return InkWell(
      onTap: () => setState(() => _filterExpanded = !_filterExpanded),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on
              ? AppColors.iosBlue.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
            color: on ? AppColors.iosBlue : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          LucideIcons.slidersHorizontal,
          size: 16,
          color: on ? AppColors.iosBlue : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        side: BorderSide(color: Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _datePickerBox({
    required String label,
    required String text,
    required VoidCallback onTap,
    double? width,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.calendar,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        prefixIcon: Icon(icon, size: 14, color: Colors.grey.shade500),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 1.4),
        ),
      ),
    );
  }

  Widget _logTypeSelector() {
    final entries = _eventMap.entries.toList();
    return DropdownButtonFormField<String?>(
      initialValue: _logType,
      isDense: true,
      isExpanded: true,
      style: const TextStyle(fontSize: 13, color: Colors.black87),
      decoration: InputDecoration(
        isDense: true,
        hintText: '日志类型',
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 1.4),
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('全部类型')),
        ...entries.map(
          (e) => DropdownMenuItem<String?>(
            value: e.key,
            child: Text(
              e.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: (v) {
        setState(() => _logType = v);
        _handleSearch();
      },
    );
  }

  // ===== PC Table =====
  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFF9FAFB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: const [
          SizedBox(width: 170, child: _HeaderCell('时间')),
          SizedBox(width: 200, child: _HeaderCell('事件', center: true)),
          SizedBox(width: 140, child: _HeaderCell('操作人', center: true)),
          Expanded(child: _HeaderCell('描述')),
          SizedBox(width: 160, child: _HeaderCell('IP地址', center: true)),
        ],
      ),
    );
  }

  Widget _buildTableBody() {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: Colors.grey.shade100),
      itemBuilder: (context, index) {
        final item = _items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 170,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.clock,
                      size: 13,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.time,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 200,
                child: Center(child: _EventTag(text: item.action)),
              ),
              SizedBox(
                width: 140,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.user,
                      size: 13,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        item.operator,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Tooltip(
                  message: item.description,
                  child: Text(
                    item.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: Center(
                  child: Text(
                    item.ip,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPagination() {
    final totalPages = (_total / _size).ceil().clamp(1, 99999);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Text(
            '共 $_total 条记录',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Spacer(),
          Text(
            '第 $_page / $totalPages 页',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          IconButton(
            onPressed: _page > 1
                ? () {
                    setState(() => _page -= 1);
                    _fetch();
                  }
                : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            tooltip: '上一页',
          ),
          IconButton(
            onPressed: _page < totalPages
                ? () {
                    setState(() => _page += 1);
                    _fetch();
                  }
                : null,
            icon: const Icon(LucideIcons.chevronRight, size: 16),
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }

  // ===== Mobile Scrollable =====
  /// 手机端整体可滚动列表：toolbar 作为 index 0 跟随滚动，
  /// 后续是错误/loading/空 / 卡片 / 加载更多 尾部。
  /// 键盘弹起时整个区域可滚动，不会出现 Column overflow。
  Widget _buildMobileScrollable() {
    final hasItems = _items.isNotEmpty;
    final hasError = _error != null && _items.isEmpty;
    final isLoadingFirst = _loading && _items.isEmpty;
    final isEmpty = !hasError && !isLoadingFirst && !hasItems;
    final hasTail = hasItems && (_loading || _noMore);

    final contentCount = hasItems
        ? _items.length + (hasTail ? 1 : 0)
        : 1; // 错误/loading/空 单一占位
    final totalCount = 1 + contentCount; // +1 for toolbar

    return ListView.builder(
      controller: _mobileScrollCtrl,
      // 底部留空，避免最后一项贴底；keyboardDismissBehavior 让滚动时收起键盘。
      padding: const EdgeInsets.only(bottom: 16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildToolbar(true),
          );
        }
        final i = index - 1;
        if (!hasItems) {
          if (hasError) {
            return SizedBox(height: 280, child: _buildError());
          }
          if (isLoadingFirst) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (isEmpty) {
            return SizedBox(height: 200, child: _buildEmptyState());
          }
          return const SizedBox.shrink();
        }
        // 有数据：卡片 / 尾部
        if (i < _items.length) {
          return _buildMobileCard(_items[i]);
        }
        if (_loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (_noMore) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '没有更多了',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMobileCard(OperationLog item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.clock, size: 13, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                item.time,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Spacer(),
              _EventTag(text: item.action),
            ],
          ),
          const SizedBox(height: 10),
          _kvRow('操作人', item.operator, icon: LucideIcons.user),
          const SizedBox(height: 6),
          _kvRow('IP', item.ip, mono: true),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              border: Border.all(color: Colors.grey.shade100),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              item.description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(
    String label,
    String value, {
    IconData? icon,
    bool mono = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 50,
          child: Text(
            '$label:',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        if (icon != null) ...[
          Icon(icon, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade800,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final bool center;
  const _HeaderCell(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    );
  }
}

class _EventTag extends StatelessWidget {
  final String text;
  const _EventTag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.iosBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.iosBlue.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.iosBlue,
        ),
      ),
    );
  }
}
