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

  /// 搜索联动：searchActive 时未命中文件隐藏，全部未命中显示"未找到匹配的文件"
  final bool searchActive;
  final Set<String> matchedKeys;

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

  /// 框选结果（Set<selectionKey>）。
  /// 【本期状态】只落签名 + 页面侧接线（页面已挂 selection.onBoxSelect）；
  /// 橡皮筋 UI 未实现：区体是 SingleChildScrollView，pan 手势与滚动手势冲突，
  /// 需要按平台分叉（桌面走 pan、触屏走长按后拖）——留到 T8c 一并处理。
  final void Function(Set<String> keys)? onBoxSelect;

  /// 区内拖拽到文件夹卡片 → 区内移动（本期不做拖拽，只留签名）
  /// TODO(T8c): 桌面用 Draggable/DragTarget，接 v2MoveFilesSerially(destId=文件夹 id)
  final void Function(V2File targetFolder)? onFolderDrop;

  /// 外部文件拖入本区 → 静默上传（本期不做拖拽，只留签名）
  /// TODO(T8c): 接 desktop_drop，路径同 V2UploadService；移动端无此入口
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
    this.searchActive = false,
    this.matchedKeys = const {},
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
  }

  @override
  void dispose() {
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
        maxLines: listMode ? 1 : 2,
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

    final visibleFiles = widget.searchActive
        ? widget.files
            .where((f) => widget.matchedKeys.contains(f.selectionKey))
            .toList()
        : widget.files;
    if (widget.searchActive && visibleFiles.isEmpty) {
      return _blankArea(
        const Center(
          child: Text('未找到匹配的文件',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ),
      );
    }

    final isList = widget.viewMode == 'list';
    return _blankArea(
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Align(
          alignment: Alignment.topLeft,
          child: isList
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final file in visibleFiles) ...[
                      _rowFor(file),
                      const SizedBox(height: 2),
                    ],
                  ],
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final file in visibleFiles) _cardFor(file)],
                ),
        ),
      ),
    );
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
