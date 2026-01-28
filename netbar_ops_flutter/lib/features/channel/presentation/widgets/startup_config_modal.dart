import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/startup_item_api.dart';

/// 启动项配置弹窗 - 适配 tactic 接口，包含启动项、区域、本地化编辑
class StartupConfigModal extends StatefulWidget {
  final TacticItem item;
  final bool isAdmin;
  final VoidCallback onSuccess;
  final bool fullscreenSheet;

  const StartupConfigModal({
    super.key,
    required this.item,
    this.isAdmin = false,
    required this.onSuccess,
    this.fullscreenSheet = false,
    List<dynamic> areas = const [],
  });

  @override
  State<StartupConfigModal> createState() => _StartupConfigModalState();
}

class _StartupConfigModalState extends State<StartupConfigModal>
    with SingleTickerProviderStateMixin {
  final StartupItemApi _api = StartupItemApi();
  final _formKey = GlobalKey<FormState>();

  // --- 启动项字段 ---
  late TextEditingController _parameterController;
  late TextEditingController _delayController;
  late bool _isRandomName;
  late bool _isForcedOn;
  late String _strategyMode;
  late TextEditingController _strategyNameController;
  late List<_PeriodInput> _periods;

  // --- 区域字段 ---
  late TextEditingController _areaInputController;
  late List<_AreaEntry> _areaList;

  // --- 本地化字段 ---
  late List<_LocaleFileEntry> _localeFiles;
  int _activeLocaleIndex = 0;

  // --- Tab ---
  late TabController _tabController;

  bool _saving = false;
  String? _error;

  bool get _canEditForceSwitch {
    final creatorGroupId = widget.item.creatorGroupId;
    if (creatorGroupId == null || creatorGroupId == 0) return true;
    return widget.isAdmin;
  }

  @override
  void initState() {
    super.initState();
    final startup = widget.item.startup;

    _parameterController = TextEditingController(
      text: startup?.parameter ?? '',
    );
    _delayController = TextEditingController(
      text: (startup?.startupDelay ?? 0).toString(),
    );
    _isRandomName = startup?.isRandomName ?? false;
    _isForcedOn = startup?.isForcedOn ?? false;
    _strategyMode = startup?.strategy.mode ?? '0';
    _strategyNameController = TextEditingController(
      text: startup?.strategy.name ?? '',
    );

    // 生效时段
    if (startup != null && startup.period.isNotEmpty) {
      _periods = startup.period
          .map((p) =>
              _PeriodInput(start: _parseTime(p.start), end: _parseTime(p.end)))
          .toList();
    } else {
      _periods = [_PeriodInput()];
    }

    // 区域
    _areaInputController = TextEditingController();
    _areaList = widget.item.area
        .where((a) => a.trim().isNotEmpty)
        .map((a) => _AreaEntry(range: a, enabled: true))
        .toList();

    // 本地化文件
    if (widget.item.locales.isNotEmpty) {
      _localeFiles = widget.item.locales
          .map((l) => _LocaleFileEntry(
                id: l.id,
                groupFileId: l.groupFileId,
                pathController: TextEditingController(text: l.path),
                contentController:
                    TextEditingController(text: l.content ?? ''),
              ))
          .toList();
    } else {
      _localeFiles = [_LocaleFileEntry(
        pathController: TextEditingController(),
        contentController: TextEditingController(),
      )];
    }

    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _parameterController.dispose();
    _delayController.dispose();
    _strategyNameController.dispose();
    _areaInputController.dispose();
    for (final f in _localeFiles) {
      f.pathController.dispose();
      f.contentController.dispose();
    }
    _tabController.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? t) {
    if (t == null || t.isEmpty) return null;
    final parts = t.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _buildTimeStr(TimeOfDay? t) {
    if (t == null) return '';
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm:00';
  }

  // --- 时段操作 ---
  void _addPeriod() => setState(() => _periods.add(_PeriodInput()));

  void _removePeriod(int index) => setState(() => _periods.removeAt(index));

  Future<void> _pickTime(bool isStart, int index) async {
    final period = _periods[index];
    final initial = isStart
        ? (period.start ?? const TimeOfDay(hour: 0, minute: 0))
        : (period.end ?? const TimeOfDay(hour: 23, minute: 59));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          period.start = picked;
        } else {
          period.end = picked;
        }
      });
    }
  }

  // --- 区域操作 ---
  void _addArea() {
    final input = _areaInputController.text.trim();
    if (input.isEmpty) return;
    setState(() {
      _areaList.add(_AreaEntry(range: input, enabled: true));
      _areaInputController.clear();
    });
  }

  void _removeArea(int index) => setState(() => _areaList.removeAt(index));

  // --- 本地化文件操作 ---
  void _addLocaleTab() {
    setState(() {
      _localeFiles.add(_LocaleFileEntry(
        pathController: TextEditingController(),
        contentController: TextEditingController(),
      ));
      _activeLocaleIndex = _localeFiles.length - 1;
    });
  }

  void _removeLocaleTab(int index) {
    setState(() {
      _localeFiles[index].pathController.dispose();
      _localeFiles[index].contentController.dispose();
      _localeFiles.removeAt(index);
      if (_activeLocaleIndex >= _localeFiles.length) {
        _activeLocaleIndex =
            _localeFiles.isEmpty ? 0 : _localeFiles.length - 1;
      }
    });
  }

  // --- 保存 ---
  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final periods = _periods
          .where((p) => p.start != null && p.end != null)
          .map((p) => StartupPeriod(
                start: _buildTimeStr(p.start),
                end: _buildTimeStr(p.end),
              ))
          .toList();

      // 构建 locales
      final locales = _localeFiles
          .where((f) =>
              f.pathController.text.isNotEmpty ||
              f.contentController.text.isNotEmpty)
          .map((f) => LocaleItem(
                id: f.id,
                groupFileId: f.groupFileId,
                path: f.pathController.text,
                content: f.contentController.text,
              ))
          .toList();

      // 构建 area
      final area =
          _areaList.where((a) => a.enabled).map((a) => a.range).toList();

      await _api.updateTactic(
        widget.item.id,
        startupId: widget.item.startup?.id,
        path: widget.item.startup?.startupPath,
        groupFileId: widget.item.startup?.groupFileId,
        parameter: _parameterController.text,
        delay: int.tryParse(_delayController.text) ?? 0,
        isRandomName: _isRandomName,
        isForcedOn: _isForcedOn,
        strategy: StartupStrategy(
          mode: _strategyMode,
          name: _strategyNameController.text,
        ),
        period: periods,
        locales: locales,
        area: area,
      );
      widget.onSuccess();
      if (mounted) {
        showTopNotice(context, '保存成功', level: NoticeLevel.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
      }
      setState(() => _error = '保存失败: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  // --- 删除 ---
  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content:
            Text('确定要删除策略 "${widget.item.effectiveDisplayName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.delete(widget.item.id);
      widget.onSuccess();
      if (mounted) {
        showTopNotice(
          context,
          '已删除: ${widget.item.effectiveDisplayName}',
          level: NoticeLevel.success,
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSheet = widget.fullscreenSheet;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.92;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(isSheet: isSheet),
        // Tab 栏
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.iosBlue,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: AppColors.iosBlue,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(text: '启动项'),
              Tab(text: '区域配置'),
              Tab(text: '本地化'),
            ],
          ),
        ),
        Flexible(
          child: Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabController,
              children: [
                SingleChildScrollView(
                    child: _buildStartupForm(isSheet: isSheet)),
                SingleChildScrollView(
                    child: _buildAreaForm(isSheet: isSheet)),
                _buildLocaleForm(isSheet: isSheet),
              ],
            ),
          ),
        ),
        _buildFooter(isSheet: isSheet),
      ],
    );

    if (isSheet) {
      return SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: Container(
            height: sheetHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              boxShadow: AppShadows.xl,
            ),
            child: content,
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.xl,
        ),
        child: content,
      ),
    );
  }

  // ==================== Header ====================
  Widget _buildHeader({required bool isSheet}) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, isSheet ? 12 : 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.iosBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              LucideIcons.settings,
              size: 20,
              color: AppColors.iosBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '编辑策略配置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.item.path.isNotEmpty
                      ? widget.item.path
                      : widget.item.name,
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon:
                Icon(LucideIcons.x, size: 20, color: Colors.grey.shade400),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  // ==================== 启动项 Tab ====================
  Widget _buildStartupForm({required bool isSheet}) {
    return Padding(
      padding: EdgeInsets.all(isSheet ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 执行文件（只读）
          _buildFormItem(
            label: '执行文件',
            child: TextFormField(
              initialValue: widget.item.startup?.startupPath ?? '',
              enabled: false,
              decoration: _inputDecoration('无'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 16),

          // 执行参数
          _buildFormItem(
            label: '执行参数',
            child: TextFormField(
              controller: _parameterController,
              decoration: _inputDecoration(''),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),

          // 延时启动
          _buildFormItem(
            label: '延时启动',
            child: SizedBox(
              width: 180,
              child: TextFormField(
                controller: _delayController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration('0').copyWith(
                  suffixText: '秒',
                  suffixStyle:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 随机进程名
          _buildFormItem(
            label: '随机进程名',
            child: Row(
              children: [
                Switch(
                  value: _isRandomName,
                  onChanged: (v) => setState(() => _isRandomName = v),
                  activeColor: AppColors.iosBlue,
                ),
                const SizedBox(width: 4),
                Text(
                  _isRandomName ? '是' : '否',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 生效时段
          _buildPeriodSection(),
          const SizedBox(height: 16),

          // 执行策略
          _buildStrategySection(),
          const SizedBox(height: 16),

          // 强制开启
          _buildFormItem(
            label: '强制开启',
            child: Switch(
              value: _isForcedOn,
              onChanged: _canEditForceSwitch
                  ? (v) => setState(() => _isForcedOn = v)
                  : null,
              activeColor: AppColors.iosBlue,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            _buildErrorBanner(),
          ],
        ],
      ),
    );
  }

  // ==================== 区域配置 Tab ====================
  Widget _buildAreaForm({required bool isSheet}) {
    return Padding(
      padding: EdgeInsets.all(isSheet ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '生效区域',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '留空代表全场生效。支持范围格式如 001-009,020',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),

          // 输入行
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _areaInputController,
                  decoration: _inputDecoration('区域机号: 001-009,020'),
                  style: const TextStyle(fontSize: 13),
                  onFieldSubmitted: (_) => _addArea(),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _addArea,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child:
                    const Text('添加', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 区域列表
          if (_areaList.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Center(
                child: Text(
                  '未添加区域，将全场生效',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey.shade500),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _areaList.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  final area = _areaList[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: area.enabled,
                            onChanged: (v) => setState(
                                () => area.enabled = v ?? true),
                            activeColor: AppColors.iosBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            area.range,
                            style: TextStyle(
                              fontSize: 13,
                              color: area.enabled
                                  ? Colors.grey.shade800
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _removeArea(index),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(LucideIcons.x,
                                size: 16, color: Colors.red.shade400),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 本地化 Tab ====================
  Widget _buildLocaleForm({required bool isSheet}) {
    return Column(
      children: [
        // 文件标签栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border:
                Border(bottom: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(_localeFiles.length, (i) {
                        final isActive = i == _activeLocaleIndex;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _activeLocaleIndex = i),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AppColors.iosBlue
                                        .withValues(alpha: 0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isActive
                                      ? AppColors.iosBlue
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '文件${i + 1}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isActive
                                          ? AppColors.iosBlue
                                          : Colors.grey.shade600,
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  if (_localeFiles.length > 1) ...[
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => _removeLocaleTab(i),
                                      child: Icon(
                                        LucideIcons.x,
                                        size: 12,
                                        color: isActive
                                            ? AppColors.iosBlue
                                            : Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _addLocaleTab,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(LucideIcons.plus,
                      size: 14, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),

        // 当前文件编辑
        if (_localeFiles.isNotEmpty &&
            _activeLocaleIndex < _localeFiles.length)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(isSheet ? 16 : 24),
              child: _buildLocaleEditor(_localeFiles[_activeLocaleIndex]),
            ),
          ),
      ],
    );
  }

  Widget _buildLocaleEditor(_LocaleFileEntry file) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件路径
        _buildFormItem(
          label: '文件路径',
          child: TextFormField(
            controller: file.pathController,
            decoration: _inputDecoration('../开机文件/config.ini'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),

        // 文件内容
        Text(
          '文件内容',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextFormField(
              controller: file.contentController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: '输入文件内容...',
                hintStyle:
                    TextStyle(fontSize: 13, color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== 公共组件 ====================
  Widget _buildFormItem({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildPeriodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '生效时段',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  ...List.generate(
                      _periods.length, (i) => _buildPeriodRow(i)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _addPeriod,
                      icon: const Icon(LucideIcons.plus, size: 14),
                      label: const Text('新增时段',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.iosBlue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPeriodRow(int index) {
    final period = _periods[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildTimeButton(
              time: period.start,
              placeholder: '开始',
              onTap: () => _pickTime(true, index),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child:
                Text('—', style: TextStyle(color: Colors.grey.shade400)),
          ),
          Expanded(
            child: _buildTimeButton(
              time: period.end,
              placeholder: '结束',
              onTap: () => _pickTime(false, index),
            ),
          ),
          if (_periods.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () => _removePeriod(index),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child:
                    const Text('删除', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeButton({
    TimeOfDay? time,
    required String placeholder,
    required VoidCallback onTap,
  }) {
    final text = time != null
        ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00'
        : placeholder;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: time != null
                    ? Colors.grey.shade800
                    : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrategySection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '执行策略',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _strategyMode,
                      isExpanded: true,
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade800),
                      items: const [
                        DropdownMenuItem(
                          value: '0',
                          child: Text('不限制',
                              style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: '1',
                          child: Text('进程存在时启动',
                              style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: '2',
                          child: Text('进程不存在时启动',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _strategyMode = v ?? '0'),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextFormField(
                  controller: _strategyNameController,
                  decoration: _inputDecoration('策略名称/进程名'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.alertCircle,
            size: 16,
            color: Colors.red.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  // ==================== Footer ====================
  Widget _buildFooter({required bool isSheet}) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, isSheet ? 24 : 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        borderRadius: isSheet
            ? BorderRadius.zero
            : const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _handleDelete,
            icon: Icon(
              LucideIcons.trash2,
              size: 16,
              color: Colors.red.shade600,
            ),
            label:
                Text('删除', style: TextStyle(color: Colors.red.shade600)),
          ),
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '取消',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saving ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    '保存',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 时段输入辅助类
class _PeriodInput {
  TimeOfDay? start;
  TimeOfDay? end;

  _PeriodInput({this.start, this.end});
}

/// 区域条目辅助类
class _AreaEntry {
  final String range;
  bool enabled;

  _AreaEntry({required this.range, this.enabled = true});
}

/// 本地化文件条目辅助类
class _LocaleFileEntry {
  final int? id;
  final int? groupFileId;
  final TextEditingController pathController;
  final TextEditingController contentController;

  _LocaleFileEntry({
    this.id,
    this.groupFileId,
    required this.pathController,
    required this.contentController,
  });
}
