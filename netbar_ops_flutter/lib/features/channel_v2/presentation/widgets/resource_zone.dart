import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/channel_v2_models.dart';
import 'v2_file_card.dart';

/// 资源区面板（props/事件面对齐 ResourceZone.vue:157-194）。
/// 下发区右侧文件区也复用本组件的展示（文件卡抽在 v2_file_card.dart）。
class ResourceZone extends StatefulWidget {
  /// 'hq' | 'group' | 'distribution'
  final String zoneKey;

  /// 区域标题，可被 [titleBuilder] 覆盖（小组区的组下拉挂 titleBuilder）
  final String title;
  final WidgetBuilder? titleBuilder;

  final List<V2File> files;

  /// 面包屑路径，根目录为 path[0]（根节点名 = zoneLabel）
  final List<ZonePathItem> path;
  final bool loading;

  /// 只读：禁用重命名等写入口（拖拽本期未做）
  final bool readonly;

  /// 视图模式 'grid' | 'list'（对齐 ResourceZone.vue props.viewMode：
  /// web 只切 CSS 类，本端切两套行/卡布局，数据与手势语义完全一致）
  final String viewMode;

  /// 搜索联动：非空时未命中文件隐藏，全部未命中显示"未找到匹配的文件"。
  /// 【为什么传 query 而不是命中集】命中集要在页面侧对三个区的全量文件各跑一次
  /// toSet()，每帧 O(n)；传 query 后由本区自己逐项 contains，虚拟化后只算可见项。
  final String searchQuery;

  final String emptyText;
  final Set<String> selectedKeys;

  final void Function(V2File file, {bool ctrl, bool shift})? onFileTap;

  /// 双击文件夹进入
  final void Function(V2File file)? onFileDoubleTap;
  final void Function(int index)? onBreadcrumbTap;

  /// 文件右键/长按 → 弹菜单（全局坐标）
  final void Function(V2File file, Offset globalPosition)? onFileContextMenu;

  /// 空白处右键/长按
  final void Function(Offset globalPosition)? onBlankContextMenu;
  final VoidCallback? onBlankTap;

  /// inline 重命名提交：(file, 新文件名（已强制拼回原扩展名）)
  /// 对齐 ResourceZone.vue emit('rename-commit', file, input)
  final void Function(V2File file, String newName)? onRenameCommit;

  /// 框选结果（Set<selectionKey>）：**整体替换**语义。
  /// Ctrl/Cmd 起手时的并集已在本区算好（见 [_startBox]），控制器侧只管照单全收。
  final void Function(Set<String> keys)? onBoxSelect;

  /// 区内拖拽到文件夹卡片 → 区内移动。
  ///
  /// 【未接线，留痕】拖拽整体不在 T8a-T8d 范围内：本组件内部**没有任何**
  /// Draggable/DragTarget，因此该回调永远不会被触发，调用点也没有一处传值。
  /// 保留签名是为了将来接拖拽时不改 ResourceZone 的公开 API。
  /// 接的时候：桌面用 Draggable/DragTarget，回调里走
  /// v2MoveFilesSerially(destId = 目标文件夹 id)；移动端不接。
  final void Function(V2File targetFolder)? onFolderDrop;

  /// 外部文件拖入本区 → 静默上传。
  ///
  /// 【未接线，留痕】同上，本组件未监听任何外部拖放事件，回调恒不触发。
  /// 接的时候：桌面用 desktop_drop 插件，上传路径同 V2UploadService；
  /// Web/移动端无此入口。参数用 Object 是为了不把 dart:io File 泄进共享层签名。
  final void Function(List<Object> files)? onExternalFilesDrop;

  const ResourceZone({
    super.key,
    required this.zoneKey,
    this.title = '',
    this.titleBuilder,
    this.files = const [],
    this.path = const [ZonePathItem(id: null, name: '')],
    this.loading = false,
    this.readonly = false,
    this.viewMode = 'grid',
    this.searchQuery = '',
    this.emptyText = '',
    this.selectedKeys = const {},
    this.onFileTap,
    this.onFileDoubleTap,
    this.onBreadcrumbTap,
    this.onFileContextMenu,
    this.onBlankContextMenu,
    this.onBlankTap,
    this.onRenameCommit,
    this.onBoxSelect,
    this.onFolderDrop,
    this.onExternalFilesDrop,
  });

  @override
  State<ResourceZone> createState() => ResourceZoneState();
}

class ResourceZoneState extends State<ResourceZone> {
  // ===== inline 重命名（Windows 风：显示完整名、默认只选中主名、扩展名强制保留） =====
  // 对齐 ResourceZone.vue:200-260。
  // 【与 web 的键差异，留痕】web 用 file.id 作编辑键；本端统一用 V2File.selectionKey
  // （下发区源 id 会撞键，见 V2File.selectionKey 注释），页面侧的 startEditing 也传 selectionKey。
  final TextEditingController _editCtrl = TextEditingController();
  final FocusNode _editFocus = FocusNode();
  String? _editingKey;
  String _editingExt = '';

  // ===== 虚拟化 + 框选所需的状态 =====

  final ScrollController _scroll = ScrollController();

  /// 布局快照（由 build 里的 LayoutBuilder 写入）。
  /// 框选命中判定全靠这三项**纯计算**得出，不做 GlobalKey 逐项测量。
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  V2GridMetrics? _gridMetrics; // list 视图为 null
  List<V2File> _laidOutFiles = const [];

  /// 框选锚点 / 当前点，均为**内容坐标**（视口坐标 + 滚动偏移）：
  /// 自动滚动时锚点必须钉在内容上，否则边缘滚动会把已框住的项甩掉。
  Offset? _boxAnchor;
  Offset? _boxCurrent;
  Offset _pointerLocal = Offset.zero; // 视口坐标
  Offset _pointerDownLocal = Offset.zero;
  bool _boxActive = false;
  int? _boxPointerId;

  /// Ctrl 起手时的既有选中（与框选命中做并集）
  Set<String> _boxBase = const {};
  Set<String>? _boxEmitted;

  Timer? _autoScrollTimer;
  int _autoScrollDir = 0;

  // 搜索过滤结果缓存：build 会被编辑态/框选频繁触发，
  // 没必要每帧对全量文件重跑一次 where
  List<V2File> _cachedVisible = const [];
  List<V2File>? _cachedFrom;
  String _cachedQuery = '';

  @override
  void initState() {
    super.initState();
    _editFocus.addListener(_onEditFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ResourceZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 编辑中若列表被刷新掉（目标文件已不在当前目录）→ 直接退出编辑态，
    // 否则编辑框会挂在一个已消失的文件上，提交时把新名字发给别人
    if (_editingKey != null &&
        !widget.files.any((f) => f.selectionKey == _editingKey)) {
      _editingKey = null;
      _editingExt = '';
    }
    // 换目录（进/退文件夹、切小组、切 scope）必须把滚动位置归零，
    // 否则新目录会停在上一个目录的滚动偏移上
    if (_pathKey(oldWidget.path) != _pathKey(widget.path)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  String _pathKey(List<ZonePathItem> path) =>
      path.map((e) => '${e.id}/${e.name}').join('>');

  @override
  void dispose() {
    _stopAutoScroll();
    _scroll.dispose();
    _editFocus.removeListener(_onEditFocusChanged);
    _editFocus.dispose();
    _editCtrl.dispose();
    super.dispose();
  }

  void _onEditFocusChanged() {
    // 失焦即提交（对齐 vue @blur="commitEdit"）
    if (!_editFocus.hasFocus && _editingKey != null) _commitEdit();
  }

  /// 是否正在 inline 编辑（页面用它决定要不要吞掉 Delete/F2 快捷键：
  /// 编辑框里按 Delete 是删字符，不能触发删文件）
  bool get isEditing => _editingKey != null;

  /// inline 重命名入口（对齐 ResourceZone.vue defineExpose({ startEditing })）。
  /// 页面按 GlobalKey<ResourceZoneState> 持有本 State 调用。
  void startEditing(String selectionKey) {
    if (widget.readonly) return;
    V2File? file;
    for (final f in widget.files) {
      if (f.selectionKey == selectionKey) {
        file = f;
        break;
      }
    }
    if (file == null) return;
    final name = file.name;
    final dotIdx = name.lastIndexOf('.');
    final hasExt = !file.isFolder && dotIdx > 0;
    _editingExt = hasExt ? name.substring(dotIdx) : '';
    _editCtrl.text = name; // 编辑值含扩展名
    setState(() => _editingKey = selectionKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingKey != selectionKey) return;
      _editFocus.requestFocus();
      // 进入编辑只选中主名（不含后缀），与 Windows 资源管理器一致
      _editCtrl.selection = hasExt
          ? TextSelection(baseOffset: 0, extentOffset: dotIdx)
          : TextSelection(baseOffset: 0, extentOffset: name.length);
    });
  }

  void _cancelEdit() {
    if (_editingKey == null) return;
    setState(() {
      _editingKey = null;
      _editingExt = '';
    });
  }

  /// 提交规则（逐条对齐 ResourceZone.vue:237-254）：
  /// trim → 空则放弃 → 用户改了后缀则强制拼回原后缀 → 与原名相同则不发请求
  void _commitEdit() {
    final key = _editingKey;
    if (key == null) return;
    V2File? file;
    for (final f in widget.files) {
      if (f.selectionKey == key) {
        file = f;
        break;
      }
    }
    var input = _editCtrl.text.trim();
    final ext = _editingExt;
    setState(() {
      _editingKey = null;
      _editingExt = '';
    });
    if (file == null) return;
    if (input.isEmpty) return;
    if (ext.isNotEmpty && !input.toLowerCase().endsWith(ext.toLowerCase())) {
      final userDot = input.lastIndexOf('.');
      final main = userDot > 0 ? input.substring(0, userDot) : input;
      input = main + ext;
    }
    if (input == file.name) return;
    widget.onRenameCommit?.call(file, input);
  }

  Widget _buildNameEditor({required bool listMode}) {
    return Focus(
      // Esc 取消：TextField 不消费 Esc，事件冒泡到这里
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _editCtrl,
        focusNode: _editFocus,
        // 网格视图用固定 mainAxisExtent（虚拟化前提），卡片高度必须有界 →
        // 编辑框限 1 行，长名字横向滚动而不是折行顶破格高
        maxLines: 1,
        minLines: 1,
        textAlign: listMode ? TextAlign.start : TextAlign.center,
        style: TextStyle(fontSize: listMode ? 13 : 11, height: 1.2),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commitEdit(),
      ),
    );
  }

  bool get _ctrlPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  bool get _shiftPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const Divider(height: 1, color: Color(0xFFF1F3F6)),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          DefaultTextStyle(
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            child: widget.titleBuilder?.call(context) ?? Text(widget.title),
          ),
          const SizedBox(width: 12),
          Expanded(child: _buildBreadcrumb(context)),
        ],
      ),
    );
  }

  /// 面包屑：路径长度 > 3 时只显示 根 / ... / 最后两级
  /// （对齐 ResourceZone.vue:363-376 visibleBreadcrumb + breadcrumbIndex）
  Widget _buildBreadcrumb(BuildContext context) {
    final path = widget.path;
    if (path.length <= 1) return const SizedBox.shrink();

    final tail = path.sublist(1);
    final visible = tail.length <= 2 ? tail : tail.sublist(tail.length - 2);
    // 可见项还原到 path 中的真实下标
    int realIndex(int visibleIdx) =>
        tail.length <= 2 ? visibleIdx + 1 : path.length - 2 + visibleIdx;

    final children = <Widget>[
      _bcLink(path[0].name, () => widget.onBreadcrumbTap?.call(0)),
    ];
    if (path.length > 3) {
      children.add(_bcSep());
      children.add(Text('...',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400)));
    }
    for (var i = 0; i < visible.length; i++) {
      children.add(_bcSep());
      if (i < visible.length - 1) {
        final idx = realIndex(i);
        children.add(_bcLink(visible[i].name, () => widget.onBreadcrumbTap?.call(idx)));
      } else {
        children.add(Text(
          visible[i].name,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ));
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _bcSep() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('/', style: TextStyle(fontSize: 12, color: Colors.grey.shade300)),
      );

  Widget _bcLink(String name, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          name,
          style: const TextStyle(fontSize: 12, color: Color(0xFF007AFF)),
        ),
      ),
    );
  }

  String get _query => widget.searchQuery.trim().toLowerCase();
  bool get _searchActive => _query.isNotEmpty;

  List<V2File> _visibleFiles() {
    final q = _query;
    if (identical(_cachedFrom, widget.files) && _cachedQuery == q) {
      return _cachedVisible;
    }
    _cachedFrom = widget.files;
    _cachedQuery = q;
    _cachedVisible = q.isEmpty
        ? widget.files
        : widget.files.where((f) => f.name.toLowerCase().contains(q)).toList();
    return _cachedVisible;
  }

  Widget _buildBody(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: Text('加载中...',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    if (widget.files.isEmpty) {
      return _blankArea(
        Center(
          child: Text(
            widget.emptyText.isNotEmpty ? widget.emptyText : '此目录为空',
            style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
          ),
        ),
      );
    }

    final visibleFiles = _visibleFiles();
    if (_searchActive && visibleFiles.isEmpty) {
      return _blankArea(
        const Center(
          child: Text('未找到匹配的文件',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ),
      );
    }

    final isList = widget.viewMode == 'list';
    // 【必须虚拟化】改造前 grid=Wrap / list=Column 一次性构建全部文件卡，
    // 几百个文件时每次 setState（选中、搜索、刷新）都重建全部 → 卡死。
    // GridView 固定 mainAxisExtent、ListView 固定 itemExtent，Flutter 才能
    // 跳过逐项测量，只建可见项。
    return _blankArea(
      LayoutBuilder(
        builder: (context, cons) {
          // 布局快照供框选命中判定使用（与下面的 delegate 同源，不得各算各的）
          _viewportWidth = cons.maxWidth;
          _viewportHeight = cons.maxHeight;
          _laidOutFiles = visibleFiles;
          _gridMetrics = isList
              ? null
              : V2GridMetrics.of(cons.maxWidth,
                  v2CardHeightFor(MediaQuery.textScalerOf(context)));
          final metrics = _gridMetrics;

          return Stack(
            children: [
              Listener(
                // translucent：列表下方的空白区也要能收到按下事件（起手框选）
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                child: metrics == null
                    ? _buildListView(visibleFiles)
                    : _buildGridView(visibleFiles, metrics),
              ),
              if (_boxAnchor != null && _boxCurrent != null)
                Positioned.fromRect(
                  rect: _boxViewportRect(),
                  // 选框只是装饰，绝不能吃掉指针事件
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.10),
                        border: Border.all(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// list 视图：itemExtent 固定行高，Flutter 才能跳过逐项测量
  Widget _buildListView(List<V2File> files) {
    return ListView.builder(
      controller: _scroll,
      padding: kV2ZonePadding,
      itemExtent: kV2RowHeight,
      itemCount: files.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: kV2RowGap),
        child: _rowFor(files[i]),
      ),
    );
  }

  /// grid 视图：crossAxisCount 与 mainAxisExtent 全部取自 [V2GridMetrics]，
  /// 与框选命中判定同源
  Widget _buildGridView(List<V2File> files, V2GridMetrics metrics) {
    return GridView.builder(
      controller: _scroll,
      padding: kV2ZonePadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: metrics.crossAxisCount,
        crossAxisSpacing: kV2GridSpacing,
        mainAxisSpacing: kV2GridSpacing,
        mainAxisExtent: metrics.cardHeight,
      ),
      itemCount: files.length,
      // 卡片固定 92 宽、在格内居中：格宽 >= 92，余量均分成等距间隔
      itemBuilder: (_, i) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: kV2CardWidth, child: _cardFor(files[i])),
      ),
    );
  }

  // ===== 框选（橡皮筋） =====
  //
  // 【为什么用 Listener 而不是 GestureDetector.onPan】
  // pan 识别器在鼠标移动 2px 就会赢下手势竞技场，把卡片的单击/双击一并判负；
  // 笔记本触摸板的双击普遍有几像素漂移，那样会再也双击不进文件夹。
  // Listener 不进竞技场，只旁听指针事件，超过 [_kBoxStartSlop] 才认定为框选：
  // 既不动既有点击语义，也不与滚动冲突（桌面 ScrollBehavior.dragDevices 默认
  // 不含 mouse，鼠标拖拽本就不会滚动列表；触屏拖拽=滚动，这里按 kind 过滤掉）。
  static const double _kBoxStartSlop = 8;
  static const double _kAutoScrollEdge = 20;
  static const double _kAutoScrollStep = 8;

  void _onPointerDown(PointerDownEvent e) {
    // 上一次拖拽若没收到 up（窗口失焦等），这里兜底收尾，避免选框残留
    if (_boxActive) _endBox();
    _boxPointerId = null;
    if (widget.onBoxSelect == null) return;
    if (e.kind != PointerDeviceKind.mouse) return; // 触屏拖拽是滚动，不框选
    if (e.buttons != kPrimaryMouseButton) return; // 右键留给菜单
    if (_editingKey != null) return; // 重命名编辑中不框选
    _boxPointerId = e.pointer;
    _pointerDownLocal = e.localPosition;
    _pointerLocal = e.localPosition;
    _boxActive = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_boxPointerId != e.pointer) return;
    if ((e.buttons & kPrimaryMouseButton) == 0) return;
    _pointerLocal = e.localPosition;
    if (!_boxActive) {
      if ((e.localPosition - _pointerDownLocal).distance < _kBoxStartSlop) {
        return;
      }
      _startBox();
    }
    _updateBox();
    _updateAutoScroll();
  }

  void _onPointerEnd(PointerEvent e) {
    if (_boxPointerId != e.pointer) return;
    _boxPointerId = null;
    if (!_boxActive) return;
    _endBox();
  }

  void _startBox() {
    _boxActive = true;
    // 修饰键：Ctrl/Cmd 与已有选中做并集，否则整体替换
    _boxBase = _ctrlPressed ? Set<String>.of(widget.selectedKeys) : const {};
    _boxEmitted = null;
    final anchor = _toContent(_pointerDownLocal);
    _boxAnchor = anchor;
    _boxCurrent = anchor;
  }

  /// 视口坐标 → 内容坐标（纵向加滚动偏移；本区不横向滚动）
  Offset _toContent(Offset local) =>
      Offset(local.dx, local.dy + (_scroll.hasClients ? _scroll.offset : 0));

  void _updateBox() {
    if (!_boxActive) return;
    setState(() => _boxCurrent = _toContent(_pointerLocal));
    _emitBox();
  }

  void _endBox() {
    _stopAutoScroll();
    _boxActive = false;
    _boxBase = const {};
    _boxEmitted = null;
    setState(() {
      _boxAnchor = null;
      _boxCurrent = null;
    });
  }

  /// 选框矩形（视口坐标，供绘制用）
  Rect _boxViewportRect() {
    final off = _scroll.hasClients ? _scroll.offset : 0.0;
    final r = Rect.fromPoints(_boxAnchor!, _boxCurrent!);
    return Rect.fromLTRB(r.left, r.top - off, r.right, r.bottom - off);
  }

  /// list 视图第 [index] 行的内容坐标矩形。
  /// x 方向取满宽：在左右留白里竖直拖动也应选中划过的行。
  Rect _rowRect(int index) => Rect.fromLTWH(
        0,
        kV2ZonePadding.top + index * kV2RowHeight,
        _viewportWidth,
        kV2RowContentHeight,
      );

  void _emitBox() {
    final a = _boxAnchor;
    final c = _boxCurrent;
    if (a == null || c == null) return;
    final sel = Rect.fromPoints(a, c);
    final keys = <String>{..._boxBase};
    final metrics = _gridMetrics;
    for (var i = 0; i < _laidOutFiles.length; i++) {
      final r = metrics != null ? metrics.cardRect(i) : _rowRect(i);
      // 手写相交判定：纯竖直/水平拖出的零宽矩形在 Rect.overlaps 下恒为 false
      if (sel.left <= r.right &&
          r.left <= sel.right &&
          sel.top <= r.bottom &&
          r.top <= sel.bottom) {
        keys.add(_laidOutFiles[i].selectionKey);
      }
    }
    // 命中集没变就不回调：onPointerMove 每帧都来，回调会触发整区（页面）重建
    if (_boxEmitted != null && setEquals(_boxEmitted, keys)) return;
    _boxEmitted = keys;
    widget.onBoxSelect?.call(keys);
  }

  /// 拖到上/下边缘 [_kAutoScrollEdge] 内自动滚动，否则长列表框不到屏幕外的项
  void _updateAutoScroll() {
    if (!_boxActive || !_scroll.hasClients) {
      _stopAutoScroll();
      return;
    }
    final dy = _pointerLocal.dy;
    _autoScrollDir = dy < _kAutoScrollEdge
        ? -1
        : (dy > _viewportHeight - _kAutoScrollEdge ? 1 : 0);
    if (_autoScrollDir == 0) {
      _stopAutoScroll();
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
        const Duration(milliseconds: 16), (_) => _autoScrollStep());
  }

  void _autoScrollStep() {
    if (!mounted || !_boxActive || _autoScrollDir == 0 || !_scroll.hasClients) {
      _stopAutoScroll();
      return;
    }
    final pos = _scroll.position;
    final next = (pos.pixels + _autoScrollDir * _kAutoScrollStep)
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    if (next == pos.pixels) return; // 已到顶/底
    _scroll.jumpTo(next);
    _updateBox(); // 指针没动但内容动了 → 命中集要按新偏移重算
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDir = 0;
  }

  Widget _cardFor(V2File file) {
    final editing = _editingKey == file.selectionKey;
    return V2FileCard(
      file: file,
      selected: widget.selectedKeys.contains(file.selectionKey),
      nameEditor: editing ? _buildNameEditor(listMode: false) : null,
      onTap: editing
          ? null
          : () => widget.onFileTap?.call(file,
              ctrl: _ctrlPressed, shift: _shiftPressed),
      onDoubleTap: editing ? null : () => widget.onFileDoubleTap?.call(file),
      onSecondaryTap:
          editing ? null : (pos) => widget.onFileContextMenu?.call(file, pos),
      onLongPress:
          editing ? null : (pos) => widget.onFileContextMenu?.call(file, pos),
    );
  }

  Widget _rowFor(V2File file) {
    final editing = _editingKey == file.selectionKey;
    return V2FileRow(
      file: file,
      selected: widget.selectedKeys.contains(file.selectionKey),
      nameEditor: editing ? _buildNameEditor(listMode: true) : null,
      onTap: editing
          ? null
          : () => widget.onFileTap?.call(file,
              ctrl: _ctrlPressed, shift: _shiftPressed),
      onDoubleTap: editing ? null : () => widget.onFileDoubleTap?.call(file),
      onSecondaryTap:
          editing ? null : (pos) => widget.onFileContextMenu?.call(file, pos),
      onLongPress:
          editing ? null : (pos) => widget.onFileContextMenu?.call(file, pos),
    );
  }

  /// 空白区手势层：点空白清选中，右键/长按空白弹区级菜单。
  /// 文件卡自身的手势在竞技场里优先，卡外区域才落到这里。
  Widget _blankArea(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 编辑中点空白 = 提交（与失焦语义一致），不再往下传清选中
        if (_editingKey != null) {
          _editFocus.unfocus();
          return;
        }
        widget.onBlankTap?.call();
      },
      onSecondaryTapUp: widget.onBlankContextMenu == null
          ? null
          : (d) => widget.onBlankContextMenu!(d.globalPosition),
      onLongPressStart: widget.onBlankContextMenu == null
          ? null
          : (d) => widget.onBlankContextMenu!(d.globalPosition),
      child: child,
    );
  }
}
