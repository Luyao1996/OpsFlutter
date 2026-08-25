import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../monitor/data/terminal_api.dart';
import '../data/game_constants.dart';
import '../data/image_manage_api.dart';
import '../data/image_manage_logic.dart';
import 'widgets/config_image_dialog.dart';

/// 镜像管理内容视图（嵌入式 Widget，不带 Dialog 外壳）——
/// 对标 web ImageManageDialog.vue + useImageManage.js。
/// 用作终端详情页的 Tab 内容，父级通过 [isFullscreen]/[onToggleFullscreen]
/// 控制"应用内全屏"（与 GameManageView 同构）。
class ImageManageView extends ConsumerStatefulWidget {
  final int merchantId;
  final String subdomainFull;
  final String netbarName;

  /// 进入时预填的机号筛选（终端详情页传当前终端机号）
  final String? initialKeyword;

  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  const ImageManageView({
    super.key,
    required this.merchantId,
    required this.subdomainFull,
    required this.netbarName,
    this.initialKeyword,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });

  @override
  ConsumerState<ImageManageView> createState() => _ImageManageViewState();
}

/// 表格行：终端列表（机号/IP/MAC/在线）左连接镜像配置（4 槽）
class _ImageRow {
  final String id;
  final String name;
  final bool online;
  final String ip;
  final String mac;
  final List<SlotView> slots;

  /// 无盘平台上查不到这个机号 = 没接入无盘系统，配镜像必然失败（502 未找到编号）
  final bool manageable;

  const _ImageRow({
    required this.id,
    required this.name,
    required this.online,
    required this.ip,
    required this.mac,
    required this.slots,
    required this.manageable,
  });
}

class _ImageManageViewState extends ConsumerState<ImageManageView> {
  late final ImageManageApi _api = ImageManageApi(widget.subdomainFull);

  bool _loading = false;
  bool _hasLoadedOnce = false;
  String _error = '';
  List<String> _warnings = const [];

  Map<String, List<DiskImage>> _imagesByPlatform = {};
  final Map<String, Map<String, ClientCfg>> _clientsByPlatform = {};
  List<String> _availablePlatforms = const [];
  String _platform = '';

  List<Terminal> _terminals = const [];

  final _searchCtrl = TextEditingController();
  Timer? _keywordTimer;
  String _keywordApplied = '';
  int? _filterDiskId;
  String _filterOnline = ''; // '' / 'online' / 'offline'

  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    final kw = widget.initialKeyword?.trim() ?? '';
    if (kw.isNotEmpty) {
      _searchCtrl.text = kw;
      _keywordApplied = kw.toLowerCase();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  @override
  void dispose() {
    _keywordTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ===== 派生数据 =====

  List<DiskImage> get _images => _imagesByPlatform[_platform] ?? const [];

  Map<int, DiskImage> get _imageIndex =>
      {for (final img in _images) img.diskId: img};

  Map<String, ClientCfg> get _cfgMap => _clientsByPlatform[_platform] ?? const {};

  bool get _showPlatformSwitch => _availablePlatforms.length > 1;

  List<_ImageRow> _buildRows() {
    final cfgMap = _cfgMap;
    final imageIndex = _imageIndex;
    final seen = <String>{};

    // 挂着 plan 时 rows 就是当前生效的临时镜像，到期时间跟着一起展示
    List<SlotView> buildSlots(ClientCfg? cfg) =>
        buildSlotViews(cfg?.rows, imageIndex, cfg?.restoreTime ?? 0);

    final out = <_ImageRow>[];
    for (final t in _terminals) {
      // 服务端不进客户机镜像表（对应 web 的 !s.ServerChannel）
      if (t.mode == 1 || t.mode == 2 || t.type == 'server') continue;
      final id = t.seatId;
      if (id.isEmpty) continue;
      seen.add(id);
      final cfg = cfgMap[id];
      out.add(_ImageRow(
        id: id,
        name: t.name.isNotEmpty ? t.name : id,
        online: t.status > 0,
        ip: t.ip.isNotEmpty ? t.ip : (cfg?.ip ?? ''),
        mac: t.mac,
        slots: buildSlots(cfg),
        manageable: cfg != null,
      ));
    }

    // 无盘平台上有、但终端列表里没有的机器（未装 toolbox agent）也要能配，避免漏机
    for (final cfg in cfgMap.values) {
      if (seen.contains(cfg.seat)) continue;
      out.add(_ImageRow(
        id: cfg.seat,
        name: cfg.seat,
        online: false,
        ip: cfg.ip,
        mac: '',
        slots: buildSlots(cfg),
        manageable: true,
      ));
    }
    return out;
  }

  List<_ImageRow> _filteredRows() {
    final kw = _keywordApplied;
    return _buildRows().where((r) {
      if (kw.isNotEmpty &&
          !r.id.toLowerCase().contains(kw) &&
          !r.name.toLowerCase().contains(kw)) {
        return false;
      }
      if (_filterOnline == 'online' && !r.online) return false;
      if (_filterOnline == 'offline' && r.online) return false;
      final diskId = _filterDiskId;
      if (diskId != null) {
        final cfg = _cfgMap[r.id];
        final hit = (cfg?.rows ?? const []).any((row) => row.diskId == diskId);
        if (!hit) return false;
      }
      return true;
    }).toList(growable: false);
  }

  // ===== 数据拉取（对标 useImageManage） =====

  Future<void> _refreshAll() async {
    if (widget.subdomainFull.isEmpty) return;
    setState(() => _loading = true);
    try {
      // 终端列表与镜像列表互不依赖可并行；clientcfg 依赖前者定下的 platform
      await Future.wait([_fetchTerminals(), _fetchImages()]);
      await _fetchClientCfg();
    } catch (e) {
      if (mounted && _error.isEmpty) setState(() => _error = '请求异常：$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasLoadedOnce = true;
        });
      }
    }
  }

  /// 终端列表提供机号/IP/MAC/在线快照；拉失败不阻断（cfg 侧机器仍可配）
  Future<void> _fetchTerminals() async {
    try {
      final api = ref.read(terminalApiProvider);
      final list = await api.getAll(merchantId: widget.merchantId);
      if (!mounted) return;
      setState(() => _terminals = list);
    } catch (_) {
      // 保留上一次快照
    }
  }

  Future<void> _fetchImages() async {
    final res = await _api.getImageInfo();
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        _error = humanizeCfgError(res.error ?? 'HTTP ${res.status}');
        _imagesByPlatform = {};
        _availablePlatforms = const [];
      });
      return;
    }

    final entries = extractPlatformEntries(res.data);
    final nextImages = <String, List<DiskImage>>{};
    final nextWarnings = <String>[];
    final nextPlatforms = <String>[];
    for (final e in entries) {
      nextImages[e.platform] = normalizeImages(e.data);
      final w = e.data['warnings'];
      if (w is List) nextWarnings.addAll(w.map((x) => x.toString()));
      // 平台启用但一个镜像都没有仍算「可用」——应让用户看到空列表而非当成平台不可用
      nextPlatforms.add(e.platform);
    }

    setState(() {
      _imagesByPlatform = nextImages;
      _warnings = nextWarnings;
      _availablePlatforms = nextPlatforms;
      if (nextPlatforms.isEmpty) {
        _error = '未检测到已启用的无盘平台（网维大师 / 云更新）';
        _platform = '';
      } else {
        _error = '';
        if (!nextPlatforms.contains(_platform)) _platform = nextPlatforms.first;
      }
    });
  }

  Future<void> _fetchClientCfg() async {
    if (_platform.isEmpty) {
      setState(() => _clientsByPlatform.clear());
      return;
    }
    // 带 platform 单查：不传会遍历白名单，两个平台都启用时白拉一倍数据
    final res = await _api.getClientCfg(platform: _platform);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        // 镜像列表已经拿到时不覆盖 error —— 客户机配置拉失败只影响表格，页面仍可用
        if (_error.isEmpty) {
          _error = humanizeCfgError(res.error ?? 'HTTP ${res.status}');
        }
        _clientsByPlatform[_platform] = {};
      });
      return;
    }
    Map<String, ClientCfg> next = {};
    for (final e in extractPlatformEntries(res.data)) {
      if (e.platform == _platform) {
        next = normalizeClientRows(e.data);
        break;
      }
    }
    setState(() => _clientsByPlatform[_platform] = next);
  }

  Future<void> _switchPlatform(String next) async {
    if (!kDisklessPlatforms.contains(next) || next == _platform) return;
    setState(() {
      _platform = next;
      // 评审 M5：web 切平台不清 diskId 筛选/勾选是 bug，此处不复刻 ——
      // disk_id 是平台专属 id，勾选集合跨平台 manageable 口径也不同；
      // 关键词/在线筛选保留
      _filterDiskId = null;
      _selected.clear();
      _loading = true;
    });
    try {
      await _fetchClientCfg();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 保存成功后逐台回拉该 seat 的 clientcfg 刷新行，不全刷（vue:416-419）
  Future<void> _refreshSeats(List<String> seats) async {
    if (_platform.isEmpty) return;
    final platform = _platform;
    await Future.wait(seats.map((seat) async {
      final res = await _api.getClientCfg(platform: platform, seat: seat);
      if (!res.ok || !mounted) return;
      Map<String, ClientCfg>? rows;
      for (final e in extractPlatformEntries(res.data)) {
        if (e.platform == platform) {
          rows = normalizeClientRows(e.data);
          break;
        }
      }
      if (rows == null || !mounted) return;
      setState(() {
        final cur = _clientsByPlatform[platform] ?? {};
        _clientsByPlatform[platform] = {...cur, ...rows!};
      });
    }));
  }

  // ===== 筛选 =====

  void _onKeywordChanged(String v) {
    // 立即 setState 只为刷新清除按钮显隐；全表筛选走防抖
    setState(() {});
    _keywordTimer?.cancel();
    // 250ms 防抖，避免每敲一个字符重算一遍全表；回车立即应用
    _keywordTimer = Timer(const Duration(milliseconds: 250), _applyKeyword);
  }

  void _applyKeyword() {
    _keywordTimer?.cancel();
    if (!mounted) return;
    setState(() => _keywordApplied = _searchCtrl.text.trim().toLowerCase());
  }

  // ===== 配置弹窗 =====

  void _openSingleConfig(_ImageRow row) {
    _openConfig([(id: row.id, name: row.name)]);
  }

  void _openBatchConfig() {
    // 只带仍是 manageable 的选中项：刷新后机器可能已不在无盘平台上
    final rows = _buildRows()
        .where((r) => r.manageable && _selected.contains(r.id))
        .toList(growable: false);
    if (rows.isEmpty) return;
    _openConfig([for (final r in rows) (id: r.id, name: r.name)]);
  }

  void _openConfig(List<({String id, String name})> seats) {
    if (_platform.isEmpty) return;
    ConfigImageDialog.show(
      context,
      api: _api,
      platform: _platform,
      seats: seats,
      images: _images,
      clientCfgMap: _cfgMap,
      onSaved: (okSeats) => _refreshSeats(okSeats),
    );
  }

  // ===== 构建 =====

  @override
  Widget build(BuildContext context) {
    if (widget.subdomainFull.isEmpty) {
      return const Center(
        child: Text(
          '当前网吧域名为空，无法访问镜像管理',
          style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
      );
    }
    final isNarrow = MediaQuery.of(context).size.width < 720;
    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        children: [
          if (!isNarrow) _buildHeader(),
          if (!isNarrow) const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Expanded(
            child: Padding(
              padding:
                  EdgeInsets.fromLTRB(isNarrow ? 10 : 16, 10, isNarrow ? 10 : 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error.isNotEmpty) _buildErrorBanner(),
                  if (_warnings.isNotEmpty) _buildWarningsBanner(),
                  if (_platform.isNotEmpty) _buildImagesStrip(),
                  const SizedBox(height: 8),
                  _buildToolbar(isNarrow: isNarrow),
                  const SizedBox(height: 8),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.netbarName.isEmpty
                          ? widget.subdomainFull
                          : widget.netbarName,
                      style:
                          const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  '镜像管理',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          if (_showPlatformSwitch) ...[
            _buildPlatformSwitch(),
            const SizedBox(width: 8),
          ],
          _buildRefreshButton(),
          if (widget.onToggleFullscreen != null) _buildFullscreenButton(),
        ],
      ),
    );
  }

  Widget _buildRefreshButton() {
    return IconButton(
      tooltip: _loading ? '刷新中…' : '刷新',
      onPressed: _loading ? null : _refreshAll,
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.refreshCw, size: 16),
      color: AppColors.iosBlue,
    );
  }

  Widget _buildFullscreenButton() {
    return IconButton(
      tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
      onPressed: widget.onToggleFullscreen,
      icon: Icon(
        widget.isFullscreen ? LucideIcons.minimize2 : LucideIcons.maximize2,
        size: 16,
      ),
      color: AppColors.iosBlue,
    );
  }

  /// 两个无盘平台都启用时才需要让用户手动切（分段按钮）
  Widget _buildPlatformSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final p in _availablePlatforms)
            InkWell(
              onTap: () => _switchPlatform(p),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: p == _platform ? AppColors.iosBlue : Colors.transparent,
                child: Text(
                  kPlatformLabel[p] ?? p,
                  style: TextStyle(
                    fontSize: 12,
                    color: p == _platform ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _error,
        style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
      ),
    );
  }

  Widget _buildWarningsBanner() {
    return Tooltip(
      message: _warnings.join('\n'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '${_warnings.length} 条镜像详情拉取告警（悬停查看）',
          style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
        ),
      ),
    );
  }

  /// 服务器上的镜像：镜像名 chip 条，悬停看路径与配置节
  Widget _buildImagesStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '服务器上的镜像',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
        ),
        const SizedBox(height: 6),
        if (_images.isEmpty)
          const Text('该平台暂无镜像',
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final img in _images)
                Tooltip(
                  message: [
                    if (img.path.isNotEmpty) img.path,
                    img.sections.isEmpty
                        ? '无配置节'
                        : '配置节点：${img.sections.map((s) => s.name).join('、')}',
                  ].join('\n'),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.hardDrive,
                            size: 13, color: Color(0xFF0891B2)),
                        const SizedBox(width: 5),
                        Text(img.name,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildToolbar({required bool isNarrow}) {
    final searchField = TextField(
      controller: _searchCtrl,
      onChanged: _onKeywordChanged,
      onSubmitted: (_) => _applyKeyword(),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: '请输入机号查询...',
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
        prefixIcon: const Icon(LucideIcons.search, size: 14),
        prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(LucideIcons.x, size: 12),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  _searchCtrl.clear();
                  _applyKeyword();
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      ),
    );

    // 镜像下拉的 value 兜底：刷新后镜像可能已不在列表里，避免 Dropdown 断言崩溃
    final diskValue = _images.any((img) => img.diskId == _filterDiskId)
        ? _filterDiskId
        : null;

    final filterChildren = <Widget>[
      _dropdown<int>(
        value: diskValue,
        hint: '选择镜像',
        items: [
          const DropdownMenuItem(value: 0, child: Text('全部镜像')),
          // diskId<=0 的脏数据会与「全部镜像」撞 value 触发 Dropdown 断言，滤掉
          for (final img in _images)
            if (img.diskId > 0)
              DropdownMenuItem(value: img.diskId, child: Text(img.name)),
        ],
        onChanged: (v) =>
            setState(() => _filterDiskId = (v == null || v == 0) ? null : v),
      ),
      _dropdown<String>(
        value: _filterOnline.isEmpty ? null : _filterOnline,
        hint: '在线状态',
        items: const [
          DropdownMenuItem(value: '', child: Text('全部')),
          DropdownMenuItem(value: 'online', child: Text('在线')),
          DropdownMenuItem(value: 'offline', child: Text('离线')),
        ],
        onChanged: (v) => setState(() => _filterOnline = v ?? ''),
      ),
    ];

    final batchButton = OutlinedButton(
      onPressed: _selected.isEmpty ? null : _openBatchConfig,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.iosBlue,
        side: BorderSide(
            color: _selected.isEmpty
                ? const Color(0xFFD1D5DB)
                : AppColors.iosBlue.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 34),
      ),
      child: Text(
        '批量编辑镜像${_selected.isNotEmpty ? '(${_selected.length})' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
    );

    if (!isNarrow) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 180, child: searchField),
          ...filterChildren,
          batchButton,
        ],
      );
    }

    // 手机端：第一行搜索 + 刷新 + 全屏；第二行筛选与批量按钮（+ 平台切换）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 6),
            SizedBox(width: 40, height: 40, child: _buildRefreshButton()),
            if (widget.onToggleFullscreen != null)
              SizedBox(width: 40, height: 40, child: _buildFullscreenButton()),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_showPlatformSwitch) _buildPlatformSwitch(),
            ...filterChildren,
            batchButton,
          ],
        ),
      ],
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 12)),
          items: items,
          onChanged: onChanged,
          isDense: true,
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          icon: const Icon(LucideIcons.chevronDown, size: 12),
        ),
      ),
    );
  }

  // ===== 列表 =====

  Widget _buildBody() {
    if (_loading && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_hasLoadedOnce && _availablePlatforms.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.hardDrive, size: 28, color: Color(0xFF9CA3AF)),
            SizedBox(height: 8),
            Text(
              '未检测到已启用的无盘平台（网维大师 / 云更新）',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      );
    }

    final rows = _filteredRows();
    if (rows.isEmpty) {
      return Center(
        child: Text(
          _hasLoadedOnce ? '暂无客户机' : '加载中…',
          style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
        ),
      );
    }

    // ListView.builder 直渲（评审 M6）：builder 天然虚拟化，无需 web 的触底加载分页
    return LayoutBuilder(
      builder: (context, cons) {
        if (cons.maxWidth < 500) return _buildCardList(rows);
        final tableWidth = cons.maxWidth < 940 ? 940.0 : cons.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _buildTableHeader(),
                Expanded(child: _buildWideList(rows)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _countFooter(int total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          '共 $total 台',
          style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
        ),
      ),
    );
  }

  static const _headStyle = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280));

  Widget _buildTableHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: const Row(
        children: [
          SizedBox(width: 40),
          Expanded(flex: 3, child: Text('客户机名称', style: _headStyle)),
          SizedBox(width: 110, child: Text('IP地址', style: _headStyle)),
          SizedBox(width: 150, child: Text('MAC地址', style: _headStyle)),
          Expanded(
              flex: 5,
              child: Text('已配置镜像 / 配置点 / 临时镜像时间', style: _headStyle)),
          SizedBox(width: 240, child: Text('虚拟安全', style: _headStyle)),
          SizedBox(width: 96, child: Text('操作', style: _headStyle)),
        ],
      ),
    );
  }

  Widget _buildWideList(List<_ImageRow> rows) {
    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (context, idx) {
        if (idx == rows.length) return _countFooter(rows.length);
        final row = rows[idx];
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: 40, child: _buildRowCheckbox(row)),
              Expanded(flex: 3, child: _buildNameCell(row)),
              SizedBox(
                width: 110,
                child: Text(row.ip,
                    style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ),
              SizedBox(
                width: 150,
                child: Text(row.mac,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
              ),
              Expanded(flex: 5, child: _buildSlotsCell(row)),
              SizedBox(width: 240, child: _buildVsCell(row)),
              SizedBox(width: 96, child: Center(child: _buildConfigButton(row))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardList(List<_ImageRow> rows) {
    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (context, idx) {
        if (idx == rows.length) return _countFooter(rows.length);
        final row = rows[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: AppShadows.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildRowCheckbox(row),
                  const SizedBox(width: 4),
                  Expanded(child: _buildNameCell(row)),
                  _buildConfigButton(row),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _buildSlotsCell(row, compact: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRowCheckbox(_ImageRow row) {
    // 没接入无盘系统的机器不给勾：批量提交必然失败，混在里面只会让人以为整批出问题
    return SizedBox(
      width: 32,
      height: 32,
      child: Checkbox(
        value: _selected.contains(row.id),
        onChanged: !row.manageable
            ? null
            : (v) => setState(() {
                  if (v == true) {
                    _selected.add(row.id);
                  } else {
                    _selected.remove(row.id);
                  }
                }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        activeColor: AppColors.iosBlue,
      ),
    );
  }

  Widget _buildNameCell(_ImageRow row) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: row.online ? const Color(0xFF22C55E) : const Color(0xFFD1D5DB),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            row.name,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildSlotsCell(_ImageRow row, {bool compact = false}) {
    // 区分「接入了但没配镜像」和「压根没接入无盘」，后者点配置必然失败
    if (!row.manageable) {
      return const Text('未接入无盘系统',
          style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)));
    }
    if (row.slots.isEmpty) {
      return const Text('未配置',
          style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in row.slots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Icon(LucideIcons.hardDrive,
                    size: 13, color: Color(0xFF0891B2)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    slot.imageName,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(slot.sectionName,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6B7280))),
                ),
                // 挂着临时镜像时才有：整台一个到期时间，只标在第一槽上
                if (slot.expireText.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '临时镜像到期时间，到点自动切回日常镜像',
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(slot.expireText,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFB45309))),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildVsCell(_ImageRow row) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slot in row.slots)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (final vs in kVsKeys) ...[
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: (slot.virtualSecurity[vs.key] ?? false)
                          ? const Color(0xFF0891B2)
                          : Colors.transparent,
                      border: Border.all(
                        color: (slot.virtualSecurity[vs.key] ?? false)
                            ? const Color(0xFF0891B2)
                            : const Color(0xFFD1D5DB),
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    vs.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: (slot.virtualSecurity[vs.key] ?? false)
                          ? const Color(0xFF374151)
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConfigButton(_ImageRow row) {
    final btn = OutlinedButton(
      onPressed: row.manageable ? () => _openSingleConfig(row) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.iosBlue,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
      ),
      child: const Text('配置镜像', style: TextStyle(fontSize: 12)),
    );
    if (row.manageable) return btn;
    return Tooltip(message: '该机器未接入无盘系统，无法配置镜像', child: btn);
  }
}
