import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../data/application_models.dart';
import '../providers/application_providers.dart';

/// 应用策略配置弹窗（单网吧模式）。
///
/// 对齐 toolboxPage PolicyConfigDialog.vue 传入 merchantId 的形态：
/// 网吧已锁定（无网吧多选栏），左=生效机号区域管理，右=参数设置。
/// 选中区域已有策略 → 编辑（POST /application-policy/{appId}），
/// 无策略 → 新建（POST /application-policy）。
class PolicyConfigDialog extends ConsumerStatefulWidget {
  final int applicationId;
  final String applicationName;
  final int merchantId;
  final String merchantName;
  final int? groupId;

  const PolicyConfigDialog({
    super.key,
    required this.applicationId,
    required this.applicationName,
    required this.merchantId,
    required this.merchantName,
    this.groupId,
  });

  @override
  ConsumerState<PolicyConfigDialog> createState() => _PolicyConfigDialogState();
}

class _PolicyConfigDialogState extends ConsumerState<PolicyConfigDialog> {
  bool _loading = true;

  List<AppVersion> _versions = [];
  List<PolicyArea> _areas = [];
  List<ServerTerminal> _servers = [];

  /// 当前选中区域 key（单选，再点取消）
  String? _selectedAreaKey;

  /// 选中区域已有的策略 id：非空=编辑，空=新建（决定提交走更新还是新建）
  int? _currentPolicyId;

  PolicyParams _params = PolicyParams();

  final _areaCtrl = TextEditingController();
  int? _editingAreaId; // 非空=编辑该区域 id，空=新增

  final _parameterCtrl = TextEditingController();
  final _delayCtrl = TextEditingController(text: '0');

  String _periodStart = '00:00:00';
  String _periodEnd = '23:59:59';

  bool _submitting = false;

  /// 宽屏 Dialog 全屏切换（窄屏本就是全屏页，不显示切换按钮）
  bool _fullscreen = false;

  static const _systemOptions = ['win7', 'win10', 'win11'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _parameterCtrl.dispose();
    _delayCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final api = ref.read(applicationApiProvider);
    try {
      final results = await Future.wait([
        api.listVersions(widget.applicationId),
        api.listAreas(
          groupId: widget.groupId,
          merchantId: widget.merchantId,
          applicationId: widget.applicationId,
        ),
        api.getServerTerminals(widget.merchantId),
      ]);
      if (!mounted) return;
      setState(() {
        _versions = results[0] as List<AppVersion>;
        _areas = results[1] as List<PolicyArea>;
        _servers = results[2] as List<ServerTerminal>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopNotice(context, '加载策略数据失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _refreshAreas() async {
    final api = ref.read(applicationApiProvider);
    final areas = await api.listAreas(
      groupId: widget.groupId,
      merchantId: widget.merchantId,
      applicationId: widget.applicationId,
    );
    if (!mounted) return;
    setState(() => _areas = areas);
  }

  // ===== 区域：选中 / 回填 =====

  void _selectArea(PolicyArea opt) {
    final willSelect = _selectedAreaKey != opt.key;
    setState(() => _selectedAreaKey = willSelect ? opt.key : null);
    if (willSelect) {
      _loadAreaPolicy(opt.id);
    } else {
      // 取消选中 → 视为无策略，防止提交误走更新
      _currentPolicyId = null;
    }
  }

  /// 按区域取策略参数回填；该区域无策略则重置默认参数（提交走新建）
  Future<void> _loadAreaPolicy(int areaId) async {
    final api = ref.read(applicationApiProvider);
    try {
      final policy = await api.getPolicyByArea(
        groupId: widget.groupId,
        merchantId: widget.merchantId,
        applicationId: widget.applicationId,
        areaId: areaId,
      );
      if (!mounted) return;
      setState(() {
        if (policy == null) {
          _currentPolicyId = null;
          _params = PolicyParams();
        } else {
          final rawId = policy['id'];
          _currentPolicyId =
              rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
          _params = PolicyParams.fromPolicyJson(policy);
        }
        _parameterCtrl.text = _params.parameter;
        _delayCtrl.text = '${_params.delay}';
      });
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '加载区域策略失败: $e', level: NoticeLevel.error);
    }
  }

  // ===== 区域：增 / 改 / 删 =====

  /// 机号文本 → 数组（按中/英文逗号拆分、去空白）
  List<String> _parseAreaText(String text) => text
      .split(RegExp(r'[,，]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void _startEditArea(PolicyArea opt) {
    setState(() {
      _editingAreaId = opt.id;
      _areaCtrl.text = opt.area.join('，');
    });
  }

  void _cancelEditArea() {
    setState(() {
      _editingAreaId = null;
      _areaCtrl.clear();
    });
  }

  Future<void> _submitArea() async {
    final text = _areaCtrl.text.trim();
    if (text.isEmpty) return;
    final area = _parseAreaText(text);
    if (area.isEmpty) return;

    final api = ref.read(applicationApiProvider);
    final editId = _editingAreaId;
    try {
      final data = editId != null
          ? await api.updateArea(
              editId,
              groupId: widget.groupId,
              merchantId: widget.merchantId,
              applicationId: widget.applicationId,
              area: area,
            )
          : await api.addArea(
              groupId: widget.groupId,
              merchantId: widget.merchantId,
              applicationId: widget.applicationId,
              area: area,
            );
      if (!mounted) return;
      showTopNotice(context, editId != null ? '区域已更新' : '区域已添加',
          level: NoticeLevel.success);
      setState(() {
        _editingAreaId = null;
        _areaCtrl.clear();
      });
      await _refreshAreas();
      if (!mounted) return;

      // 选中目标项：优先返回 area_key，否则按机号文本匹配
      dynamic key = data?['area_key'];
      final nested = data?['area'];
      if (key == null && nested is Map) key = nested['area_key'];
      PolicyArea? target;
      for (final o in _areas) {
        if (key != null ? o.key == '$key' : o.area.join('，') == area.join('，')) {
          target = o;
          break;
        }
      }
      if (target != null) {
        final t = target;
        setState(() => _selectedAreaKey = t.key);
        _loadAreaPolicy(t.id);
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '${editId != null ? '编辑' : '添加'}区域失败: $e',
          level: NoticeLevel.error);
    }
  }

  Future<void> _removeArea(PolicyArea opt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除区域「${opt.label}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref.read(applicationApiProvider).deleteArea(opt.id);
      if (!mounted) return;
      showTopNotice(context, '已删除', level: NoticeLevel.success);
      if (_selectedAreaKey == opt.key) {
        setState(() {
          _selectedAreaKey = null;
          _currentPolicyId = null;
        });
      }
      await _refreshAreas();
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
    }
  }

  // ===== 生效时段 =====

  /// 时间选择：原生组件精确到分，秒固定 00（默认值保持 web 同款全天 00:00:00~23:59:59）
  Future<void> _pickTime(bool isStart) async {
    final current = isStart ? _periodStart : _periodEnd;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null || !mounted) return;
    final text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
    setState(() {
      if (isStart) {
        _periodStart = text;
      } else {
        _periodEnd = text;
      }
    });
  }

  void _addPeriod() {
    setState(() {
      _params.period = [
        ..._params.period,
        PolicyPeriod(start: _periodStart, end: _periodEnd),
      ];
    });
  }

  void _removePeriod(int index) {
    setState(() {
      _params.period = [..._params.period]..removeAt(index);
    });
  }

  // ===== 提交 =====

  Future<void> _handleSubmit() async {
    final versionId = _params.versionId;
    if (versionId == null) {
      showTopNotice(context, '请选择版本', level: NoticeLevel.warning);
      return;
    }

    int? areaId;
    if (_selectedAreaKey != null) {
      for (final o in _areas) {
        if (o.key == _selectedAreaKey) {
          areaId = o.id;
          break;
        }
      }
    }

    final payload = PolicyPayload(
      groupId: widget.groupId,
      applicationId: widget.applicationId,
      versionId: versionId,
      parameter: _parameterCtrl.text.trim(),
      strategyMode: _params.strategyMode,
      period: _params.period,
      delay: int.tryParse(_delayCtrl.text.trim()) ?? 0,
      isRandomName: _params.isRandomName,
      isForcedOn: _params.isForcedOn,
      systems: _params.systems,
      server: _params.server,
      merchantIds: [widget.merchantId],
      areaId: areaId,
    );

    setState(() => _submitting = true);
    final api = ref.read(applicationApiProvider);
    try {
      // 选中区域已有策略 → 编辑；区域无策略（如新增的区域）→ 新建
      if (_currentPolicyId != null) {
        await api.updatePolicy(payload);
      } else {
        await api.createPolicy(payload);
      }
      if (!mounted) return;
      showTopNotice(context, '保存成功', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow;
    final screen = MediaQuery.sizeOf(context);
    return ResponsiveDialogScaffold(
      title: '${widget.applicationName} 策略配置',
      // 全屏：尺寸给到屏幕大小（保持有界约束）+ 去掉 Dialog 屏幕边距
      maxWidth: _fullscreen ? screen.width : 980,
      maxHeight: _fullscreen ? screen.height : null,
      insetPadding: _fullscreen ? EdgeInsets.zero : null,
      scrollableBody: false,
      appBarActions: isNarrow
          ? null
          : [
              IconButton(
                icon: Icon(
                  _fullscreen ? LucideIcons.minimize2 : LucideIcons.maximize2,
                  size: 18,
                ),
                tooltip: _fullscreen ? '还原' : '全屏',
                onPressed: () => setState(() => _fullscreen = !_fullscreen),
              ),
            ],
      body: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          : (isNarrow ? _buildNarrowBody() : _buildWideBody()),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed:
                _submitting ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _submitting ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildAreaPanel(expandList: true),
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFFF0F2F5)),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildParamForm(),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAreaPanel(expandList: false),
          const Divider(height: 32),
          _buildParamForm(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
      );

  // ===== 左栏：生效机号 =====

  Widget _buildAreaPanel({required bool expandList}) {
    final list = _areas.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无选项，可在上方新增',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          )
        : Column(
            children: [for (final o in _areas) _buildAreaOption(o)],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: expandList ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _sectionTitle('生效机号'),
        TextField(
          controller: _areaCtrl,
          decoration: InputDecoration(
            hintText: _editingAreaId != null
                ? '编辑机号 001-025，033-257'
                : '生效机号 001-025，033-257',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(
              icon: Icon(
                _editingAreaId != null ? LucideIcons.check : LucideIcons.plus,
                size: 16,
              ),
              tooltip: _editingAreaId != null ? '保存' : '添加',
              onPressed: _submitArea,
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onSubmitted: (_) => _submitArea(),
        ),
        if (_editingAreaId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Text(
                  '编辑中',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE6A23C)),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _cancelEditArea,
                  child: const Text(
                    '取消',
                    style: TextStyle(fontSize: 12, color: AppColors.iosBlue),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        if (expandList)
          Expanded(child: SingleChildScrollView(child: list))
        else
          list,
      ],
    );
  }

  Widget _buildAreaOption(PolicyArea o) {
    final active = _selectedAreaKey == o.key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectArea(o),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEFF6FF) : null,
            border: Border.all(
              color: active ? AppColors.iosBlue : const Color(0xFFE5E7EB),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  o.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? AppColors.iosBlue : const Color(0xFF4B5563),
                    fontWeight: active ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _startEditArea(o),
                child: Icon(LucideIcons.edit2,
                    size: 14, color: Colors.grey.shade400),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _removeArea(o),
                child: Icon(LucideIcons.trash2,
                    size: 14, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== 右栏：参数设置 =====

  Widget _buildParamForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('参数设置'),
        _formRow(
          '选择版本',
          DropdownButtonFormField<int>(
            // FormField 的 initialValue 变化不会刷新已建 state，
            // 切换区域回填版本时必须用 key 强制重建
            key: ValueKey('version-${_params.versionId}-${_versions.length}'),
            initialValue: _versions.any((v) => v.id == _params.versionId)
                ? _params.versionId
                : null,
            isDense: true,
            decoration: _denseInputDecoration(hint: '选择版本'),
            items: [
              for (final v in _versions)
                DropdownMenuItem(value: v.id, child: Text(v.version)),
            ],
            onChanged: (v) => setState(() => _params.versionId = v),
          ),
        ),
        _formRow(
          '执行参数',
          TextField(
            controller: _parameterCtrl,
            decoration: _denseInputDecoration(hint: '可选'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        _formRow(
          '延迟启动',
          SizedBox(
            width: 140,
            child: TextField(
              controller: _delayCtrl,
              keyboardType: TextInputType.number,
              decoration: _denseInputDecoration(suffixText: '秒'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        _formRow(
          '随机进程名',
          Align(
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _params.isRandomName,
              onChanged: (v) => setState(() => _params.isRandomName = v),
            ),
          ),
        ),
        _formRow(
          '强制开启',
          Align(
            alignment: Alignment.centerLeft,
            child: Switch(
              value: _params.isForcedOn,
              onChanged: (v) => setState(() => _params.isForcedOn = v),
            ),
          ),
        ),
        _formRow('生效时段', _buildPeriodEditor()),
        _formRow(
          '执行策略',
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<int>(
              initialValue: _params.strategyMode,
              isDense: true,
              decoration: _denseInputDecoration(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('直接启动')),
              ],
              onChanged: (v) =>
                  setState(() => _params.strategyMode = v ?? 0),
            ),
          ),
        ),
        _formRow(
          '生效系统',
          Wrap(
            spacing: 8,
            children: [
              for (final s in _systemOptions)
                FilterChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  selected: _params.systems.contains(s),
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _params.systems = [..._params.systems, s];
                    } else {
                      _params.systems =
                          _params.systems.where((x) => x != s).toList();
                    }
                  }),
                ),
            ],
          ),
        ),
        _formRow('服务端', _buildServerCards()),
      ],
    );
  }

  InputDecoration _denseInputDecoration({String? hint, String? suffixText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      suffixText: suffixText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _formRow(String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildPeriodEditor() {
    Widget timeButton(String value, bool isStart) {
      return OutlinedButton.icon(
        onPressed: () => _pickTime(isStart),
        icon: const Icon(LucideIcons.clock, size: 14),
        label: Text(value, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF4B5563),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            timeButton(_periodStart, true),
            Text('至',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            timeButton(_periodEnd, false),
            IconButton(
              onPressed: _addPeriod,
              icon: const Icon(LucideIcons.plus, size: 16),
              tooltip: '添加时段',
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_params.period.isEmpty)
          Text(
            '未设置 = 全天生效',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _params.period.length; i++)
                Chip(
                  label: Text(
                    '${_params.period[i].start} ~ ${_params.period[i].end}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(LucideIcons.x, size: 14),
                  onDeleted: () => _removePeriod(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildServerCards() {
    if (_servers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '无可用服务器',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final s in _servers) _buildServerCard(s),
      ],
    );
  }

  Widget _buildServerCard(ServerTerminal s) {
    final active = _params.server == '${s.id}';
    return InkWell(
      // 再次点击当前选中项 → 取消选择（对齐 web 单选可取消）
      onTap: () => setState(
        () => _params.server = active ? '' : '${s.id}',
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFF6FF) : Colors.white,
          border: Border.all(
            color: active ? AppColors.iosBlue : const Color(0xFFE5E7EB),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: active ? AppColors.iosBlue : const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.monitor,
                    size: 24,
                    color: active ? Colors.white : Colors.grey.shade400,
                  ),
                ),
                if (active)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.iosBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.check,
                          size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.iosBlue : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              s.ip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
