import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../data/channel_v2_api.dart';
import '../data/channel_v2_models.dart';

/// ChannelV2 状态层：对齐 web composables/channel-v2 的四个 use*，
/// 后续阶段（文件操作/策略/启动项）全部挂在这套控制器上，此处 API 面第一天定死。

// ============ 选中态（对齐 useZoneSelection.js 全 API） ============

/// 单区文件选中态：单击选中 / Ctrl 多选 / Shift 范围选 / 框选。
class ZoneSelectionController extends ChangeNotifier {
  /// 当前区可见文件列表取值器（Shift 范围选需按列表顺序确定 from/to）
  final List<V2File> Function() _files;

  ZoneSelectionController(List<V2File> Function() files) : _files = files;

  final Set<String> _keys = <String>{};
  String? _lastClickKey;

  /// 选中键集合（键 = V2File.selectionKey）
  Set<String> get keys => _keys;

  List<V2File> get selectedFiles =>
      _files().where((f) => _keys.contains(f.selectionKey)).toList();

  /// 对齐 useZoneSelection.js onClick(file, e)：
  /// shift → 以 lastClick 为锚做范围选；ctrl → 切换；否则单选
  void onClick(V2File file, {bool ctrl = false, bool shift = false}) {
    final key = file.selectionKey;
    if (shift && _lastClickKey != null) {
      final list = _files();
      final lastIdx = list.indexWhere((f) => f.selectionKey == _lastClickKey);
      final curIdx = list.indexWhere((f) => f.selectionKey == key);
      if (lastIdx >= 0 && curIdx >= 0) {
        final from = lastIdx <= curIdx ? lastIdx : curIdx;
        final to = lastIdx <= curIdx ? curIdx : lastIdx;
        for (var i = from; i <= to; i++) {
          _keys.add(list[i].selectionKey);
        }
      } else {
        _keys.add(key);
      }
      // 保真：web 版 shift 分支不更新 lastClickId
    } else if (ctrl) {
      if (_keys.contains(key)) {
        _keys.remove(key);
      } else {
        _keys.add(key);
      }
      _lastClickKey = key;
    } else {
      _keys
        ..clear()
        ..add(key);
      _lastClickKey = key;
    }
    notifyListeners();
  }

  void onBlankClick() {
    if (_keys.isEmpty && _lastClickKey == null) return;
    _keys.clear();
    _lastClickKey = null;
    notifyListeners();
  }

  /// 框选结果整体替换（T8a 无框选 UI，签名预埋供 T8b 挂接）
  void onBoxSelect(Set<String> newKeys) {
    _keys
      ..clear()
      ..addAll(newKeys);
    notifyListeners();
  }

  void clear() {
    if (_keys.isEmpty && _lastClickKey == null) return;
    _keys.clear();
    _lastClickKey = null;
    notifyListeners();
  }

  /// 右键 file → 应被批量操作的文件列表（纯查询，不改选中态）：
  /// 右键项已在选中集合里 → 返回全部选中；未选中 → 只它本身；空 → []
  /// （对齐 useZoneSelection.js:55-60）
  List<V2File> expandFromRightClick(V2File? file) {
    if (file != null && _keys.contains(file.selectionKey)) {
      return selectedFiles;
    }
    return file != null ? [file] : const [];
  }
}

// ============ 资源区文件状态（对齐 useZoneFiles.js） ============

class ZoneFilesController extends ChangeNotifier {
  final ChannelV2Api api;

  /// 'hq' | 'group'
  final String zone;
  final String zoneLabel;

  /// 刷新失败提示出口（页面挂 showTopNotice；对齐 web ElMessage.error）
  void Function(String message)? onError;

  ZoneFilesController({
    required this.api,
    required this.zone,
    required this.zoneLabel,
    int? groupId,
  }) : _groupId = groupId {
    path = [ZonePathItem(id: null, name: zoneLabel)];
  }

  int? _groupId;
  int? get groupId => _groupId;

  List<V2File> files = const [];
  bool loading = false;

  /// 从根开始的目录栈，根目录 {id: null, name: zoneLabel}（对齐 useZoneFiles.js:20）
  late List<ZonePathItem> path;

  int? get currentFolderId => path.last.id;
  bool get isAtRoot => path.length == 1;

  // 请求序号：快速切目录/切小组时，晚发出的请求先返回会覆盖后发的，
  // 导致面包屑停在 A 层、列表却是 B 层内容（对齐 useZoneFiles.js:27-47）
  int _reqSeq = 0;

  Future<void> refresh() async {
    if (zone == 'group' && _groupId == null) {
      files = const [];
      notifyListeners();
      return;
    }
    final seq = ++_reqSeq;
    loading = true;
    notifyListeners();
    try {
      final list = await api.listResources(
        zone: zone,
        groupId: _groupId,
        parentId: currentFolderId,
      );
      if (seq != _reqSeq) return;
      files = list;
    } catch (e) {
      if (seq != _reqSeq) return;
      files = const [];
      onError?.call(e.toString().isEmpty ? '资源加载失败' : e.toString());
    } finally {
      if (seq == _reqSeq) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void enterFolder(V2File folder) {
    if (!folder.isFolder) return;
    path = [...path, ZonePathItem(id: folder.id, name: folder.name)];
    refresh();
  }

  void goTo(int index) {
    if (index < 0 || index >= path.length) return;
    path = path.sublist(0, index + 1);
    refresh();
  }

  void reset() {
    path = [ZonePathItem(id: null, name: zoneLabel)];
    refresh();
  }

  /// 小组切换：必须回根再刷（对齐 useZoneFiles.js:105-107 watch(groupId)→reset），
  /// 否则停留在旧组的子目录 id 上，新组按该 parent_id 查询会拿到错数据
  void setGroupId(int? id) {
    if (id == _groupId) return;
    _groupId = id;
    reset();
  }
}

// ============ 下发区文件状态（对齐 useDistributionFiles.js） ============

class DistributionFilesController extends ChangeNotifier {
  final ChannelV2Api api;

  void Function(String message)? onError;

  DistributionFilesController({required this.api});

  DistributionScope? _scope;
  DistributionScope? get scope => _scope;

  bool loading = false;

  /// 目录路径：path[0] 是合成根（scope 名），末尾是当前所在文件夹
  List<V2File> path = [V2File.deliveryRoot(name: '下发文件区', children: const [])];

  /// 当前目录下显示的文件列表（对齐 useDistributionFiles.js:25-28）
  List<V2File> get files => path.last.children;

  int _reqSeq = 0;

  /// scope 切换：路径不再适用，必须先清 path 再刷
  /// （对齐 useDistributionFiles.js:174-183 watch selectedNode → 先回根再 refresh）
  void setScope(DistributionScope? scope) {
    final same = _scope?.scopeType == scope?.scopeType &&
        _scope?.scopeId == scope?.scopeId;
    _scope = scope;
    if (same) return;
    path = [V2File.deliveryRoot(name: '下发文件区', children: const [])];
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    final node = _scope;
    if (node == null) {
      path = [V2File.deliveryRoot(name: '下发文件区', children: const [])];
      notifyListeners();
      return;
    }
    // 整棵树会被替换成新对象，先记当前层级的 deliveryNodeId 序列，拉完按它复位，
    // 否则用户在子目录里的任何刷新都会被弹回根目录（对齐 useDistributionFiles.js:40-42）
    final keys = path.skip(1).map((p) => p.deliveryPathKey).toList();
    final seq = ++_reqSeq;
    loading = true;
    notifyListeners();
    try {
      final tree = await api.getDeliveryTree(
        scopeType: node.scopeType,
        scopeId: node.scopeId,
      );
      if (seq != _reqSeq) return;
      final root = V2File.deliveryRoot(name: node.name, children: tree);
      path = restorePath(root, keys);
    } catch (e) {
      if (seq != _reqSeq) return;
      path = [V2File.deliveryRoot(name: node.name, children: const [])];
      onError?.call(e.toString().isEmpty ? '下发树加载失败' : e.toString());
    } finally {
      if (seq == _reqSeq) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void enterFolder(V2File folder) {
    if (!folder.isFolder) return;
    path = [...path, folder];
    notifyListeners();
  }

  void goTo(int index) {
    if (index < 0 || index >= path.length) return;
    path = path.sublist(0, index + 1);
    notifyListeners();
  }
}

// ============ 下发区暴露面（对齐 DistributionZone.vue:274-282 defineExpose） ============

class DistributionZoneController extends ChangeNotifier {
  final ChannelV2Api api;
  late final DistributionFilesController filesCtrl;
  late final ZoneSelectionController selection;

  DistributionZoneController({required this.api}) {
    filesCtrl = DistributionFilesController(api: api);
    selection = ZoneSelectionController(() => filesCtrl.files);
    // 子控制器变化统一上抛，页面只需监听本控制器
    filesCtrl.addListener(notifyListeners);
    selection.addListener(notifyListeners);
  }

  /// 树选中 key 持久化在控制器上：窄/宽布局切换重挂 widget 不丢选中
  String? selectedTreeKey;

  DistributionScope? get selectedNode => filesCtrl.scope;
  Set<String> get selectedIds => selection.keys;
  List<V2File> get selectedFiles => selection.selectedFiles;
  List<V2File> expandFromRightClick(V2File? file) =>
      selection.expandFromRightClick(file);
  void clearSelection() => selection.clear();
  List<V2File> get files => filesCtrl.files;
  Future<void> refresh() => filesCtrl.refresh();

  /// 左树点选 scope（对齐 DistributionZone.vue onNodeClick：selectNode + 清选中）
  void selectScope(DistributionScope scope) {
    selectedTreeKey = scope.key;
    selection.clear();
    filesCtrl.setScope(scope);
    notifyListeners();
  }

  @override
  void dispose() {
    filesCtrl.dispose();
    selection.dispose();
    super.dispose();
  }
}

// ============ 页面级协调器（对齐 ChannelV2Page.vue 协调逻辑） ============

class ChannelV2PageController {
  final ChannelV2Api api;

  late final ZoneFilesController hq;
  late final ZoneFilesController group;
  late final ZoneSelectionController hqSel;
  late final ZoneSelectionController groupSel;
  late final DistributionZoneController distribution;

  /// 由页面按权限写入（isHQUser），refreshResourceZones 据此决定是否刷 hq 区
  bool canSeeHqZone = false;

  ChannelV2PageController({required this.api}) {
    hq = ZoneFilesController(api: api, zone: 'hq', zoneLabel: '总部资源区');
    group = ZoneFilesController(api: api, zone: 'group', zoneLabel: '小组资源区');
    hqSel = ZoneSelectionController(() => hq.files);
    groupSel = ZoneSelectionController(() => group.files);
    distribution = DistributionZoneController(api: api);
  }

  /// 同一时刻只允许一个区有选中，三区必须全互斥（对齐 ChannelV2Page.vue:312-320）：
  /// Delete/F2 快捷键按固定顺序找选中区，残留旧选中会让操作落到错误的区。
  /// 判空再清：避免另外两区的选中集合被无谓换新触发重渲染。
  void activateZone(String zoneKey) {
    if (zoneKey != 'hq' && hqSel.keys.isNotEmpty) hqSel.clear();
    if (zoneKey != 'group' && groupSel.keys.isNotEmpty) groupSel.clear();
    if (zoneKey != 'distribution' && distribution.selectedIds.isNotEmpty) {
      distribution.clearSelection();
    }
  }

  void refreshZone(String zoneKey) {
    if (zoneKey == 'hq') {
      hq.refresh();
    } else if (zoneKey == 'group') {
      group.refresh();
    } else if (zoneKey == 'distribution') {
      distribution.refresh();
    }
  }

  void refreshResourceZones() {
    if (canSeeHqZone) hq.refresh();
    if (group.groupId != null) group.refresh();
  }

  void refreshAll() {
    refreshResourceZones();
    distribution.refresh();
  }

  /// 当前浏览目录 id（上传/新建的落点；对齐 ChannelV2Page.vue:780-784，
  /// 下发区无资源目录语义 → null 视同根目录 '0'）
  int? currentFolderIdOf(String zoneKey) {
    if (zoneKey == 'hq') return hq.currentFolderId;
    if (zoneKey == 'group') return group.currentFolderId;
    return null;
  }

  void dispose() {
    hq.dispose();
    group.dispose();
    hqSel.dispose();
    groupSel.dispose();
    distribution.dispose();
  }
}

// ============ 弹窗状态槽（T8a 只定义类型，UI 在 T8b+ 实现） ============

/// 上传弹窗参数（对齐 ChannelV2Page.vue:366 uploadDialog 结构）
class UploadDialogSlot {
  /// 上传目标目录 id（'0' = 根目录；web 侧为字符串语义）
  final String folderId;

  /// 外部拖入预填充的文件（平台差异大，先用 Object 占位，T8b 定具体类型）
  final List<Object> initialFiles;

  /// 额外表单参数（小组区根目录必须显式带 group_id，后端无法从父目录推断归属）
  final Map<String, String> extraParams;

  const UploadDialogSlot({
    this.folderId = '0',
    this.initialFiles = const [],
    this.extraParams = const {},
  });
}

/// 文件属性弹窗参数（对齐 ChannelV2Page.vue:488 propsDialog）
class PropsDialogSlot {
  final V2File file;
  const PropsDialogSlot({required this.file});
}

/// 「移动到」弹窗参数（对齐 ChannelV2Page.vue:489 moveDialog）
class MoveDialogSlot {
  final V2File? file;
  final List<V2File> files;
  final String zoneKey;

  /// 下发区移动时的当前 scope（资源区移动为 null）
  final DistributionScope? deliveryScope;

  const MoveDialogSlot({
    this.file,
    this.files = const [],
    this.zoneKey = 'group',
    this.deliveryScope,
  });
}

// ============ 右键菜单（对齐 useContextMenuItems.js） ============

class V2ContextMenuItem {
  final String key;
  final String label;
  final IconData? icon;
  final bool disabled;
  final bool danger;
  final bool divider;

  const V2ContextMenuItem({
    this.key = '',
    this.label = '',
    this.icon,
    this.disabled = false,
    this.danger = false,
    this.divider = false,
  });

  const V2ContextMenuItem.divider()
      : key = '',
        label = '',
        icon = null,
        disabled = false,
        danger = false,
        divider = true;
}

/// 根据「区域 + 文件 + 权限 + 批量」决定右键菜单项。
/// 签名对齐 useContextMenuItems.js:16-24，后续阶段只往里补 item，不改签名。
/// T8a 只挂 刷新 / 属性(disabled 占位)；
/// 完整项集（复制到下发区/解压/重命名/移动/删除/上传/视图切换）T8b+ 按 web 全集补齐。
List<V2ContextMenuItem> buildContextMenuItems({
  required String zoneKey,
  V2File? file,
  required bool isBlank,
  required bool writableHere,
  required bool writableFile,
  required List<V2File> batchFiles,
  required String viewMode,
}) {
  if (isBlank) {
    return const [
      V2ContextMenuItem(key: 'refresh', label: '刷新', icon: LucideIcons.refreshCw),
    ];
  }
  return const [
    V2ContextMenuItem(key: 'refresh', label: '刷新', icon: LucideIcons.refreshCw),
    V2ContextMenuItem.divider(),
    // T8a 占位恒置灰；属性弹窗 T8b 落地后改回 `disabled: batchFiles.length > 1`
    // （批量时 web 同样置灰，useContextMenuItems.js:72）
    V2ContextMenuItem(
      key: 'properties',
      label: '属性',
      icon: LucideIcons.info,
      disabled: true,
    ),
  ];
}
