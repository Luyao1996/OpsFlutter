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
        // 用户反馈 #5：私有策略编辑态也要能改「生效网吧」。
        // 该开关只有 V2 传 true，V1 两个旧页面不传 → 仍是 3 个页签、
        // 提交也不带 merchants[]（见 StartupConfigModal.allowMerchantEdit 注释）。
        // 公共策略本来就恒有该页签，传 true 对它没有额外影响。
        allowMerchantEdit: true,
        dialogWidth: _kFormDialogWidth,
        onSuccess: _fetch,
      ),
      routeName: '/dialog/startup-config',
    );
  }

  /// 新增（含占位行入口）：复用共享层 AddStartupItemModal。
  ///
  /// **私有策略**：[merchant] 为预选网吧；为 null 时先弹单选网吧选择器——
  /// AddStartupItemModal 私有形态沿用 V1 的"当前网吧"上下文（只吃一个 netbarId），
  /// 不先选会在保存时报「请先选择网吧」。
  ///
  /// **公共策略**：不弹前置选择器——表单里的「生效网吧」页签本身就是多选面板
  /// （T8c-2 新增），与 web 一致。
  Future<void> _addStrategy({MerchantBrief? merchant, TacticItem? template}) async {
    MerchantBrief? target = merchant;
    if (_isPrivate && target == null) {
      target = await showAdaptive<MerchantBrief>(
        context,
        (_) => _MerchantPickerDialog(api: _api, groupFileId: widget.groupFileId),
        routeName: '/dialog/v2-strategy-merchant-picker',
      );
      if (target == null || !mounted) return;
    }
    final perm = ref.read(permissionProvider);
    await showAdaptive<void>(
      context,
      (_) => AddStartupItemModal(
        // 【留痕】zone 是 AddStartupItemModal 的死参数（全文件无 widget.zone 引用），
        // 传值仅为满足 required；V2 没有 zone 概念。
        zone: 'BRANCH',
        // 公共策略不吃 netbarId（生效网吧走表单内多选）
        netbarId: target?.id,
        isAdmin: perm.isManager,
        template: template,
        variant:
            _isPrivate ? StrategyVariant.private : StrategyVariant.public,
        exePicker: _exePicker(),
        dialogWidth: _kFormDialogWidth,
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
  /// 【对 web 的偏离，留痕】web 复制后可在弹窗里重选生效网吧（可多选）；
  /// Flutter **私有策略**沿用 V1 的单网吧上下文，故先弹单选网吧选择器
  /// （私有策略本来就一条策略只归属一家网吧，多选只影响"一次建多条"的便利性）。
  /// **公共策略**复制走表单内的「生效网吧」多选面板，并预选模板原有的生效网吧，
  /// 与 web 一致。
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

  /// 顶部工具条统一控件高度（用户反馈 #2）。
  ///
  /// 原来输入框/下拉写死 34，而旁边 OutlinedButton 走 M3 默认 minimumSize
  /// （高 40）→ 输入框明显比按钮矮一截。这里把**三者都钉死同一个值**，
  /// 不再依赖 M3 默认高度（换主题/换 visualDensity 也不会重新错位）。
  static const double _kToolbarControlHeight = 40;

  Widget _buildHeader(bool isNarrow) {
    final perm = ref.watch(permissionProvider);
    // 按钮统一高度：minimumSize 只管下限，还要 padding 不把高度顶上去
    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, _kToolbarControlHeight),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final typeDropdown = SizedBox(
      width: 130,
      height: _kToolbarControlHeight,
      child: DropdownButtonFormField<String>(
        initialValue: _type,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
        items: [
          for (final o in _spec.typeOptions)
            DropdownMenuItem(
              value: o.value,
              child: Text(o.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _type = v);
        },
      ),
    );

    final hintByType = {
      'merchant': '请输入网吧名称',
      'group': '请输入分组名称',
      'file': '请输入程序名称',
    };

    final searchField = SizedBox(
      height: _kToolbarControlHeight,
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: hintByType[_type] ?? '请输入关键字',
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          // isDense + 零纵向 padding：让 SizedBox 的 40 完全决定高度，
          // 文本在其中垂直居中，与按钮齐平
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          border: const OutlineInputBorder(),
        ),
      ),
    );

    // T8c-2：两个 variant 的新增都已接通（共享层表单按 variant 分流
    // merchants 键形与保存端点），不再置灰。
    final addButton = OutlinedButton.icon(
      onPressed: () => _addStrategy(),
      style: buttonStyle,
      icon: const Icon(LucideIcons.plus, size: 14),
      label: const Text('添加', style: TextStyle(fontSize: 13)),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          typeDropdown,
          SizedBox(width: isNarrow ? 160 : 220, child: searchField),
          OutlinedButton(
            onPressed: _search,
            style: buttonStyle,
            child: const Text('搜索', style: TextStyle(fontSize: 13)),
          ),
          if (perm.isManager) addButton,
          SizedBox(
            height: _kToolbarControlHeight,
            child: IconButton(
              tooltip: '刷新',
              onPressed: _fetch,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: _kToolbarControlHeight,
                  minHeight: _kToolbarControlHeight),
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

  /// 分页条（用户反馈 #1：右下角 `RIGHT OVERFLOWED BY 6.9 PIXELS`）。
  ///
  /// 原实现是 `Row + Spacer`：Row 不会收缩，两个 IconButton 各带 48x48 的默认
  /// minimumSize，加上 90 宽的每页下拉，在窄一点的容器里必然把行撑爆。
  /// 改为：
  ///   1. 外层 Wrap(spaceBetween)——放得下时左右分列，放不下就整块换行；
  ///   2. 右侧控件自己也是 Wrap，可以继续折行；
  ///   3. 两个翻页 IconButton 去掉 48x48 默认约束，压到 32x32。
  Widget _buildPagination(bool isNarrow) {
    final pageCount = _perPage <= 0 ? 1 : ((_total + _perPage - 1) ~/ _perPage);
    final maxPage = pageCount < 1 ? 1 : pageCount;

    Widget pageButton(IconData icon, VoidCallback? onPressed) => IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 18,
        );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text('共 $_total 条',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 6,
          children: [
            if (!isNarrow)
              SizedBox(
                width: 96,
                height: 32,
                child: DropdownButtonFormField<int>(
                  initialValue: _perPage,
                  isDense: true,
                  // 不加 isExpanded 时 DropdownButton 按最宽 item 的固有宽度撑开，
                  // 会顶破外面的 SizedBox
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8),
                    border: OutlineInputBorder(),
                  ),
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
                  items: const [
                    DropdownMenuItem(
                        value: 10,
                        child: Text('10 条/页',
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(
                        value: 20,
                        child: Text('20 条/页',
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(
                        value: 50,
                        child: Text('50 条/页',
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    _perPage = v;
                    _page = 1;
                    _fetch();
                  },
                ),
              ),
            pageButton(
              LucideIcons.chevronLeft,
              _page > 1
                  ? () {
                      _page--;
                      _fetch();
                    }
                  : null,
            ),
            Text('$_page / $maxPage',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF1F2937))),
            pageButton(
              LucideIcons.chevronRight,
              _page < maxPage
                  ? () {
                      _page++;
                      _fetch();
                    }
                  : null,
            ),
          ],
        ),
      ],
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

// ===========================================================================
// 生效网吧选择器（新增/复制前置步骤）
// ===========================================================================

/// 单选网吧。数据源 GET /tactic/merchants（T8c-0 已实现，全量无分页）。
///
/// 【存在的理由，留痕】共享层 AddStartupItemModal 的**私有**形态是 V1 的
/// "当前网吧"上下文产物，只接受一个 netbarId；V2 弹窗里没有当前网吧，
/// 不先选会在保存时直接报「请先选择网吧」。
///
/// 【本次（用户反馈 #5）的处理范围，留痕】只给**编辑态**
/// （StartupConfigModal + allowMerchantEdit）补了私有策略的「生效网吧」多选面板；
/// **新增态**没动，故私有新增仍走本前置单选器。
/// 结果是"新增只能一次建一家、编辑可改成多家"——与 web 私有弹窗
/// （LocalStrategyAdd.vue 新增/编辑共用同一个多选面板）仍有差距，
/// 待编辑态的 merchants 提交经后端验证跑通后再统一。
class _MerchantPickerDialog extends StatefulWidget {
  final StrategyApi api;
  final int? groupFileId;

  const _MerchantPickerDialog({required this.api, this.groupFileId});

  @override
  State<_MerchantPickerDialog> createState() => _MerchantPickerDialogState();
}

class _MerchantPickerDialogState extends State<_MerchantPickerDialog> {
  final TextEditingController _kw = TextEditingController();
  List<MerchantBrief> _all = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.getTacticMerchants(
        groupFileId: widget.groupFileId,
      );
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = v2ErrMessage(e, '获取网吧列表失败');
        _loading = false;
      });
    }
  }

  List<MerchantBrief> get _filtered {
    final q = _kw.text.trim();
    if (q.isEmpty) return _all;
    return _all.where((m) => m.name.contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return ResponsiveDialogScaffold(
      title: '选择生效网吧',
      maxWidth: 460,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _kw,
                style: const TextStyle(fontSize: 13),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '搜索网吧名称',
                  hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: Text('加载中...',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF9CA3AF))))
                : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.red)))
                    : list.isEmpty
                        ? const Center(
                            child: Text('无匹配网吧',
                                style: TextStyle(
                                    fontSize: 13, color: Color(0xFF9CA3AF))))
                        // 网吧数量可能上千 → 虚拟化
                        : ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final m = list[i];
                              final groups = m.groups
                                      ?.map((g) => g.name)
                                      .where((n) => n.isNotEmpty)
                                      .join('、') ??
                                  '';
                              return ListTile(
                                dense: true,
                                title: Text(m.name,
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  '终端数 ${m.terminalCount}'
                                  '${groups.isEmpty ? '' : ' · $groups'}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF9CA3AF)),
                                ),
                                onTap: () => Navigator.of(context).pop(m),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
