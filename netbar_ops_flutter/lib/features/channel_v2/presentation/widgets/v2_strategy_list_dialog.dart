import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/permission_provider.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../strategy/data/strategy_api.dart';
import '../../../strategy/data/strategy_permission.dart';
import '../../../strategy/presentation/widgets/add_startup_item_modal.dart';
import '../../../strategy/presentation/widgets/startup_config_modal.dart';
import '../../../strategy/presentation/widgets/strategy_exe_picker.dart';
import '../../data/channel_v2_api.dart';
import '../channel_v2_file_actions.dart' show v2ErrMessage, v2ConfirmDanger;
import 'v2_delivery_exe_picker_dialog.dart';
import 'v2_pagination_bar.dart';
import 'v2_toolbar_controls.dart';

/// 策略列表弹窗的两种形态。
///
/// web 是两个文件：NetbarStrategyDialog.vue(596) / PublicStrategyDialog.vue(686)，
/// 其中 formatStrategy / formatPeriods / formatRemainTime / startCountdown /
/// updateEnableStatus / confirmDisable / performEnableDisable / getLocaleType /
/// extSuffix / canEdit / canDelete / copyItem 共 11 个函数**逐字符重复**。
/// Flutter 侧只写一套，差异全部收敛到本枚举 + [_VariantSpec]。
enum V2StrategyVariant {
  /// 网吧私有策略 → GET/DELETE /tactic
  private,

  /// 程序公共策略 → GET/DELETE /public-tactic
  public,
}

/// variant 之间的**全部**差异点（列集合、接口、下拉项）。
/// 新增差异必须加在这里，不要在 build 里散写 `if (variant == ...)`。
class _VariantSpec {
  final String title;

  /// type 下拉项：公共策略多一个 file（程序名称）
  final List<({String value, String label})> typeOptions;

  const _VariantSpec({required this.title, required this.typeOptions});

  static const private = _VariantSpec(
    title: '网吧私有策略',
    typeOptions: [
      (value: 'merchant', label: '网吧名称'),
      (value: 'group', label: '分组名称'),
    ],
  );

  static const public = _VariantSpec(
    title: '程序公共策略',
    typeOptions: [
      (value: 'merchant', label: '网吧名称'),
      (value: 'group', label: '分组名称'),
      // web PublicStrategyDialog.vue:204 独有；私有弹窗把这项注释掉了
      (value: 'file', label: '程序名称'),
    ],
  );
}

/// 公共策略「生效网吧」列的折叠阈值（对齐 web MERCHANT_PREVIEW_LIMIT=3）
const int _kMerchantPreviewLimit = 3;

/// 文本类扩展名白名单（逐字照抄 web 两个弹窗里同一份 TEXT_FILE_EXTENSIONS）
const Set<String> _kTextFileExtensions = {
  'txt', 'ini', 'inf', 'json', 'xml', 'yaml', 'yml', 'cfg', 'conf',
  'properties', 'csv', 'bat', 'cmd', 'ps1', 'reg', 'log', 'env', 'sh',
  'lua', 'html', 'htm',
};

// ===========================================================================
// 纯函数（与 web 同名函数一一对应，便于对照）
// ===========================================================================

/// web formatStrategy：mode 三值。
/// mode='2'（进程不存在时启动）**必须有分支**，漏掉会把它显示成"无限制"。
String _formatStrategy(StartupStrategy? s) {
  if (s == null) return '';
  switch (s.mode) {
    case '1':
      return '检测到进程[${s.name.isEmpty ? '未设置' : s.name}]存在时启动';
    case '2':
      return '检测到进程[${s.name.isEmpty ? '未设置' : s.name}]不存在时启动';
    default:
      return '';
  }
}

/// web formatPeriods：多段用 ', ' 连接
String _formatPeriods(List<StartupPeriod> periods) {
  if (periods.isEmpty) return '-';
  return periods.map((p) => '${p.start}-${p.end}').join(', ');
}

/// web getLocaleType：先看有没有换行（有换行必是文本内容），再看扩展名白名单
String _localeType(LocaleItem l) {
  final filename = l.path.isNotEmpty ? l.path : (l.content ?? '');
  if (filename.contains('\n')) return '文本';
  final segs = filename.split('.');
  final ext = segs.length > 1 ? segs.last.toLowerCase() : '';
  if (ext.isNotEmpty && !_kTextFileExtensions.contains(ext)) return '文件';
  return '文本';
}

/// web extSuffix：只按 '/' 取最后一段（Windows 反斜杠路径不拆，照抄不修）
String _extSuffix(String? p) {
  if (p == null || p.isEmpty) return '';
  final name = p.split('/').last;
  final segs = name.split('.');
  if (segs.length <= 1) return '';
  return segs.last;
}

/// web formatRemainTime：HH:mm:ss，小时不取模（超过 24h 就显示 26:xx:xx）
String _formatRemainTime(DateTime? target) {
  if (target == null) return '';
  final diff = target.difference(DateTime.now());
  if (diff.isNegative || diff.inMilliseconds <= 0) return '00:00:00';
  final h = diff.inHours;
  final m = diff.inMinutes % 60;
  final s = diff.inSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}

// ===========================================================================
// 主弹窗
// ===========================================================================

/// 策略列表弹窗（对齐 web NetbarStrategyDialog.vue / PublicStrategyDialog.vue）。
///
/// 打开方必须包在 ChannelV2Page 的 `_guardDialog` 里（弹窗计数器，快捷键靠它避让）。
class V2StrategyListDialog extends ConsumerStatefulWidget {
  final V2StrategyVariant variant;

  /// 右键「策略」入口预留：按某个文件过滤策略。
  /// 本期工具栏入口恒传 null = 全局策略（对齐 web `currentDialogFile=null`）。
  /// web 的右键入口是**从未激活的死路径**，故本期不接。
  final int? groupFileId;
  final String? groupFileType;

  const V2StrategyListDialog({
    super.key,
    required this.variant,
    this.groupFileId,
    this.groupFileType,
  });

  @override
  ConsumerState<V2StrategyListDialog> createState() =>
      _V2StrategyListDialogState();
}

class _V2StrategyListDialogState extends ConsumerState<V2StrategyListDialog> {
  final StrategyApi _api = StrategyApi();

  final TextEditingController _searchCtrl = TextEditingController();

  /// 聚焦高亮由 [V2ToolbarTextField] 内部监听（边框是它自绘的，
  /// InputDecorator 的 focusedBorder 已被置 none）；这里只负责持有与释放，
  /// 本弹窗不再为焦点变化整体 rebuild。
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _hScroll = ScrollController();

  String _type = 'merchant';
  int _page = 1;
  int _perPage = 20;
  int _total = 0;
  bool _loading = false;
  String? _error;
  List<TacticItem> _items = const [];

  /// 正在提交启禁用的 startup.id（对齐 web `row._updating`，防重复点击）
  final Set<int> _updating = {};

  /// 公共策略「生效网吧」列已展开的行（key = tactic.id）
  final Set<int> _expandedMerchants = {};

  _VariantSpec get _spec => widget.variant == V2StrategyVariant.private
      ? _VariantSpec.private
      : _VariantSpec.public;

  bool get _isPrivate => widget.variant == V2StrategyVariant.private;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  // ====== 数据 ======

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keyword = _searchCtrl.text.trim();
      final result = _isPrivate
          ? await _api.listPrivateTactics(
              page: _page,
              perPage: _perPage,
              keyword: keyword.isEmpty ? null : keyword,
              type: _type,
              groupFileId: widget.groupFileId,
              groupFileType: widget.groupFileType,
            )
          : await _api.listPublicTactics(
              page: _page,
              perPage: _perPage,
              keyword: keyword.isEmpty ? null : keyword,
              type: _type,
              groupFileId: widget.groupFileId,
              groupFileType: widget.groupFileType,
            );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        // total 来自 paginator.total（T8c-0 已改口径）。
        // 【留痕】私有策略的 total 单位是"网吧"而不是"策略行"：
        // 一个网吧挂多条策略时本页行数会大于 per_page，行数与 total 对不齐属预期。
        _total = result.total;
        _expandedMerchants.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = v2ErrMessage(e, '获取策略列表失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _search() {
    _page = 1;
    _fetch();
  }

  void _notice(String m, NoticeLevel level) {
    if (mounted) showTopNotice(context, m, level: level);
  }

  // ====== 启禁用 ======

  /// web updateEnableStatus：val=true 表示用户希望启用
  Future<void> _onEnableChanged(TacticItem row, bool val) async {
    final startup = row.startup;
    if (startup == null || row.isPlaceholder) return;
    final perm = ref.read(permissionProvider);

    if (val && !perm.isManager) {
      _notice('仅管理员可以启用配置', NoticeLevel.warning);
      return;
    }

    if (val) {
      await _performEnableDisable(row, true);
      return;
    }

    // 禁用：先选时长
    // 【对 web 的修正，留痕】web 判「永久」选项可见性用的是
    // `currentDisableRow?.is_forced_on !== 1`（NetbarStrategyDialog.vue:116），
    // 但 is_forced_on 实际挂在 row.startup 上、行对象上根本没这个字段 →
    // 该条件恒为 true，是个失效的守卫。这里按 row.startup.isForcedOn 正确判定。
    final allowPermanent = perm.isManager &&
        startup.isForcedOn != true &&
        (perm.isHQUser || row.groupId == perm.groupId);

    final hours = await showAdaptive<int>(
      context,
      (_) => _DisableDurationDialog(
        itemName: _rowLabel(row),
        allowPermanent: allowPermanent,
      ),
      routeName: '/dialog/v2-strategy-disable-duration',
      barrierDismissible: false,
    );
    if (!mounted) return;
    if (hours == null) {
      // 对齐 web handleDisableDialogClose：关窗也刷新一次
      await _fetch();
      return;
    }
    await _performEnableDisable(row, false, hours: hours);
  }

  /// web performEnableDisable：两个 variant 的启禁用端点完全相同
  /// （`POST /startup/{enable|disable}/{startup.id}`），不做 variant 分流。
  Future<void> _performEnableDisable(TacticItem row, bool enable,
      {int? hours}) async {
    final startup = row.startup;
    if (startup == null) return;
    setState(() => _updating.add(startup.id));
    try {
      if (enable) {
        await _api.enable(startup.id);
      } else {
        // hours==0 → 永久禁用。共享层 disable() 会把 'permanent' 映射成 hours:0
        // （T8c-0 行为变更 a：永久禁用必须显式发 hours:0，不能发空 body）。
        await _api.disable(
          startup.id,
          EnabledState(status: false, duration: hours == 0 ? 'permanent' : hours),
        );
      }
      if (!mounted) return;
      _notice(enable ? '启用成功' : '禁用成功', NoticeLevel.success);
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      _notice(v2ErrMessage(e, enable ? '启用失败' : '禁用失败'), NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _updating.remove(startup.id));
    }
  }

  // ====== 行操作 ======

  String _rowLabel(TacticItem row) {
    if (_isPrivate) {
      final n = row.merchant?.name ?? '';
      if (n.isNotEmpty) return n;
    }
    final p = row.startup?.startupPath ?? '';
    return p.isEmpty ? '该策略' : p;
  }

  Future<void> _deleteRow(TacticItem row) async {
    // 占位行没有真实策略：web 在这里会发 `DELETE /tactic/null`，不复刻
    if (row.isPlaceholder) return;
    final ok = await v2ConfirmDanger(
      context,
      title: '删除确认',
      message: _isPrivate
          ? '确认删除「${_rowLabel(row)}」的网吧策略？'
          : '确认删除公共策略「${_rowLabel(row)}」？',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    try {
      if (_isPrivate) {
        await _api.delete(row.id);
      } else {
        await _api.deletePublicTactic(row.id);
      }
      if (!mounted) return;
      _notice('删除成功', NoticeLevel.success);
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      _notice(v2ErrMessage(e, '删除失败'), NoticeLevel.error);
    }
  }

  /// 执行文件选择器（T8c-2，评审 A-4）：策略表单选执行文件必须走**下发文件区**
  /// （web FileSelectDialog source='delivery'），共享层默认的 ExePickerDialog 走的是
  /// 资源中心，文件域不对。这里按注入点把 channel_v2 的下发树选择器塞进共享层表单。
  ///
  /// scope 口径对齐 web fileScope（StrategyAddDialog.vue:573-579）：
  /// **私有策略编辑态**（策略已固定归属一家网吧）按该网吧查它自己的下发区；
  /// 其余情况（新增 / 复制可多选网吧、公共策略无网吧归属）留空，
  /// 由选择器按当前账号身份推导 hq / group。
  StrategyExePicker _exePicker({MerchantBrief? merchantScope}) {
    final api = ref.read(channelV2ApiProvider);
    if (merchantScope != null) {
      return v2DeliveryExePicker(api,
          scopeType: 'merchant', scopeId: '${merchantScope.id}');
    }
    return v2DeliveryExePicker(api);
  }

  /// 共享层表单的宽屏宽度：用户反馈 #3 要求放大 30%（560 → 728）。
  /// 只有 V2 传这个值，V1 两个旧页面不传 → 仍是 560。
  static const double _kFormDialogWidth = 728;

  /// 编辑：直接复用共享层 StartupConfigModal
  /// （私有 = /tactic，公共 = /public-tactic，由 variant 决定）
  Future<void> _editRow(TacticItem row) async {
    if (row.isPlaceholder) return;
    final perm = ref.read(permissionProvider);
    await showAdaptive<void>(
      context,
      (_) => StartupConfigModal(
        item: row,
        isAdmin: perm.isManager,
        variant:
            _isPrivate ? StrategyVariant.private : StrategyVariant.public,
        exePicker: _exePicker(
          merchantScope: _isPrivate ? row.merchant : null,
        ),
        // 【留痕】私有编辑态没有「生效网吧」页签、提交也不带 merchants[]：
        // 生效网吧一旦创建就不可改，这是 web 的原始行为。
        dialogWidth: _kFormDialogWidth,
        onSuccess: _fetch,
      ),
      routeName: '/dialog/startup-config',
    );
  }

  /// 新增（含占位行入口）：复用共享层 AddStartupItemModal。
  ///
  /// 两种形态都**不弹前置网吧选择器**——网吧一律在表单的「生效网吧」页签里多选
  /// （私有靠 `allowMerchantSelect: true` 打开该页签），与 web 一致
  /// （LocalStrategyAdd.vue 新增/编辑共用同一个多选面板）。
  ///
  /// 【生效网吧的初始勾选，留痕】按**入口意图**分两种，不做任何与用户操作无关的
  /// 自动勾选：
  ///   - 工具栏「新增」（[merchant] 为 null）：一家都不勾，用户自己在面板里选；
  ///   - 占位行「新增策略」（[merchant] = 该行网吧）：预勾这一家，用户可再增删。
  ///     这是承接用户"给这家网吧建策略"的显式点击，不是默认值。
  Future<void> _addStrategy({MerchantBrief? merchant, TacticItem? template}) async {
    final perm = ref.read(permissionProvider);
    await showAdaptive<void>(
      context,
      (_) => AddStartupItemModal(
        // 【留痕】zone 是 AddStartupItemModal 的死参数（全文件无 widget.zone 引用），
        // 传值仅为满足 required；V2 没有 zone 概念。
        zone: 'BRANCH',
        // 【留痕】不传 netbarId：它只服务于共享层"没有生效网吧面板时以单个网吧
        // 上下文提交"的 V1 旁路；V2 两种形态都走表单内多选面板，传了也不会被读。
        isAdmin: perm.isManager,
        template: template,
        variant:
            _isPrivate ? StrategyVariant.private : StrategyVariant.public,
        exePicker: _exePicker(),
        dialogWidth: _kFormDialogWidth,
        // 私有新增态用表单内的「生效网吧」多选面板选网吧（默认一家都不勾），
        // 对齐 web LocalStrategyAdd 的多选行为。该开关只有 V2 传 true，
        // V1 两个旧页面不传 → 仍是 3 页签、网吧恒取入口 netbarId。
        // 公共形态恒有该面板，本开关对它无影响。
        allowMerchantSelect: true,
        // 见本方法文档：占位行入口预勾该行网吧，工具栏入口一家都不勾
        initialSelectedMerchantIds:
            merchant == null ? const <int>{} : <int>{merchant.id},
        onSuccess: _fetch,
      ),
      routeName: '/dialog/add-startup-item',
    );
  }

  /// 复制：对齐 web copyItem（深拷贝 → 剥离 id / startup.id / locales[].id → 进新增态）。
  ///
  /// 【Flutter 用显式 mode 表达，不靠 id==null 隐式判断】：
  /// 这里不构造"没有 id 的 TacticItem"，而是把整行当只读模板传给
  /// AddStartupItemModal（新增态），由它只读取表单字段、绝不读取任何 id。
  /// 复制态的生效网吧同样走表单内的多选面板：**公共**策略会预选模板原有的生效网吧
  /// （共享层按 `template.merchants` 预选）；**私有**策略不预选——私有 TacticItem 的
  /// 归属挂在单数 `merchant` 上、不在 `merchants` 里，且顶部已提示"请确认生效网吧"。
  /// 【未定，待用户拍板】私有复制是否也该预勾源网吧（同占位行入口的口径）。
  Future<void> _copyRow(TacticItem row) async {
    if (row.isPlaceholder) return;
    _notice('已复制配置，请确认生效网吧并保存', NoticeLevel.success);
    await _addStrategy(template: row);
  }

  // ====== 构建 ======

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow;
    return ResponsiveDialogScaffold(
      title: _spec.title,
      // 用户反馈 #3：弹窗放大 30%（1280→1664）。
      // 高度同步放宽：骨架的 effectiveMaxHeight = min(屏高*0.85, maxHeightCap)，
      // 默认 cap=820 会在 1080p 上先卡住，820*1.3≈1066 让它退回按屏高 0.85 走。
      // 两个值都只是**上限**，Dialog 本身受 屏宽/屏高 - insetPadding 收紧，小屏不越界。
      maxWidth: 1664,
      maxHeightCap: 1066,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(isNarrow),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          Expanded(child: _buildBody(isNarrow)),
        ],
      ),
      footer: _buildPagination(isNarrow),
    );
  }

  /// 顶部工具条控件全部走 [v2_toolbar_controls]（[kV2ControlHeight] 是唯一真源）。
  ///
  /// 【为什么不能在本文件里各写各的，留痕】前两轮就是在这里就地补高度，补完
  /// 别的弹窗照旧矮。根因有两条且方向相反（按钮被全局
  /// `visualDensity: adaptivePlatformDensity` 压到 32；输入框/下拉的边框由
  /// InputDecorator 自算、外层 SizedBox 只占位不撑边框），详见
  /// `v2_toolbar_controls.dart` 文件头。本文件只保留「刷新」这个 IconButton
  /// 的尺寸对齐，其余一律用共用控件。
  Widget _buildHeader(bool isNarrow) {
    final perm = ref.watch(permissionProvider);

    const hintByType = {
      'merchant': '请输入网吧名称',
      'group': '请输入分组名称',
      'file': '请输入程序名称',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          V2ToolbarDropdown<String>(
            value: _type,
            options: _spec.typeOptions,
            onChanged: (v) => setState(() => _type = v),
          ),
          V2ToolbarTextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            width: isNarrow ? 160 : 220,
            hintText: hintByType[_type] ?? '请输入关键字',
            onSubmitted: (_) => _search(),
          ),
          V2ToolbarButton(label: '搜索', onPressed: _search),
          // T8c-2：两个 variant 的新增都已接通（共享层表单按 variant 分流
          // merchants 键形与保存端点），不再置灰。
          if (perm.isManager)
            V2ToolbarButton(
              label: '添加',
              icon: LucideIcons.plus,
              onPressed: () => _addStrategy(),
            ),
          // 刷新是纯图标按钮：IconButton 默认 48x48 且会吃全局 density，
          // 这里压成与其余控件同高的正方形
          SizedBox(
            width: kV2ControlHeight,
            height: kV2ControlHeight,
            child: IconButton(
              tooltip: '刷新',
              onPressed: _fetch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: kV2ControlHeight, minHeight: kV2ControlHeight),
              icon: Icon(LucideIcons.refreshCw,
                  size: 16, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isNarrow) {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: Text('加载中...',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.red)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _fetch, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('暂无策略',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    return isNarrow ? _buildCardList() : _buildTable();
  }

  // ---------- 宽屏：表格 ----------

  List<({String label, double width, Alignment align})> get _columns {
    if (_isPrivate) {
      return const [
        (label: '网吧名称', width: 170.0, align: Alignment.centerLeft),
        (label: '终端数', width: 70.0, align: Alignment.center),
        (label: '所属分组', width: 140.0, align: Alignment.centerLeft),
        (label: '启动参数', width: 360.0, align: Alignment.centerLeft),
        (label: '强制开启', width: 80.0, align: Alignment.center),
        (label: '启动启禁用', width: 130.0, align: Alignment.center),
        (label: '本地化配置', width: 260.0, align: Alignment.centerLeft),
        (label: '操作', width: 160.0, align: Alignment.center),
      ];
    }
    return const [
      (label: '启动参数', width: 360.0, align: Alignment.centerLeft),
      (label: '所属分组', width: 130.0, align: Alignment.centerLeft),
      (label: '强制开启', width: 80.0, align: Alignment.center),
      (label: '本地化配置', width: 260.0, align: Alignment.centerLeft),
      (label: '生效网吧', width: 240.0, align: Alignment.centerLeft),
      (label: '启禁用', width: 130.0, align: Alignment.center),
      (label: '操作', width: 160.0, align: Alignment.center),
    ];
  }

  double get _tableWidth =>
      _columns.fold<double>(0, (sum, c) => sum + c.width);

  Widget _buildTable() {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = _tableWidth > cons.maxWidth ? _tableWidth : cons.maxWidth;
        return Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTableHeader(),
                  Expanded(
                    // 【虚拟化，评审 C-11】必须 ListView.builder。
                    // 与 resource_zone 的定高列表不同，**这里不能用 itemExtent**：
                    // 每行含 locales 子列表，行高不定，写死 extent 会截断内容。
                    child: ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _buildTableRow(_items[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFFAFBFC),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          for (final c in _columns)
            SizedBox(
              width: c.width,
              child: Align(
                alignment: c.align,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    c.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(TacticItem row) {
    final cells = _isPrivate ? _privateCells(row) : _publicCells(row);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F6))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < _columns.length; i++)
            SizedBox(
              width: _columns[i].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: _columns[i].align == Alignment.center
                      ? Alignment.topCenter
                      : Alignment.topLeft,
                  child: cells[i],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _privateCells(TacticItem row) {
    final groups =
        row.merchant?.groups?.map((g) => g.name).where((n) => n.isNotEmpty) ??
            const <String>[];
    return [
      Text(row.merchant?.name ?? '-',
          style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
      Text('${row.merchant?.terminalCount ?? '-'}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937))),
      Text(groups.isEmpty ? '-' : groups.join('、'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
      _startupCell(row),
      _forcedCell(row),
      _enableCell(row),
      _localesCell(row),
      _actionsCell(row),
    ];
  }

  List<Widget> _publicCells(TacticItem row) {
    return [
      _startupCell(row),
      Text(row.group?.name ?? '-',
          style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563))),
      _forcedCell(row),
      _localesCell(row),
      _merchantsCell(row),
      _enableCell(row),
      _actionsCell(row),
    ];
  }

  // ---------- 单元格 ----------

  /// 启动参数列（web command-cell：路径 + 参数 + 后缀 / 启动机号 / 启动时段 / 延迟·随机名·策略）
  Widget _startupCell(TacticItem row) {
    if (row.isPlaceholder) return _placeholderText();
    final s = row.startup;
    final path = s?.startupPath ?? '';
    final param = s?.parameter ?? '';
    final suffix = _extSuffix(path);
    final strategyText = _formatStrategy(s?.strategy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$path${param.isEmpty ? '' : ' $param'}'
          '${path.isEmpty || suffix.isEmpty ? '' : ' ($suffix)'}',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
        ),
        if (row.area.isNotEmpty)
          Text('启动机号: ${row.area.join(',')}', style: _noteStyle),
        if ((s?.period ?? const []).isNotEmpty)
          Text('启动时段: ${_formatPeriods(s!.period)}', style: _noteStyle),
        Text(
          '延迟: ${s?.startupDelay ?? 0}秒'
          '${(s?.isRandomName ?? false) ? ' | 随机进程名' : ''}'
          '${strategyText.isEmpty ? '' : ' | $strategyText'}',
          style: _noteStyle,
        ),
      ],
    );
  }

  Widget _forcedCell(TacticItem row) {
    if (row.isPlaceholder) return _placeholderText();
    final on = row.startup?.isForcedOn ?? false;
    return Text(
      on ? '开' : '关',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: on ? const Color(0xFFF56C6C) : const Color(0xFF909399),
      ),
    );
  }

  /// 启禁用列：Switch + 剩余时间倒计时
  Widget _enableCell(TacticItem row) {
    if (row.isPlaceholder) return _placeholderText();
    final perm = ref.watch(permissionProvider);
    final s = row.startup;
    if (s == null) return _placeholderText();
    final busy = _updating.contains(s.id);
    // 对齐 web `:disabled="row._updating || (row.startup?.is_disable && !isManager)"`
    final disabled = busy || (s.isDisable && !perm.isManager);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: !s.isDisable,
          onChanged: disabled ? null : (v) => _onEnableChanged(row, v),
          activeThumbColor: const Color(0xFF13CE66),
          inactiveThumbColor: const Color(0xFFFF4949),
        ),
        if (s.isDisable)
          (s.disableIn != null && s.disableIn!.isNotEmpty)
              // 【倒计时下沉，评审 C-5】web 每秒 `startupList=[...]` 强制全表重建，
              // 只为刷新这一格文本。Flutter 侧改为每格自带 Ticker 的独立 StatefulWidget，
              // 每秒只重建自己（且 ListView.builder 回收行时自动 cancel timer）。
              ? _RemainCountdown(disableIn: s.disableIn!)
              : const Text('永久禁用',
                  style: TextStyle(fontSize: 11, color: Color(0xFFF56C6C))),
      ],
    );
  }

  Widget _localesCell(TacticItem row) {
    if (row.isPlaceholder) return _placeholderText();
    if (row.locales.isEmpty) {
      return const Text('-',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in row.locales)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.path,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF333333))),
                Text(_localeType(l), style: _noteStyle),
              ],
            ),
          ),
      ],
    );
  }

  /// 公共策略「生效网吧」列：tag 展示前 3 个 + 展开/收起
  Widget _merchantsCell(TacticItem row) {
    final names = row.merchants
        .map((m) => m.name)
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) {
      return const Text('-',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)));
    }
    final expanded = _expandedMerchants.contains(row.id);
    final canToggle = names.length > _kMerchantPreviewLimit;
    final shown =
        expanded ? names : names.take(_kMerchantPreviewLimit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final n in shown)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F4F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFE9E9EB)),
                ),
                child: Text(n,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF909399))),
              ),
          ],
        ),
        if (canToggle)
          GestureDetector(
            onTap: () => setState(() {
              if (expanded) {
                _expandedMerchants.remove(row.id);
              } else {
                _expandedMerchants.add(row.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                expanded ? '收起' : '查看全部 ${names.length} 家',
                style: const TextStyle(fontSize: 11, color: AppColors.iosBlue),
              ),
            ),
          ),
      ],
    );
  }

  /// 操作列：编辑 / 复制 / 删除。
  /// 占位行**一律不渲染任何操作按钮**，只给「新增策略」入口。
  Widget _actionsCell(TacticItem row) {
    final perm = ref.watch(permissionProvider);
    if (row.isPlaceholder) {
      return _linkButton(
        '新增策略',
        AppColors.iosBlue,
        perm.isManager && row.merchant != null
            ? () => _addStrategy(merchant: row.merchant)
            : null,
      );
    }

    // 权限判定用 strategy_permission 扩展。
    // ⚠ 不可换成 PermissionService.canOperateGroupConfig：它对 creatorGroupId==0
    // 返回 true，与"总部创建的策略仅总部管理员可删"语义相反。
    final canEdit = perm.canEditStrategy(row);
    final canDelete = perm.canDeleteStrategy(row);
    // T8c-2：公共策略的编辑/复制已接通（共享层表单按 variant 分流），不再置灰。
    return Wrap(
      spacing: 2,
      alignment: WrapAlignment.center,
      children: [
        if (canEdit)
          _linkButton('编辑', AppColors.iosBlue, () => _editRow(row)),
        if (perm.isManager)
          _linkButton('复制', const Color(0xFF67C23A), () => _copyRow(row)),
        if (canDelete)
          _linkButton('删除', AppColors.red, () => _deleteRow(row)),
      ],
    );
  }

  Widget _linkButton(String label, Color color, VoidCallback? onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _placeholderText() => const Text('未配置',
      style: TextStyle(fontSize: 12, color: Color(0xFFBFC4CD)));

  static const TextStyle _noteStyle =
      TextStyle(fontSize: 11, color: Color(0xFF999999));

  // ---------- 窄屏：卡片列表 ----------
  //
  // 【web 未做，评审 D-10】宽表在手机端横向滚动不可用，这里降级成一行一卡。

  Widget _buildCardList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildCard(_items[i]),
    );
  }

  Widget _buildCard(TacticItem row) {
    final perm = ref.watch(permissionProvider);
    final s = row.startup;
    final title = _isPrivate
        ? (row.merchant?.name ?? '-')
        : (s?.startupPath ?? '-');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937))),
              ),
              if (row.isPlaceholder)
                _badge('未配置', const Color(0xFF9CA3AF))
              else ...[
                if (s?.isForcedOn ?? false)
                  _badge('强制开启', const Color(0xFFF56C6C)),
                _badge((s?.isDisable ?? false) ? '已禁用' : '启用中',
                    (s?.isDisable ?? false)
                        ? const Color(0xFFF56C6C)
                        : const Color(0xFF13CE66)),
              ],
            ],
          ),
          if (_isPrivate) ...[
            const SizedBox(height: 4),
            Text(_cardSubtitle(row), style: _noteStyle),
          ],
          if (!row.isPlaceholder) ...[
            const SizedBox(height: 8),
            _startupCell(row),
            if (row.locales.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('本地化配置',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              _localesCell(row),
            ],
            if (!_isPrivate && row.merchants.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('生效网吧',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280))),
              _merchantsCell(row),
            ],
            const Divider(height: 20),
            Row(
              children: [
                _enableCell(row),
                const Spacer(),
                // Row 给非 flex 子节点的是无限主轴约束，Wrap 拿到 infinity 会排成一行
                // 后溢出；必须用 Flexible 把剩余宽度收紧下去
                Flexible(child: _actionsCell(row)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _linkButton(
                '新增策略',
                AppColors.iosBlue,
                perm.isManager && row.merchant != null
                    ? () => _addStrategy(merchant: row.merchant)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 窄屏卡片副标题：终端数 + 所属分组
  String _cardSubtitle(TacticItem row) {
    final terminal = row.merchant?.terminalCount;
    final groups = row.merchant?.groups
            ?.map((g) => g.name)
            .where((n) => n.isNotEmpty)
            .join('、') ??
        '';
    return '终端数 ${terminal ?? '-'}${groups.isEmpty ? '' : ' · $groups'}';
  }

  Widget _badge(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, color: color)),
      );

  // ---------- 分页 ----------

  /// 分页条（用户反馈 #1 的右溢出 6.9px / 「20 条/...」被截断）。
  /// 已与任务列表弹窗合并为共用组件，见 [V2PaginationBar]。
  Widget _buildPagination(bool isNarrow) {
    return V2PaginationBar(
      total: _total,
      page: _page,
      perPage: _perPage,
      isNarrow: isNarrow,
      onPageChanged: (p) {
        _page = p;
        _fetch();
      },
      onPerPageChanged: (v) {
        _perPage = v;
        _page = 1;
        _fetch();
      },
    );
  }
}

// ===========================================================================
// 倒计时单元格（评审 C-5：重建范围只有这一格）
// ===========================================================================

class _RemainCountdown extends StatefulWidget {
  /// 后端 disable_in（禁用到期时间，ISO8601 / 'yyyy-MM-dd HH:mm:ss'）
  final String disableIn;

  const _RemainCountdown({required this.disableIn});

  @override
  State<_RemainCountdown> createState() => _RemainCountdownState();
}

class _RemainCountdownState extends State<_RemainCountdown> {
  Timer? _timer;
  DateTime? _target;
  String _text = '';

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _RemainCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ListView.builder 会把同一个 Element 复用给另一行 → 必须跟着换目标时间
    if (oldWidget.disableIn != widget.disableIn) _reset();
  }

  void _reset() {
    _timer?.cancel();
    // DateTime.parse 与 JS `new Date(str)` 一样按本地时区解析无时区后缀的串
    _target = DateTime.tryParse(widget.disableIn);
    _text = _formatRemainTime(_target);
    if (_target == null || _text == '00:00:00') return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final t = _formatRemainTime(_target);
      if (t == _text) return;
      setState(() => _text = t);
      // 归零后不再空转
      if (t == '00:00:00') _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_target == null) {
      // disable_in 非空但解析失败 = 后端给了非 ISO8601 值。
      // 这里**不能**回落成"永久禁用"（那是 disable_in 为空才成立的语义），
      // 否则会把临时禁用误报成永久。
      return const Text('开启剩余: --:--:--',
          style: TextStyle(fontSize: 11, color: Color(0xFFF56C6C)));
    }
    return Text('开启剩余: $_text',
        style: const TextStyle(fontSize: 11, color: Color(0xFFF56C6C)));
  }
}

// ===========================================================================
// 禁用时长选择子弹窗
// ===========================================================================

/// 选择禁用时长（对齐 web 两个弹窗内嵌的「选择禁用时长」el-dialog）。
///
/// 【为什么不用共享层 showDisableStartupModal，留痕】
/// 共享层 disable_startup_modal.dart 是**另一套语义**：永久/临时(天数) +
/// 全局/指定区域·IP 范围，而 `POST /startup/disable/{id}` 只认 `hours`。
/// web 这里是固定的小时档位单选（1/2/5/12/24/72/120 + 永久=0）。
/// 直接复用会把"天"当"小时"发（共享层 disable() 把 duration 原样当 hours），
/// 且多出的区域/IP 字段后端根本不接收。故 V2 单独实现本子弹窗，
/// 共享层那个继续给 V1 两个页面用，不动。
///
/// 返回值：小时数；0 = 永久；null = 取消。
class _DisableDurationDialog extends StatefulWidget {
  final String itemName;

  /// 「永久」档位是否可选（调用方按 isManager + 非强制开启 + 组归属判定）
  final bool allowPermanent;

  const _DisableDurationDialog({
    required this.itemName,
    required this.allowPermanent,
  });

  @override
  State<_DisableDurationDialog> createState() => _DisableDurationDialogState();
}

class _DisableDurationDialogState extends State<_DisableDurationDialog> {
  static const _options = <({int hours, String label})>[
    (hours: 1, label: '一小时'),
    (hours: 2, label: '两小时'),
    (hours: 5, label: '五小时'),
    (hours: 12, label: '十二小时'),
    (hours: 24, label: '一天'),
    (hours: 72, label: '三天'),
    (hours: 120, label: '五天'),
  ];

  int _selected = 1;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '选择禁用时长',
      maxWidth: 420,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.itemName,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          for (final o in _options) _radio(o.hours, o.label),
          if (widget.allowPermanent) _radio(0, '永久'),
          if (_selected > 0)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF0F9FF),
                border: Border(
                    left: BorderSide(color: AppColors.iosBlue, width: 3)),
              ),
              child: Text('将在 $_selected 小时后自动恢复启用',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.iosBlue)),
            ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(_selected),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 手写单选圈：Radio 的 groupValue/onChanged 在 Flutter 3.38 已标记 deprecated，
  /// 且共享层 disable_startup_modal 也是手写圈，保持一致。
  Widget _radio(int hours, String label) {
    final selected = _selected == hours;
    return InkWell(
      onTap: () => setState(() => _selected = hours),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.iosBlue : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppColors.iosBlue),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: selected ? AppColors.iosBlue : const Color(0xFF1F2937),
                )),
          ],
        ),
      ),
    );
  }
}
