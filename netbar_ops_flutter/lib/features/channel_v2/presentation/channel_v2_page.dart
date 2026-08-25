import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/permission_provider.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/utils/platform_utils.dart';
import '../../../shared/utils/top_notice.dart';
import '../../netbar/data/netbar_api.dart';
import '../../netbar/data/netbar_list_provider.dart';
import '../data/channel_v2_api.dart';
import '../data/channel_v2_models.dart';
import '../data/v2_upload_service.dart';
import 'channel_v2_controllers.dart';
import 'channel_v2_file_actions.dart';
import 'widgets/distribution_zone.dart';
import 'widgets/resource_zone.dart';
import 'widgets/v2_file_props_dialog.dart';
import 'widgets/v2_move_target_dialog.dart';
import 'widgets/v2_strategy_list_dialog.dart';
import 'widgets/v2_task_list_dialog.dart';
import 'widgets/v2_upload_dialog.dart';

/// 通道管理 V2（T8b-2：文件操作层，对齐 web ChannelV2Page.vue）。
/// 与旧 channel feature 新旧并存，互不 import。
class ChannelV2Page extends ConsumerStatefulWidget {
  const ChannelV2Page({super.key});

  @override
  ConsumerState<ChannelV2Page> createState() => _ChannelV2PageState();
}

class _ChannelV2PageState extends ConsumerState<ChannelV2Page> {
  late final ChannelV2PageController _ctrl;

  /// 各区独立的重建触发源（见 initState 注释）
  late final Listenable _hqListenable;
  late final Listenable _groupListenable;

  /// inline 重命名入口（对齐 vue hqZoneRef/groupZoneRef）
  final _hqZoneKey = GlobalKey<ResourceZoneState>();
  final _groupZoneKey = GlobalKey<ResourceZoneState>();

  /// HQ 账号的组下拉选择（小组账号固定自己组不可切）
  int? _selectedGroupId;

  /// 窄屏分段：'distribution' | 'hq' | 'group'
  String _narrowSegment = 'distribution';

  /// 顶栏视图模式（右键「视图切换」与工具栏按钮共用同一份状态）
  String _viewMode = 'grid';

  /// 顶栏搜索（三区联动，原地过滤，不改后端查询）
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  /// 快捷键宿主
  final FocusNode _pageFocus = FocusNode(debugLabel: 'channel_v2_page');

  /// 【统一「是否有弹窗打开」标志位】
  /// web 是 document 级监听 + 逐个弹窗 visible 判空（ChannelV2Page.vue:793-801），
  /// 弹窗一多就会漏判。这里改为计数器：任何弹窗/右键菜单打开期间自增，关闭自减，
  /// 快捷键只需判 `_anyDialogOpen`。T8c/T8d 新增弹窗必须走 [_guardDialog]。
  int _dialogDepth = 0;
  bool get _anyDialogOpen => _dialogDepth > 0;

  /// 解压防重复点击（同一文件连点会向后端投多份任务）
  bool _unzipping = false;

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

    // 【重建范围收窄】原先四个控制器都挂页面级 setState：任一区的选中/加载态变化
    // 都会重建整页（含另外两个区的全部文件卡）。改为各区只监听自己的两个控制器，
    // 由 ListenableBuilder 把重建圈在本区内。
    _hqListenable = Listenable.merge([_ctrl.hq, _ctrl.hqSel]);
    _groupListenable = Listenable.merge([_ctrl.group, _ctrl.groupSel]);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initZones());
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
    _ctrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  // ====== 通用出口 ======

  void _notice(String message, NoticeLevel level) {
    if (mounted) showTopNotice(context, message, level: level);
  }

  /// 所有弹窗/菜单必须经此包裹：维护 [_dialogDepth]，快捷键据此让路
  Future<T> _guardDialog<T>(Future<T> Function() run) async {
    _dialogDepth++;
    try {
      return await run();
    } finally {
      _dialogDepth--;
    }
  }

  ChannelV2Api get _api => ref.read(channelV2ApiProvider);

  // ====== 权限 ======

  /// 当前区是否可写（空白菜单用；对齐 ChannelV2Page.vue:447-451 canWriteHere）
  bool _canWriteHere(String zoneKey) {
    final perm = ref.read(permissionProvider);
    if (!perm.isManager) return false;
    if (zoneKey == 'group' && _effectiveGroupId == null) return false;
    return true;
  }

  /// 文件级写权限（对齐 ChannelV2Page.vue:460-467 canWriteForFile：
  /// 非管理员拒绝；继承节点只读；canOperateGroupConfig 判组归属）。
  ///
  /// 注意：这里的 inherited 判断只管**被右键的这一个文件**（决定菜单置灰），
  /// 批量集合里混进继承项要靠 [_blockIfInherited] 再拦一层，两者不是冗余。
  bool _canWriteForFile(String zoneKey, V2File? file) {
    final perm = ref.read(permissionProvider);
    if (!perm.isManager) return false;
    if (file == null) return _canWriteHere(zoneKey);
    if (file.inherited) return false;
    // 【S12 → T8c-2 已偿还，留痕】下发节点的 groupId 实际是 source_id：
    // sourceScope=='merchant' 时它是 merchant_id，喂给 canOperateGroupConfig
    // 比的却是 group_id（跨 id 空间，判定结果无意义）。T8b 一律置灰该类节点的写操作；
    // T8c-2 改为先把 merchant_id 还原成「所属组 id」再判权。
    // 映射源是 netbarListProvider（下发区左侧 scope 树本来就在用它，
    // 见 distribution_zone.dart:130-132 —— 能右键到下发文件说明该 provider 已有值，
    // 零额外请求）。**查不到映射时保持置灰**，只放宽能证明归属的情形。
    if (zoneKey == 'distribution' && file.sourceScope == 'merchant') {
      final ownerGroupIds = _merchantOwnerGroupIds(file.sourceId);
      if (ownerGroupIds.isEmpty) return false;
      return ownerGroupIds.any(perm.canOperateGroupConfig);
    }
    return perm.canOperateGroupConfig(file.groupId);
  }

  /// 网吧 → 所属组 id 集合（T8c-2）。
  /// 一家网吧可挂多个组，任一组有权即可写（与 canOperateGroupConfig 的"同组可操作"同义）。
  List<int> _merchantOwnerGroupIds(int? merchantId) {
    if (merchantId == null) return const [];
    final merchants =
        ref.read(netbarListProvider).valueOrNull?.merchants ?? const <Netbar>[];
    for (final m in merchants) {
      if (m.id == merchantId) {
        return (m.groups ?? const <GroupBrief>[]).map((g) => g.id).toList();
      }
    }
    return const [];
  }

  /// 继承节点批量守卫（移植 ChannelV2Page.vue:469-485），move/delete/unzip 三处调用
  bool _blockIfInherited(List<V2File> files, String action) {
    return v2BlockIfInherited(
      files,
      action: action,
      warn: (m) => _notice(m, NoticeLevel.warning),
    );
  }

  // ====== 选中集 ======

  List<V2File> _getSelectedFiles(String zoneKey, V2File? rightClicked) {
    if (zoneKey == 'hq') return _ctrl.hqSel.expandFromRightClick(rightClicked);
    if (zoneKey == 'group') {
      return _ctrl.groupSel.expandFromRightClick(rightClicked);
    }
    return _ctrl.distribution.expandFromRightClick(rightClicked);
  }

  void _clearSelection(String zoneKey) {
    if (zoneKey == 'hq') {
      _ctrl.hqSel.clear();
    } else if (zoneKey == 'group') {
      _ctrl.groupSel.clear();
    } else {
      _ctrl.distribution.clearSelection();
    }
  }

  // ====== 右键菜单 ======

  Future<void> _openFileMenu(String zoneKey, V2File file, Offset pos) async {
    final items = buildContextMenuItems(
      zoneKey: zoneKey,
      file: file,
      isBlank: false,
      writableHere: _canWriteHere(zoneKey),
      writableFile: _canWriteForFile(zoneKey, file),
      // 右键项已在选中集合里 → 批量；否则只它本身
      batchFiles: _getSelectedFiles(zoneKey, file),
      viewMode: _viewMode,
    );
    final key = await _showContextMenu(pos, items);
    await _handleMenuAction(zoneKey, key, file);
  }

  Future<void> _openBlankMenu(String zoneKey, Offset pos) async {
    final items = buildContextMenuItems(
      zoneKey: zoneKey,
      file: null,
      isBlank: true,
      writableHere: _canWriteHere(zoneKey),
      writableFile: false,
      batchFiles: const [],
      viewMode: _viewMode,
    );
    final key = await _showContextMenu(pos, items);
    await _handleMenuAction(zoneKey, key, null);
  }

  Future<void> _handleMenuAction(
      String zoneKey, String? key, V2File? file) async {
    if (key == null) return;
    switch (key) {
      case 'refresh':
        _ctrl.refreshZone(zoneKey);
        break;

      case 'view-toggle':
        setState(() => _viewMode = _viewMode == 'grid' ? 'list' : 'grid');
        break;

      case 'upload':
        _openUploadDialog(zoneKey: zoneKey);
        break;

      case 'distribute':
        await _distribute(_getSelectedFiles(zoneKey, file));
        break;

      case 'rename':
        if (file != null) _triggerInlineRename(file, zoneKey);
        break;

      case 'move':
        await _openMoveDialog(zoneKey, file);
        break;

      case 'delete':
        await _deleteFlow(zoneKey, file);
        break;

      case 'properties':
        if (file != null) await _openPropsDialog(file);
        break;

      case 'unzip':
        if (file != null) await _unzip(zoneKey, file);
        break;
    }
  }

  Future<String?> _showContextMenu(
      Offset globalPos, List<V2ContextMenuItem> items) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    return _guardDialog<String?>(() => showMenu<String>(
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
                              : (it.danger
                                  ? AppColors.red
                                  : const Color(0xFF1F2937)),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ));
  }

  // ====== 删除 ======

  Future<void> _deleteFlow(String zoneKey, V2File? file) async {
    final files = _getSelectedFiles(zoneKey, file);
    if (files.isEmpty) return;
    if (_blockIfInherited(files, '删除')) return;
    final ok = await _guardDialog<bool>(() async {
      if (files.length > 1) {
        return v2ConfirmAndBatchDelete(
          context,
          api: _api,
          files: files,
          zoneKey: zoneKey,
          notice: _notice,
        );
      }
      return v2ConfirmAndDelete(
        context,
        api: _api,
        file: files.first,
        zoneKey: zoneKey,
        notice: _notice,
      );
    });
    if (ok) {
      // S5：必须先清选中再刷新，否则被删项还留在 keys 里，
      // 下一次批量操作的 selectedFiles 会静默变短（用户以为还选着 N 项）
      _clearSelection(zoneKey);
      // 删除只刷本区（下发区的引用由后端 missing 标记表达，不必整页刷）
      _ctrl.refreshZone(zoneKey);
    }
  }

  // ====== 移动 ======

  Future<void> _openMoveDialog(String zoneKey, V2File? file) async {
    final files = _getSelectedFiles(zoneKey, file);
    if (files.isEmpty) return;
    if (_blockIfInherited(files, '移动')) return;
    final moved = await _guardDialog<bool?>(() => showAdaptive<bool>(
          context,
          (_) => V2MoveTargetDialog(
            api: _api,
            files: files,
            zoneKey: zoneKey,
            groupId: _effectiveGroupId,
            deliveryScope: zoneKey == 'distribution'
                ? _ctrl.distribution.selectedNode
                : null,
          ),
          routeName: '/dialog/channel-v2-move',
          barrierDismissible: false,
        ));
    if (moved == true) {
      // 【对 web 的小幅偏离，留痕】web 的 onMoved 只 refreshAll，不清选中
      // （ChannelV2Page.vue:775-778）；这里按 S5 统一口径先清再刷，
      // 否则移走的文件仍留在选中键集合里，后续批量操作会少算项数。
      _clearSelection(zoneKey);
      // 移动可能跨区影响（资源区改 parent / 下发区改父节点）→ 三区全刷
      _ctrl.refreshAll();
    }
  }

  // ====== 属性 / 隐藏 ======

  Future<void> _openPropsDialog(V2File file) async {
    await _guardDialog<void>(() async => showAdaptive<void>(
          context,
          (_) => V2FilePropsDialog(
            api: _api,
            file: file,
            // 隐藏状态变化后三区都可能含此文件的引用 → 全刷（对齐 :770-773）
            onHideChanged: () => _ctrl.refreshAll(),
          ),
          routeName: '/dialog/channel-v2-props',
        ));
  }

  // ====== 下发（复制到下发区） ======

  Future<void> _distribute(List<V2File> files) async {
    if (files.isEmpty) return;
    final ok = await v2DistributeMany(
      api: _api,
      files: files,
      target: _ctrl.distribution.selectedNode,
      notice: _notice,
    );
    if (ok) _ctrl.distribution.refresh();
  }

  // ====== 解压 ======

  Future<void> _unzip(String zoneKey, V2File file) async {
    if (_blockIfInherited([file], '解压')) return;
    if (_unzipping) return; // 防重复点击：连点会向后端投多份解压任务
    final gid = file.groupFileId;
    if (gid == null) return;
    setState(() => _unzipping = true);
    try {
      await _api.extractResource(gid);
      // 【对 web 的刻意偏离，留痕】web 用 `res.message || '已解压'`（:567），
      // 但本端 ApiClient 在 code==0 时把 message 丢弃（只把 data 透出），
      // 无法照抄后端文案 → 改用中性文案。
      // T8d：/file/extract 判定为**异步投递**——任务列表的类型码只有一个
      //（100=文件解压缩，TaskListDialog.vue:133-138），状态里还有「解压中」，
      // 说明解压是后台任务，刷新本区当下大概率看不到解压结果 → 文案指向任务列表。
      _notice('已提交解压请求，可在「任务列表」查看进度', NoticeLevel.success);
      _ctrl.refreshZone(zoneKey);
    } catch (e) {
      _notice(v2ErrMessage(e, '解压失败'), NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _unzipping = false);
    }
  }

  // ====== 重命名 ======

  /// 触发资源区文件的 inline 编辑（下发区不支持：/file/rename 改的是源文件名）
  void _triggerInlineRename(V2File file, String zoneKey) {
    if (zoneKey == 'distribution') return;
    final key = zoneKey == 'hq' ? _hqZoneKey : _groupZoneKey;
    key.currentState?.startEditing(file.selectionKey);
  }

  Future<void> _onRenameCommit(
      V2File file, String newName, String zoneKey) async {
    final gid = file.groupFileId;
    if (gid == null) return;
    try {
      await _api.renameResource(gid, newName);
      _notice('已重命名', NoticeLevel.success);
      _ctrl.refreshZone(zoneKey);
    } catch (e) {
      _notice(v2ErrMessage(e, '重命名失败'), NoticeLevel.error);
    }
  }

  // ====== 快捷键（Delete 删除选中 / F2 重命名） ======

  /// 输入中（顶栏搜索框 / inline 重命名框）不接管按键：
  /// 编辑框里的 Delete 是删字符
  bool get _isTyping =>
      _searchFocus.hasFocus ||
      (_hqZoneKey.currentState?.isEditing ?? false) ||
      (_groupZoneKey.currentState?.isEditing ?? false);

  KeyEventResult _onPageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k != LogicalKeyboardKey.delete && k != LogicalKeyboardKey.f2) {
      return KeyEventResult.ignored;
    }
    if (_anyDialogOpen || _isTyping) return KeyEventResult.ignored;

    // 按固定顺序 hq → group → distribution 找有选中的区
    // （三区选中互斥由 activateZone 保证，这里的顺序只在互斥失效时兜底）
    String? zoneKey;
    List<V2File> files = const [];
    if (_ctrl.hqSel.keys.isNotEmpty) {
      zoneKey = 'hq';
      files = _ctrl.hqSel.selectedFiles;
    } else if (_ctrl.groupSel.keys.isNotEmpty) {
      zoneKey = 'group';
      files = _ctrl.groupSel.selectedFiles;
    } else if (_ctrl.distribution.selectedIds.isNotEmpty) {
      zoneKey = 'distribution';
      files = _ctrl.distribution.selectedFiles;
    }
    if (zoneKey == null || files.isEmpty) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.delete) {
      _triggerDeleteSelected(files, zoneKey);
      return KeyEventResult.handled;
    }
    // F2：仅单选、下发区不支持、且与右键菜单同一权限门槛
    if (files.length != 1) return KeyEventResult.ignored;
    if (zoneKey == 'distribution') return KeyEventResult.ignored;
    if (!_canWriteForFile(zoneKey, files.first)) return KeyEventResult.ignored;
    _triggerInlineRename(files.first, zoneKey);
    return KeyEventResult.handled;
  }

  Future<void> _triggerDeleteSelected(
      List<V2File> files, String zoneKey) async {
    // 继承节点单独提示：否则按 Delete 无任何反馈，用户不知道为什么删不掉
    if (_blockIfInherited(files, '删除')) return;
    // 快捷键路径的整体门槛：任一文件不可写则整体拒绝
    // （菜单里删除会置灰，快捷键同样不放行；对齐 :836 的 every）
    if (!files.every((f) => _canWriteForFile(zoneKey, f))) return;
    final ok = await _guardDialog<bool>(() async {
      if (files.length == 1) {
        return v2ConfirmAndDelete(
          context,
          api: _api,
          file: files.first,
          zoneKey: zoneKey,
          notice: _notice,
        );
      }
      return v2ConfirmAndBatchDelete(
        context,
        api: _api,
        files: files,
        zoneKey: zoneKey,
        notice: _notice,
      );
    });
    if (ok) {
      _clearSelection(zoneKey);
      _ctrl.refreshZone(zoneKey);
    }
  }

  // ====== 上传 ======

  /// 打开上传弹窗。
  ///
  /// [zoneKey] 为 null = 工具栏入口：落根目录、不带归属字段，由后端按账号身份
  /// 决定落点（对齐 web ChannelV2Page.vue:368-372）。
  /// 有 zoneKey = 空白右键入口：上传到当前浏览目录；小组区根目录后端无法从父目录
  /// 推断归属，必须显式带 group_id（对齐 ChannelV2Page.vue:502-509）。
  ///
  /// folderId 与 extra 都在这里取一次快照传进弹窗：上传中切组/切目录不得改变
  /// 已入队文件的落点。
  void _openUploadDialog({String? zoneKey}) {
    final String folderId;
    final Map<String, String> extra;
    if (zoneKey == null || zoneKey == 'distribution') {
      // 下发区无资源目录语义 → 仍用根目录
      folderId = '0';
      extra = const {};
    } else {
      folderId = '${_ctrl.currentFolderIdOf(zoneKey) ?? 0}';
      extra = zoneKey == 'group'
          ? buildV2UploadExtra('group', groupId: _effectiveGroupId)
          : buildV2UploadExtra('hq');
    }

    _guardDialog<void>(() async => showAdaptive<void>(
          context,
          (_) => V2UploadDialog(
            service: ref.read(v2UploadServiceProvider),
            folderId: folderId,
            extraParams: extra,
            // 全部跑完只回调一次；web:392-394 同样只刷资源区（下发区未变）
            onUploaded: () => _ctrl.refreshResourceZones(),
          ),
          // 上传中禁止关窗：点遮罩关闭会让串行队列成孤儿
          barrierDismissible: false,
        ));
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

    return Focus(
      focusNode: _pageFocus,
      autofocus: true,
      onKeyEvent: _onPageKey,
      child: Container(
        color: const Color(0xFFF0F2F5),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(context, isNarrow, canSeeHqZone, perm.isManager),
            const SizedBox(height: 8),
            Expanded(
              child: isNarrow
                  ? _buildNarrowBody(context, perm, canSeeHqZone, canWriteHqZone,
                      canWriteGroupZone)
                  : _buildWideBody(context, perm, canSeeHqZone, canWriteHqZone,
                      canWriteGroupZone),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(
      BuildContext context, bool isNarrow, bool canSeeHqZone, bool canUpload) {
    final actions = <Widget>[
      // 对齐 web ChannelV2Page.vue:24 `v-if=isManagerUser`
      if (canUpload)
        TextButton.icon(
          onPressed: () => _openUploadDialog(),
          icon: const Icon(LucideIcons.upload, size: 14),
          label: const Text('上传', style: TextStyle(fontSize: 13)),
        ),
      IconButton(
        tooltip: _viewMode == 'grid' ? '切换到列表视图' : '切换到图标视图',
        onPressed: () =>
            setState(() => _viewMode = _viewMode == 'grid' ? 'list' : 'grid'),
        icon: Icon(_viewMode == 'grid' ? LucideIcons.list : LucideIcons.grid,
            size: 16, color: Colors.grey.shade600),
      ),
      IconButton(
        tooltip: '刷新',
        onPressed: _ctrl.refreshAll,
        icon: Icon(LucideIcons.refreshCw, size: 16, color: Colors.grey.shade600),
      ),
      // 窄屏不渲染 [_extraToolbarButtons]（会挤爆标题行），这些入口在这里收进菜单，
      // 否则手机端根本进不去策略/任务列表弹窗
      if (isNarrow)
        Builder(
          builder: (btnCtx) => IconButton(
            tooltip: '更多',
            onPressed: () => _openMoreMenu(btnCtx),
            icon: Icon(LucideIcons.moreHorizontal,
                size: 16, color: Colors.grey.shade600),
          ),
        ),
    ];

    final searchField = SizedBox(
      height: 32,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索文件（三区联动）',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon:
              Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 13),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFEEF0F4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFF007AFF)),
          ),
        ),
      ),
    );

    return _card(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                // 功能入口按钮（见 [_extraToolbarButtons]）；窄屏不渲染以免挤压标题，
                // 改由 actions 里的「更多」菜单进入（[_openMoreMenu]）。
                // 外包 Flexible+横向滚动：中等宽度（~900px）下四个按钮 + 搜索框
                // 会把 Row 撑爆成 RenderFlex overflow，这里让它退化为可横滚
                if (!isNarrow)
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 16),
                          ..._extraToolbarButtons(),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                if (!isNarrow) ...[
                  SizedBox(width: 220, child: searchField),
                  const SizedBox(width: 8),
                ],
                ...actions,
              ],
            ),
            if (isNarrow) ...[
              const SizedBox(height: 6),
              searchField,
            ],
          ],
        ),
      ),
    );
  }

  /// 工具栏功能入口（对齐 web ChannelV2Page.vue:6-8,22）。T8d 起四个全部接通。
  List<Widget> _extraToolbarButtons() {
    final entries = <(String, VoidCallback?)>[
      ('网吧私有策略', () => _openStrategyDialog(V2StrategyVariant.private)),
      ('程序公共策略', () => _openStrategyDialog(V2StrategyVariant.public)),
      // 桌标管理在移动端整体不提供（与主菜单同口径，见 main_layout.dart:495
      // `if (!platformHelper.isMobile)`），故移动端直接不渲染入口
      if (!isMobilePlatform) ('桌标管理', _openDesktopIcon),
      ('任务列表', _openTaskListDialog),
    ];
    return [
      for (final e in entries)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(
            onPressed: e.$2,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(e.$1, style: const TextStyle(fontSize: 12)),
          ),
        ),
    ];
  }

  /// 窄屏功能入口菜单（走 [_showContextMenu] → 已包 [_guardDialog]）。
  /// 项集合必须与 [_extraToolbarButtons] 保持一致（含移动端隐藏桌标管理）。
  Future<void> _openMoreMenu(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(box.size.bottomLeft(Offset.zero));
    final key = await _showContextMenu(pos, [
      const V2ContextMenuItem(
          key: 'strategy_private',
          label: '网吧私有策略',
          icon: LucideIcons.shieldCheck),
      const V2ContextMenuItem(
          key: 'strategy_public', label: '程序公共策略', icon: LucideIcons.globe),
      if (!isMobilePlatform)
        const V2ContextMenuItem(
            key: 'desktop_icon', label: '桌标管理', icon: LucideIcons.layoutGrid),
      const V2ContextMenuItem(
          key: 'task_list', label: '任务列表', icon: LucideIcons.listChecks),
    ]);
    switch (key) {
      case 'strategy_private':
        _openStrategyDialog(V2StrategyVariant.private);
        break;
      case 'strategy_public':
        _openStrategyDialog(V2StrategyVariant.public);
        break;
      case 'desktop_icon':
        _openDesktopIcon();
        break;
      case 'task_list':
        _openTaskListDialog();
        break;
    }
  }

  /// 打开策略列表弹窗。
  /// 工具栏入口是**全局策略**（不带 group_file_id），对齐 web 工具栏
  /// `currentDialogFile=null`（ChannelV2Page.vue:6-8）。
  /// web 另有右键「策略」入口带文件过滤，但那条路径在 web 从未被激活，本期不做。
  void _openStrategyDialog(V2StrategyVariant variant) {
    _guardDialog<void>(() async => showAdaptive<void>(
          context,
          (_) => V2StrategyListDialog(variant: variant),
          routeName: '/dialog/channel-v2-strategy',
        ));
  }

  /// 任务列表（对齐 web TaskListDialog）
  void _openTaskListDialog() {
    _guardDialog<void>(() async => showAdaptive<void>(
          context,
          (_) => V2TaskListDialog(api: _api),
          routeName: '/dialog/channel-v2-task-list',
        ));
  }

  /// 桌标管理：web 是 `router.push('/desktopIcon')`（ChannelV2Page.vue:219），
  /// Flutter 对应已有的桌面管理页路由 /desktop-management（router.dart:91）。
  /// 移动端不提供入口（见 [_extraToolbarButtons] 注释），这里再兜一层。
  void _openDesktopIcon() {
    if (isMobilePlatform) return;
    context.go('/desktop-management');
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
            Expanded(child: _card(_buildDistributionZone(perm, true))),
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
      body = _buildDistributionZone(perm, false);
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

  Widget _buildDistributionZone(PermissionService perm, bool showTreeInline) {
    return DistributionZone(
      controller: _ctrl.distribution,
      isHqUser: perm.isHQUser,
      showTreeInline: showTreeInline,
      viewMode: _viewMode,
      searchQuery: _searchQuery,
      onZoneActivate: () => _ctrl.activateZone('distribution'),
      onFileContextMenu: (f, pos) => _openFileMenu('distribution', f, pos),
      onBlankContextMenu: (pos) => _openBlankMenu('distribution', pos),
      // 窄屏 scope 选择弹窗由本组件自己弹，注入守卫让它也计入 _dialogDepth
      dialogGuard: _guardDialog,
    );
  }

  Widget _buildHqZone(bool canWriteHqZone) {
    return ListenableBuilder(
      listenable: _hqListenable,
      builder: (context, _) => _hqZone(canWriteHqZone),
    );
  }

  Widget _hqZone(bool canWriteHqZone) {
    return ResourceZone(
      key: _hqZoneKey,
      zoneKey: 'hq',
      title: '总部资源区',
      files: _ctrl.hq.files,
      loading: _ctrl.hq.loading,
      path: _ctrl.hq.path,
      readonly: !canWriteHqZone,
      emptyText: '总部资源区为空',
      viewMode: _viewMode,
      searchQuery: _searchQuery,
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
      onBoxSelect: (keys) {
        _ctrl.activateZone('hq');
        _ctrl.hqSel.onBoxSelect(keys);
      },
      onRenameCommit: (f, n) => _onRenameCommit(f, n, 'hq'),
      onFileContextMenu: (f, pos) => _openFileMenu('hq', f, pos),
      onBlankContextMenu: (pos) => _openBlankMenu('hq', pos),
    );
  }

  Widget _buildGroupZone(PermissionService perm, bool canWriteGroupZone) {
    // ref.watch 必须在页面 build 里求值：ListenableBuilder 的 builder 会在页面
    // build 之外被控制器触发，watch 不能放进去
    final groups = ref.watch(netbarListProvider).valueOrNull?.groups ?? const [];
    return ListenableBuilder(
      listenable: _groupListenable,
      builder: (context, _) => _groupZone(perm, canWriteGroupZone, groups),
    );
  }

  Widget _groupZone(
      PermissionService perm, bool canWriteGroupZone, List<GroupBrief> groups) {
    final isHq = perm.isHQUser;
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
      viewMode: _viewMode,
      searchQuery: _searchQuery,
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
      onBoxSelect: (keys) {
        _ctrl.activateZone('group');
        _ctrl.groupSel.onBoxSelect(keys);
      },
      onRenameCommit: (f, n) => _onRenameCommit(f, n, 'group'),
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
