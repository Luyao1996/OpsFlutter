import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/permission_provider.dart';
import '../../../shared/utils/top_notice.dart';
import '../../netbar/data/netbar_list_provider.dart';
import '../data/channel_v2_api.dart';
import '../data/channel_v2_models.dart';
import 'channel_v2_controllers.dart';
import 'widgets/distribution_zone.dart';
import 'widgets/resource_zone.dart';

/// 通道管理 V2（T8a：双区只读浏览 + 可扩展骨架，对齐 web ChannelV2Page.vue）。
/// 与旧 channel feature 新旧并存，互不 import。
class ChannelV2Page extends ConsumerStatefulWidget {
  const ChannelV2Page({super.key});

  @override
  ConsumerState<ChannelV2Page> createState() => _ChannelV2PageState();
}

class _ChannelV2PageState extends ConsumerState<ChannelV2Page> {
  late final ChannelV2PageController _ctrl;

  /// inline 重命名入口预埋（T8b 经此调 startEditing，对齐 vue hqZoneRef/groupZoneRef）
  final _hqZoneKey = GlobalKey<ResourceZoneState>();
  final _groupZoneKey = GlobalKey<ResourceZoneState>();

  /// HQ 账号的组下拉选择（小组账号固定自己组不可切）
  int? _selectedGroupId;

  /// 窄屏分段：'distribution' | 'hq' | 'group'
  String _narrowSegment = 'distribution';

  @override
  void initState() {
    super.initState();
    _ctrl = ChannelV2PageController(api: ref.read(channelV2ApiProvider));

    void showErr(String m) {
      if (mounted) showTopNotice(context, m, level: NoticeLevel.error);
    }

    _ctrl.hq.onError = showErr;
    _ctrl.group.onError = showErr;
    _ctrl.distribution.filesCtrl.onError = showErr;

    _ctrl.hq.addListener(_onCtrlChanged);
    _ctrl.group.addListener(_onCtrlChanged);
    _ctrl.hqSel.addListener(_onCtrlChanged);
    _ctrl.groupSel.addListener(_onCtrlChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initZones());
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  /// 初次加载（对齐 ChannelV2Page.vue onMounted:262-270,301-305）
  Future<void> _initZones() async {
    if (!mounted) return;
    final perm = ref.read(permissionProvider);
    if (perm.isHQUser) {
      _ctrl.hq.refresh();
      await _restoreGroupPref();
    } else {
      // 小组账号：固定自己组；setGroupId 内部回根并刷新
      _ctrl.group.setGroupId(perm.groupId);
    }
  }

  /// 组记忆按账号隔离。
  /// 【对 web 的刻意偏离，留痕】web 用全局 key 'channel_v2:last_group_id'
  /// （ChannelV2Page.vue:196），同机换账号会串记忆；Flutter 端 key 拼 userId。
  String _groupPrefKey(int userId) => 'channel_v2:last_group_id:$userId';

  Future<void> _restoreGroupPref() async {
    final userId = ref.read(authNotifierProvider).user?.id;
    if (userId == null) return;
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getInt(_groupPrefKey(userId));
    if (saved != null && mounted && _selectedGroupId == null) {
      setState(() => _selectedGroupId = saved);
      _ctrl.group.setGroupId(saved);
    }
  }

  Future<void> _saveGroupPref(int groupId) async {
    final userId = ref.read(authNotifierProvider).user?.id;
    if (userId == null) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_groupPrefKey(userId), groupId);
  }

  void _onGroupSelected(int? id) {
    if (id == null || id == _selectedGroupId) return;
    setState(() => _selectedGroupId = id);
    // 切组回根 + 刷新（竞态防护：ZoneFilesController 内 seq 丢弃晚到的旧组响应）
    _ctrl.group.setGroupId(id);
    _saveGroupPref(id);
  }

  @override
  void dispose() {
    _ctrl.hq.removeListener(_onCtrlChanged);
    _ctrl.group.removeListener(_onCtrlChanged);
    _ctrl.hqSel.removeListener(_onCtrlChanged);
    _ctrl.groupSel.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    super.dispose();
  }

  // ====== 右键菜单（T8a 只挂 刷新/属性占位） ======

  /// 当前区是否可写（空白菜单用；对齐 ChannelV2Page.vue:447-451 canWriteHere）
  bool _canWriteHere(String zoneKey) {
    final perm = ref.read(permissionProvider);
    if (!perm.isManager) return false;
    if (zoneKey == 'group' && _effectiveGroupId == null) return false;
    return true;
  }

  /// 文件级写权限（对齐 ChannelV2Page.vue:460-467 canWriteForFile：
  /// 非管理员拒绝；继承节点只读；canOperateGroupConfig 判组归属）
  bool _canWriteForFile(String zoneKey, V2File? file) {
    final perm = ref.read(permissionProvider);
    if (!perm.isManager) return false;
    if (file == null) return _canWriteHere(zoneKey);
    if (file.inherited) return false;
    return perm.canOperateGroupConfig(file.groupId);
  }

  List<V2File> _getSelectedFiles(String zoneKey, V2File? rightClicked) {
    if (zoneKey == 'hq') return _ctrl.hqSel.expandFromRightClick(rightClicked);
    if (zoneKey == 'group') {
      return _ctrl.groupSel.expandFromRightClick(rightClicked);
    }
    return _ctrl.distribution.expandFromRightClick(rightClicked);
  }

  Future<void> _openFileMenu(String zoneKey, V2File file, Offset pos) async {
    final items = buildContextMenuItems(
      zoneKey: zoneKey,
      file: file,
      isBlank: false,
      writableHere: _canWriteHere(zoneKey),
      writableFile: _canWriteForFile(zoneKey, file),
      batchFiles: _getSelectedFiles(zoneKey, file),
      viewMode: 'grid',
    );
    final key = await _showContextMenu(pos, items);
    _handleMenuAction(zoneKey, key);
  }

  Future<void> _openBlankMenu(String zoneKey, Offset pos) async {
    final items = buildContextMenuItems(
      zoneKey: zoneKey,
      file: null,
      isBlank: true,
      writableHere: _canWriteHere(zoneKey),
      writableFile: false,
      batchFiles: const [],
      viewMode: 'grid',
    );
    final key = await _showContextMenu(pos, items);
    _handleMenuAction(zoneKey, key);
  }

  void _handleMenuAction(String zoneKey, String? key) {
    if (key == null) return;
    switch (key) {
      case 'refresh':
        _ctrl.refreshZone(zoneKey);
        break;
      // 'properties' T8a 置灰不可达；T8b 起在此接 PropsDialogSlot
    }
  }

  Future<String?> _showContextMenu(
      Offset globalPos, List<V2ContextMenuItem> items) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        overlay.size.width - globalPos.dx,
        overlay.size.height - globalPos.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        for (final it in items)
          if (it.divider)
            const PopupMenuDivider(height: 1)
          else
            PopupMenuItem<String>(
              value: it.key,
              enabled: !it.disabled,
              height: 36,
              child: Row(
                children: [
                  if (it.icon != null) ...[
                    Icon(
                      it.icon,
                      size: 15,
                      color: it.disabled
                          ? Colors.grey.shade400
                          : (it.danger ? AppColors.red : Colors.grey.shade700),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    it.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: it.disabled
                          ? Colors.grey.shade400
                          : (it.danger ? AppColors.red : const Color(0xFF1F2937)),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  // ====== 权限/账号派生 ======

  int? get _effectiveGroupId {
    final perm = ref.read(permissionProvider);
    if (perm.isHQUser) return _selectedGroupId;
    return perm.groupId;
  }

  @override
  Widget build(BuildContext context) {
    final perm = ref.watch(permissionProvider);
    final canSeeHqZone = perm.isHQUser;
    final canWriteHqZone = perm.isTopManager;
    // 对齐 vue canWriteGroupZone：总部账号按总部管理员、小组账号按管理员
    final canWriteGroupZone = perm.isHQUser ? perm.isTopManager : perm.isManager;
    _ctrl.canSeeHqZone = canSeeHqZone;
    final isNarrow = context.isNarrow;

    return Container(
      color: const Color(0xFFF0F2F5),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(context, isNarrow, canSeeHqZone),
          const SizedBox(height: 8),
          Expanded(
            child: isNarrow
                ? _buildNarrowBody(
                    context, perm, canSeeHqZone, canWriteHqZone, canWriteGroupZone)
                : _buildWideBody(
                    context, perm, canSeeHqZone, canWriteHqZone, canWriteGroupZone),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool isNarrow, bool canSeeHqZone) {
    return _card(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            const Icon(LucideIcons.layers, size: 16, color: Color(0xFF007AFF)),
            const SizedBox(width: 8),
            const Text(
              '通道管理V2',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937)),
            ),
            const Spacer(),
            // 搜索框与 grid/list 切换 T8a 不做（ResourceZone props 已预留
            // searchActive/matchedKeys；viewMode 待 T8b）
            IconButton(
              tooltip: '刷新',
              onPressed: _ctrl.refreshAll,
              icon: Icon(LucideIcons.refreshCw,
                  size: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // ====== 宽屏：左下发复合面板 + 右列（HQ 上 / Group 下） ======

  Widget _buildWideBody(BuildContext context, PermissionService perm,
      bool canSeeHqZone, bool canWriteHqZone, bool canWriteGroupZone) {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        // >=1200 右列固定 580；[900,1200) 按比例压缩，最小约 420
        final rightW =
            w >= 1200 ? 580.0 : (w * 0.45).clamp(420.0, 580.0).toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _card(DistributionZone(
                controller: _ctrl.distribution,
                isHqUser: perm.isHQUser,
                showTreeInline: true,
                onZoneActivate: () => _ctrl.activateZone('distribution'),
                onFileContextMenu: (f, pos) =>
                    _openFileMenu('distribution', f, pos),
                onBlankContextMenu: (pos) =>
                    _openBlankMenu('distribution', pos),
              )),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: rightW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (canSeeHqZone) ...[
                    Expanded(child: _card(_buildHqZone(canWriteHqZone))),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                      child: _card(_buildGroupZone(perm, canWriteGroupZone))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ====== 窄屏：三段分段切换 + 树改全屏弹窗选择 ======

  Widget _buildNarrowBody(BuildContext context, PermissionService perm,
      bool canSeeHqZone, bool canWriteHqZone, bool canWriteGroupZone) {
    final segments = <(String, String)>[
      ('distribution', '下发'),
      if (canSeeHqZone) ('hq', '总部资源'),
      ('group', '小组资源'),
    ];
    var seg = _narrowSegment;
    if (!segments.any((s) => s.$1 == seg)) seg = 'distribution';

    Widget body;
    if (seg == 'hq') {
      body = _buildHqZone(canWriteHqZone);
    } else if (seg == 'group') {
      body = _buildGroupZone(perm, canWriteGroupZone);
    } else {
      body = DistributionZone(
        controller: _ctrl.distribution,
        isHqUser: perm.isHQUser,
        showTreeInline: false,
        onZoneActivate: () => _ctrl.activateZone('distribution'),
        onFileContextMenu: (f, pos) => _openFileMenu('distribution', f, pos),
        onBlankContextMenu: (pos) => _openBlankMenu('distribution', pos),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              for (final s in segments)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _narrowSegment = s.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: seg == s.$1 ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: seg == s.$1 ? AppShadows.sm : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        s.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              seg == s.$1 ? FontWeight.w600 : FontWeight.normal,
                          color: seg == s.$1
                              ? const Color(0xFF1F2937)
                              : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _card(body)),
      ],
    );
  }

  // ====== 三个区 ======

  Widget _buildHqZone(bool canWriteHqZone) {
    return ResourceZone(
      key: _hqZoneKey,
      zoneKey: 'hq',
      title: '总部资源区',
      files: _ctrl.hq.files,
      loading: _ctrl.hq.loading,
      path: _ctrl.hq.path,
      readonly: !canWriteHqZone,
      emptyText: '总部资源区为空',
      selectedKeys: _ctrl.hqSel.keys,
      onFileTap: (f, {bool ctrl = false, bool shift = false}) {
        _ctrl.activateZone('hq');
        _ctrl.hqSel.onClick(f, ctrl: ctrl, shift: shift);
      },
      onFileDoubleTap: (f) {
        if (!f.isFolder) return;
        _ctrl.hq.enterFolder(f);
        _ctrl.hqSel.clear();
      },
      onBreadcrumbTap: _ctrl.hq.goTo,
      onBlankTap: _ctrl.hqSel.onBlankClick,
      onFileContextMenu: (f, pos) => _openFileMenu('hq', f, pos),
      onBlankContextMenu: (pos) => _openBlankMenu('hq', pos),
    );
  }

  Widget _buildGroupZone(PermissionService perm, bool canWriteGroupZone) {
    final isHq = perm.isHQUser;
    final groups = ref.watch(netbarListProvider).valueOrNull?.groups ?? const [];
    final groupEmptyText =
        (isHq && _selectedGroupId == null) ? '请选择小组' : '小组资源区为空';

    String groupZoneTitle() {
      // 小组账号标题（对齐 vue:100 '{组名} 小组资源区'；User 无 group_name 字段，
      // 从 netbarListProvider.groups 反查，查不到兜底 '本'——与 web 兜底一致）
      String name = '本';
      final gid = perm.groupId;
      for (final g in groups) {
        if (g.id == gid) {
          name = g.name;
          break;
        }
      }
      return '$name 小组资源区';
    }

    return ResourceZone(
      key: _groupZoneKey,
      zoneKey: 'group',
      title: isHq ? '' : groupZoneTitle(),
      titleBuilder: isHq
          ? (ctx) => DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: groups.any((g) => g.id == _selectedGroupId)
                      ? _selectedGroupId
                      : null,
                  hint: Text('请选择小组',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade500)),
                  isDense: true,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151)),
                  items: [
                    for (final g in groups)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  ],
                  onChanged: _onGroupSelected,
                ),
              )
          : null,
      files: _ctrl.group.files,
      loading: _ctrl.group.loading,
      path: _ctrl.group.path,
      readonly: !canWriteGroupZone,
      emptyText: groupEmptyText,
      selectedKeys: _ctrl.groupSel.keys,
      onFileTap: (f, {bool ctrl = false, bool shift = false}) {
        _ctrl.activateZone('group');
        _ctrl.groupSel.onClick(f, ctrl: ctrl, shift: shift);
      },
      onFileDoubleTap: (f) {
        if (!f.isFolder) return;
        _ctrl.group.enterFolder(f);
        _ctrl.groupSel.clear();
      },
      onBreadcrumbTap: _ctrl.group.goTo,
      onBlankTap: _ctrl.groupSel.onBlankClick,
      onFileContextMenu: (f, pos) => _openFileMenu('group', f, pos),
      onBlankContextMenu: (pos) => _openBlankMenu('group', pos),
    );
  }

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFEEF0F4)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
