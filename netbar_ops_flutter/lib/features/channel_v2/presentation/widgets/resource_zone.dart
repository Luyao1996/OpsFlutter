import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/channel_v2_models.dart';
import 'v2_file_card.dart';

/// 资源区面板（props/事件面对齐 ResourceZone.vue:157-181）。
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

  /// 只读：T8b 起禁用拖拽/重命名等写入口（T8a 仅透传占位）
  final bool readonly;

  /// 搜索预留（T8a 顶栏搜索未做，props 先落）：
  /// searchActive 时未命中文件隐藏，全部未命中显示"未找到匹配的文件"
  final bool searchActive;
  final Set<String> matchedKeys;

  final String emptyText;
  final Set<String> selectedKeys;

  final void Function(V2File file, {bool ctrl, bool shift})? onFileTap;

  /// 双击文件夹进入（文件的双击行为 T8b+ 定义）
  final void Function(V2File file)? onFileDoubleTap;
  final void Function(int index)? onBreadcrumbTap;

  /// 文件右键/长按 → 弹菜单（全局坐标）
  final void Function(V2File file, Offset globalPosition)? onFileContextMenu;

  /// 空白处右键/长按
  final void Function(Offset globalPosition)? onBlankContextMenu;
  final VoidCallback? onBlankTap;

  const ResourceZone({
    super.key,
    required this.zoneKey,
    this.title = '',
    this.titleBuilder,
    this.files = const [],
    this.path = const [ZonePathItem(id: null, name: '')],
    this.loading = false,
    this.readonly = false,
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
  });

  @override
  State<ResourceZone> createState() => ResourceZoneState();
}

class ResourceZoneState extends State<ResourceZone> {
  /// inline 重命名入口（对齐 ResourceZone.vue defineExpose({ startEditing })）。
  /// T8b 实现编辑态；签名先落，页面已按 GlobalKey<ResourceZoneState> 持有。
  void startEditing(String selectionKey) {
    // T8b: 定位到 selectionKey 对应文件卡，切换为编辑态（Windows 风：默认选中主名，扩展名强制保留）
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

    return _blankArea(
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final file in visibleFiles)
                V2FileCard(
                  file: file,
                  selected: widget.selectedKeys.contains(file.selectionKey),
                  onTap: () => widget.onFileTap?.call(
                    file,
                    ctrl: _ctrlPressed,
                    shift: _shiftPressed,
                  ),
                  onDoubleTap: () => widget.onFileDoubleTap?.call(file),
                  onSecondaryTap: (pos) =>
                      widget.onFileContextMenu?.call(file, pos),
                  onLongPress: (pos) =>
                      widget.onFileContextMenu?.call(file, pos),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空白区手势层：点空白清选中，右键/长按空白弹区级菜单。
  /// 文件卡自身的手势在竞技场里优先，卡外区域才落到这里。
  Widget _blankArea(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onBlankTap,
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
