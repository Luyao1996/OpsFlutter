import 'dart:convert';
import 'dart:typed_data';
import 'package:charset/charset.dart' as charset;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/strategy_api.dart';
import '../../../channel/data/resource_api.dart' as res;
import 'exe_picker_dialog.dart';
import 'strategy_exe_picker.dart';
import 'strategy_merchants_panel.dart';

/// 后台解码函数（必须是顶级函数才能在 compute 中使用）
String _decodeInBackground(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final encoding = params['encoding'] as String;

  try {
    switch (encoding) {
      case 'utf-8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'latin1':
        return latin1.decode(bytes);
      case 'ascii':
        return ascii.decode(bytes);
      case 'gbk':
        return charset.gbk.decode(bytes);
      case 'shift-jis':
        return charset.shiftJis.decode(bytes);
      case 'euc-jp':
        return charset.eucJp.decode(bytes);
      case 'euc-kr':
        return charset.eucKr.decode(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  } catch (e) {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// 启动项配置弹窗 - 适配 tactic 接口，包含启动项、区域、本地化编辑
class StartupConfigModal extends ConsumerStatefulWidget {
  final TacticItem item;
  final bool isAdmin;
  final VoidCallback onSuccess;

  /// T8c-2 新增（**可选，默认 private，V1 两个页面不传 → 行为一字未变**）：
  /// 策略形态。[StrategyVariant.public] 时的**全部**差异：
  ///   1. 「区域配置」页签换成「生效网吧」多选，并**加载全部网吧 + 预选已生效的**
  ///      （web StrategyAddDialog.vue:1112-1134：公共策略无论编辑还是新增都拉全量；
  ///      私有策略编辑态则固定只构造当前一家、不请求列表，:806-822）
  ///   2. 保存走 POST /public-tactic/{id}，且要先把编辑前的生效网吧用
  ///      delete_merchants[] 全删一遍（后端先删后加，:998-1008）
  ///   3. 删除走 DELETE /public-tactic/{id}
  /// 其余字段两形态完全相同，**禁止**再分叉。
  final StrategyVariant variant;

  /// T8c-2 新增（**可选，默认 null，V1 不传 → 执行文件仍是只读文本框**）：
  /// 注入式执行文件选择器（下发文件区，评审 A-4）。注入后执行文件可改，
  /// 提交时按新路径 + 新 group_file_id 发；不注入时这两个值恒等于原策略的值，
  /// 提交内容与改动前逐字节一致。
  final StrategyExePicker? exePicker;

  const StartupConfigModal({
    super.key,
    required this.item,
    this.isAdmin = false,
    this.variant = StrategyVariant.private,
    this.exePicker,
    required this.onSuccess,
    List<dynamic> areas = const [],
  });

  @override
  ConsumerState<StartupConfigModal> createState() => _StartupConfigModalState();
}

class _StartupConfigModalState extends ConsumerState<StartupConfigModal>
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

  // --- 区域字段（仅私有策略）---
  late TextEditingController _areaInputController;
  late List<_AreaEntry> _areaList;

  // --- 生效网吧（仅公共策略）---
  late Set<int> _selectedMerchantIds;

  /// 编辑前的生效网吧（提交时作为 delete_merchants[]，先删后加）
  late List<int> _originalMerchantIds;

  // --- 执行文件（注入 exePicker 时可改；否则恒为原值）---
  late TextEditingController _pathController;
  int? _exeGroupFileId;

  bool get _isPublic => widget.variant == StrategyVariant.public;

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

    // 执行文件：注入选择器时可改，否则这两个值全程不变（= 改动前的提交口径）
    _pathController =
        TextEditingController(text: startup?.startupPath ?? '');
    _exeGroupFileId = startup?.groupFileId;

    // 生效网吧（公共策略）：预选已生效的，并记下原始集合用于 delete_merchants[]
    _originalMerchantIds = widget.item.merchants.map((m) => m.id).toList();
    _selectedMerchantIds = _originalMerchantIds.toSet();

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
                fileId: l.fileId,
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
    _pathController.dispose();
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
              f.contentController.text.isNotEmpty ||
              f.fileBytes != null)
          .map((f) => LocaleSubmitData(
                id: f.id,
                groupFileId: f.groupFileId,
                path: f.pathController.text,
                content: f.mode == 'text' ? f.contentController.text : null,
                fileBytes: f.mode == 'upload' ? f.fileBytes : null,
                fileName: f.mode == 'upload' ? f.fileName : null,
                // T8c-0 行为变更 d：把已上传文件的 file_id 带回去，避免重编辑丢引用。
                // group_file_id==0 是后端标记"这条本地化是上传上来的文件"
                // （对齐 web StrategyAddDialog.vue:1184 `const isUpload = l.group_file_id == 0`），
                // 本弹窗不按它切换显示模式（T8c-2 未做：本地化两形态一致，
                // "上传态"的 UI 呈现留待后续），
                // 但提交时必须按上传模式发键，否则后端会把上传文件当成文本内容处理。
                fileId: f.fileId,
                isUploadMode: f.mode == 'upload' || f.groupFileId == 0,
              ))
          .toList();

      // 构建 area
      final area =
          _areaList.where((a) => a.enabled).map((a) => a.range).toList();

      if (_isPublic) {
        // T8c-2：公共策略 → POST /public-tactic/{id}。
        // 不发 area（公共策略无区域）；deleteMerchantIds 传编辑前的全部生效网吧，
        // 共享层会先发 delete_merchants[] 再发新的 merchants（后端"先删后加"语义）。
        // 提交前兜底（finally 会复位 _saving）
        if (_selectedMerchantIds.isEmpty) {
          showTopNotice(context, '请至少选择一个网吧', level: NoticeLevel.error);
          return;
        }
        await _api.updatePublicTactic(
          widget.item.id,
          startupId: widget.item.startup?.id,
          path: _pathController.text,
          groupFileId: _exeGroupFileId,
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
          merchantIds: _selectedMerchantIds.toList(),
          deleteMerchantIds: _originalMerchantIds,
        );
      } else {
        await _api.updateTactic(
          widget.item.id,
          startupId: widget.item.startup?.id,
          // 未注入 exePicker 时这两个值 = initState 里从 item 取的原值，
          // 与改动前 `widget.item.startup?.xxx` 完全等价
          path: _pathController.text,
          groupFileId: _exeGroupFileId,
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
      }
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
      if (_isPublic) {
        await _api.deletePublicTactic(widget.item.id);
      } else {
        await _api.delete(widget.item.id);
      }
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
    final isSheet = context.isNarrow;
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
            tabs: [
              const Tab(text: '启动项'),
              // T8c-2：公共策略没有生效区域（web hasArea=false），该页签换成「生效网吧」
              Tab(text: _isPublic ? '生效网吧' : '区域配置'),
              const Tab(text: '本地化'),
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
                _isPublic
                    ? _buildMerchantsForm(isSheet: isSheet)
                    : SingleChildScrollView(
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
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(child: content),
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
                Text(
                  _isPublic ? '编辑公共策略' : '编辑策略配置',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
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
          // 执行文件：默认（V1）只读；注入 exePicker 时可从下发文件区改选
          _buildFormItem(
            label: '执行文件',
            child: _buildExeField(),
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

  /// 执行文件控件。
  /// **默认（V1）**：只读文本框，与改动前逐字一致（路径不可改，提交时原样发回）。
  /// **注入 exePicker 时（channel_v2）**：可从下发文件区改选，
  /// 对齐 web 编辑态执行文件同样可改（StrategyAddDialog.vue:81-83）。
  Widget _buildExeField() {
    final picker = widget.exePicker;
    if (picker == null) {
      return TextFormField(
        controller: _pathController,
        enabled: false,
        decoration: _inputDecoration('无'),
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      );
    }
    return StrategyInjectedExeField(
      controller: _pathController,
      decoration: _inputDecoration('从下发文件区选择'),
      picker: picker,
      onPicked: (p) => setState(() => _exeGroupFileId = p.groupFileId),
      // 对齐 web clearStartupPath（:581-584）。注意：路径清空后共享层
      // _appendStartup 会整块跳过 startup（T8c-0 行为变更 e），
      // 即"只改本地化、不动启动项"，这与 web `if (startupForm.execPath)` 一致。
      onCleared: () => setState(() => _exeGroupFileId = null),
    );
  }

  // ==================== 生效网吧 Tab（仅公共策略）====================
  Widget _buildMerchantsForm({required bool isSheet}) {
    return StrategyMerchantsPanel(
      api: _api,
      // 编辑态恒拉全量网吧（web 公共策略不按文件过滤，:1114 loadMerchants() 无参）
      initialSelectedIds: _selectedMerchantIds,
      isSheet: isSheet,
      onChanged: (ids) => setState(() => _selectedMerchantIds = ids),
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

  List<ExeZoneOption> _buildVisibleZones() {
    final auth = ref.read(authNotifierProvider);
    final user = auth.user;
    final isTopManager = user?.isTopManager == true;
    final groupId = user?.groupId ?? 0;

    return <ExeZoneOption>[
      const ExeZoneOption(label: '总公司资源', zone: 'HEADQUARTERS', netbarId: 0),
      // 非总部管理员（分部管理员或普通用户）显示分公司资源
      if (!isTopManager && groupId > 0)
        ExeZoneOption(label: '分公司资源', zone: 'BRANCH', netbarId: groupId),
      const ExeZoneOption(label: '共享区资源', zone: 'SHARED', netbarId: null),
    ];
  }

  static const int _maxEditableSize = 200 * 1024; // 最大可编辑文件大小 200KB（与文件管理预览一致）

  // 图片文件扩展名
  static const Set<String> _imageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.ico', '.svg', '.tiff', '.tif', '.heic', '.heif'
  };

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any((ext) => lower.endsWith(ext));
  }

  // 支持的编码列表
  static const List<MapEntry<String, String>> _supportedEncodings = [
    MapEntry('utf-8', 'UTF-8'),
    MapEntry('gbk', 'GBK (简体中文)'),
    MapEntry('shift-jis', 'Shift-JIS (日文)'),
    MapEntry('euc-jp', 'EUC-JP (日文)'),
    MapEntry('euc-kr', 'EUC-KR (韩文)'),
    MapEntry('latin1', 'ISO-8859-1 (Latin1)'),
    MapEntry('ascii', 'ASCII'),
  ];

  /// 异步解码（在后台线程执行）
  Future<String> _decodeContentAsync(Uint8List bytes, String encoding) async {
    return compute(_decodeInBackground, {'bytes': bytes, 'encoding': encoding});
  }

  /// 同步解码（用于编码切换等小操作）
  String _decodeContent(Uint8List bytes, String encoding) {
    return _decodeInBackground({'bytes': bytes, 'encoding': encoding});
  }

  Future<void> _loadFileContent(_LocaleFileEntry file, {bool forceLoad = false}) async {
    if (file.groupFileId == null) return;

    // 如果已有完整字节且是强制加载，直接解码显示
    if (forceLoad && file.fullBytes != null) {
      setState(() {
        file.rawBytes = file.fullBytes;
        file.isFullyLoaded = true;
      });
      // 使用异步解码避免阻塞 UI
      final content = await _decodeContentAsync(file.fullBytes!, file.encoding);
      if (mounted) {
        setState(() {
          file.contentController.text = content;
        });
      }
      return;
    }

    setState(() {
      file.isLoading = true;
      file.loadError = null;
    });

    try {
      final resourceApi = res.ResourceApi();

      // 参考 FileEditorModal：使用限量下载，先获取最多 _maxEditableSize + 1 字节
      // 如果返回的字节数超过限制，说明文件过大
      final limitedBytes = await resourceApi.downloadBytesLimited(
        file.groupFileId!,
        _maxEditableSize + 1,
      );

      final bytes = Uint8List.fromList(limitedBytes);

      // 判断文件是否过大
      if (bytes.length > _maxEditableSize && !forceLoad) {
        // 文件过大，不加载内容
        if (mounted) {
          setState(() {
            file.rawBytes = null;
            file.fullBytes = null;
            file.totalSize = bytes.length;
            file.isFullyLoaded = false;
            file.isLoading = false;
            file.contentController.text = '[文件较大] 文件大小超过可编辑限制 (${_formatFileSize(_maxEditableSize)})。\n\n如需编辑，请下载后使用本地编辑器修改。';
          });
        }
        return;
      }

      // 文件大小在限制内，正常显示
      file.rawBytes = bytes;
      file.fullBytes = bytes;
      file.totalSize = bytes.length;
      file.isFullyLoaded = true;

      // 使用异步解码避免阻塞 UI
      final content = await _decodeContentAsync(bytes, file.encoding);

      if (mounted) {
        setState(() {
          file.contentController.text = content;
          file.mode = 'text';
          file.isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          file.loadError = '加载失败: $e';
          file.isLoading = false;
        });
      }
    }
  }

  void _onEncodingChanged(_LocaleFileEntry file, String newEncoding) {
    // 只有已加载内容的文件才能切换编码
    if (file.rawBytes == null) return;
    setState(() {
      file.encoding = newEncoding;
      file.contentController.text = _decodeContent(file.rawBytes!, newEncoding);
    });
  }

  Future<void> _pickLocalePath(_LocaleFileEntry file) async {
    final visibleZones = _buildVisibleZones();
    final selected = await showAdaptive<res.Resource>(
      context,
      (context) => ExePickerDialog(visibleZones: visibleZones, exeOnly: false),
    );
    if (!mounted || selected == null) return;

    // ExePickerDialog 现在返回带有完整路径的 Resource
    final filePath = selected.path.isNotEmpty ? selected.path : selected.name;
    setState(() {
      file.pathController.text = filePath;
      file.groupFileId = selected.id;
    });

    // 如果是图片文件，显示提示而不加载内容
    if (_isImageFile(filePath)) {
      setState(() {
        file.mode = 'text';
        file.contentController.text = '[图片文件] 不支持预览图片内容，保存时将使用原文件。';
        file.rawBytes = null;
        file.fullBytes = null;
        file.isFullyLoaded = true;
      });
      return;
    }

    // 参考 FileEditorModal：先检查已知文件大小，超过限制直接显示提示，不下载
    if (selected.size > _maxEditableSize) {
      setState(() {
        file.mode = 'text';
        file.rawBytes = null;
        file.fullBytes = null;
        file.totalSize = selected.size;
        file.isFullyLoaded = false;
        file.contentController.text = '[文件较大] 文件大小 ${_formatFileSize(selected.size)}，超过可编辑限制 (${_formatFileSize(_maxEditableSize)})。\n\n如需编辑，请下载后使用本地编辑器修改。';
      });
      return;
    }

    // 自动加载文件内容
    await _loadFileContent(file);
  }

  Future<void> _pickLocaleFile(_LocaleFileEntry file) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );
    final picked = result?.files.single;
    if (picked == null || picked.bytes == null) return;
    setState(() {
      file.fileBytes = picked.bytes;
      file.fileName = picked.name;
    });
  }

  void _clearLocaleFile(_LocaleFileEntry file) {
    setState(() {
      file.fileBytes = null;
      file.fileName = null;
    });
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
            decoration: _inputDecoration('../开机文件/config.ini').copyWith(
              suffixIcon: IconButton(
                onPressed: () => _pickLocalePath(file),
                icon: Icon(LucideIcons.folderOpen, size: 16, color: Colors.grey.shade500),
                tooltip: '从资源中选择',
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(height: 16),

        // 模式切换 + 编码选择
        Row(
          children: [
            _buildModeChip('文本内容', file.mode == 'text', () {
              setState(() => file.mode = 'text');
            }),
            const SizedBox(width: 8),
            _buildModeChip('上传文件', file.mode == 'upload', () {
              setState(() => file.mode = 'upload');
            }),
            const Spacer(),
            // 编码选择
            if (file.mode == 'text') ...[
              Text('编码:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: file.encoding,
                    isDense: true,
                    menuMaxHeight: 300,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    items: _supportedEncodings
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value, style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _onEncodingChanged(file, v);
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // 加载错误提示
        if (file.loadError != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertCircle, size: 14, color: Colors.red.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.loadError!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 内容区
        Expanded(
          child: file.isLoading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text('正在加载文件内容...', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : file.mode == 'text'
                  ? _buildTextEditorWithLoadMore(file)
                  : _buildUploadArea(file),
        ),
      ],
    );
  }

  Widget _buildTextEditorWithLoadMore(_LocaleFileEntry file) {
    // 参考 FileEditorModal：大文件不支持强制加载，直接显示文本编辑器
    // 大文件情况下，contentController 中已包含提示信息
    return _buildTextEditor(file);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Widget _buildModeChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.iosBlue.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.iosBlue : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.iosBlue : Colors.grey.shade600,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTextEditor(_LocaleFileEntry file) {
    return Container(
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
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
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
    );
  }

  Widget _buildUploadArea(_LocaleFileEntry file) {
    if (file.fileBytes != null && file.fileName != null) {
      // 已选择文件
      final sizeKB = (file.fileBytes!.length / 1024).toStringAsFixed(1);
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(LucideIcons.file, size: 36, color: AppColors.iosBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName!,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$sizeKB KB',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => _pickLocaleFile(file),
              child: const Text('更换', style: TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: () => _clearLocaleFile(file),
              style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400),
              child: const Text('删除', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    // 未选择文件 - 上传占位
    return InkWell(
      onTap: () => _pickLocaleFile(file),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.grey.shade300, style: BorderStyle.solid),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.uploadCloud,
                  size: 36, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                '点击选择文件',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 4),
              Text(
                '支持任意文件类型',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
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
  int? groupFileId;
  /// T8c-0：后端回传的已上传文件 id，编辑保存时必须原样带回（否则丢文件引用）
  final int? fileId;
  final TextEditingController pathController;
  final TextEditingController contentController;
  String mode; // 'text' | 'upload'
  Uint8List? fileBytes;
  String? fileName;
  // 编码相关
  String encoding; // 'utf-8' | 'latin1' | 'ascii'
  Uint8List? rawBytes; // 当前显示的字节（可能是截断的）
  Uint8List? fullBytes; // 完整文件字节（用于"加载更多"）
  bool isLoading;
  String? loadError;
  int totalSize; // 文件总大小
  bool isFullyLoaded; // 是否已完全加载

  _LocaleFileEntry({
    this.id,
    this.groupFileId,
    this.fileId,
    required this.pathController,
    required this.contentController,
    this.mode = 'text',
    this.fileBytes,
    this.fileName,
    this.encoding = 'utf-8',
    this.rawBytes,
    this.fullBytes,
    this.isLoading = false,
    this.loadError,
    this.totalSize = 0,
    this.isFullyLoaded = true,
  });
}
