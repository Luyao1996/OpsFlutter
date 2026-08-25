import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/channel_v2_api.dart';
import '../../data/channel_v2_models.dart';
import '../channel_v2_file_actions.dart';

/// 「移动到」目标选择弹窗（对标 web MoveTargetDialog.vue，386 行逐条对齐）。
///
/// 【结构性约束，禁止改成"一次性展开树"】
/// 本弹窗必须是**逐层导航式**选择器：一次只显示当前层的子文件夹，进入一层才拉下一层。
/// web 的"禁止把文件移进自身子孙"不是靠显式的子孙检测实现的，而是这套导航的结构性
/// 保证：`isSelf` 只比对**直接子项**的 id（:123-128），而"进不去自身"（:209-211）
/// 让自身的所有子孙天然不可达。改成一次性展开整棵树后，子孙节点会变成可点选目标 →
/// 目录成环 / 整棵子树从可见层级里消失（数据损坏级）。
class V2MoveTargetDialog extends StatefulWidget {
  final ChannelV2Api api;

  /// 待移动集合（调用方已用 expandFromRightClick 展开；单选也是 1 个元素的列表）
  final List<V2File> files;

  /// 'hq' | 'group' | 'distribution'。
  /// **跨区移动不允许**：数据源与文案都按本值分叉，弹窗内不提供切区入口。
  final String zoneKey;

  /// 小组资源区的 group_id（每层 listResources 都必须带，否则后端退回默认组）
  final int? groupId;

  /// 下发区移动时必传（决定拉哪棵下发树）
  final DistributionScope? deliveryScope;

  const V2MoveTargetDialog({
    super.key,
    required this.api,
    required this.files,
    required this.zoneKey,
    this.groupId,
    this.deliveryScope,
  });

  @override
  State<V2MoveTargetDialog> createState() => _V2MoveTargetDialogState();
}

/// 导航栈项：id 在资源区是 group_file_id，在下发区是 delivery_node_id（根为 null）
class _MovePathItem {
  final int? id;
  final String name;
  const _MovePathItem({required this.id, required this.name});
}

class _V2MoveTargetDialogState extends State<V2MoveTargetDialog> {
  late List<_MovePathItem> _path;
  List<V2File> _folders = const [];
  bool _loading = false;
  bool _moving = false;

  /// 下发区专用：整棵树只拉一次，之后全部本地导航（对齐 MoveTargetDialog.vue:161-178）
  List<V2File> _fullDeliveryTree = const [];

  bool get _isDist => widget.zoneKey == 'distribution';

  String get _rootLabel {
    if (widget.zoneKey == 'hq') return '总部资源区';
    if (widget.zoneKey == 'group') return '小组资源区';
    return '下发区';
  }

  @override
  void initState() {
    super.initState();
    _path = [_MovePathItem(id: null, name: _rootLabel)];
    // 直接置位而非 setState：initState 阶段首帧还没 build，setState 会触发
    // "markNeedsBuild called during build"
    _loading = true;
    _loadFolders();
  }

  int? get _currentFolderId => _path.last.id;

  String get _currentLabel => _path.map((p) => p.name).join(' / ');

  /// 目标目录的身份键。
  /// 【留痕】下发树在本弹窗内自建归一：`id = delivery_node_id ?? id`
  /// （对齐 MoveTargetDialog.vue:190 `_normNode`）——这是**弹窗内部**的一套归一，
  /// 与列表页 V2File.selectionKey 的复合键不是同一套；V2File.deliveryPathKey 语义吻合，
  /// 直接复用。
  int? _keyOf(V2File f) => _isDist ? f.deliveryPathKey : f.id;

  /// 目标文件夹是否是待移动文件之一（不能移入自身）。
  ///
  /// 【对 web 的刻意偏离，留痕】web 是
  /// `folder.id === s.id || (isDist && folder.id === (s.delivery_id ?? s.id))`：
  /// 下发区模式下 folder.id 已是 delivery_node_id，第一个分支拿它去比源文件 id 属于
  /// **跨 id 空间比对**，会把无关目录误判成"自身"而禁止进入。这里只在同一 id 空间内比。
  bool _isSelf(V2File folder) {
    final fk = _keyOf(folder);
    if (fk == null) return false;
    return widget.files.any((s) => _keyOf(s) == fk);
  }

  Future<void> _loadFolders() async {
    if (!_loading) setState(() => _loading = true);
    try {
      if (_isDist) {
        await _loadDeliveryFolders();
      } else {
        final list = await widget.api.listResources(
          zone: widget.zoneKey,
          groupId: widget.groupId,
          parentId: _currentFolderId,
        );
        _folders = list.where((f) => f.isFolder).toList();
      }
    } catch (e) {
      debugPrint('[V2MoveTargetDialog] loadFolders failed: $e');
      _folders = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 下发区：整树只拉一次 + 本地按 path 定位到当前层（V5）
  Future<void> _loadDeliveryFolders() async {
    if (_fullDeliveryTree.isEmpty) {
      final scope = widget.deliveryScope;
      if (scope == null) {
        _folders = const [];
        return;
      }
      _fullDeliveryTree = await widget.api.getDeliveryTree(
        scopeType: scope.scopeType,
        scopeId: scope.scopeId,
      );
    }
    _folders = _foldersAtCurrentPath();
  }

  List<V2File> _foldersAtCurrentPath() {
    var level = _fullDeliveryTree;
    for (var i = 1; i < _path.length; i++) {
      final target = _path[i].id;
      V2File? found;
      for (final n in level) {
        if (_keyOf(n) == target) {
          found = n;
          break;
        }
      }
      if (found == null) return const [];
      level = found.children;
    }
    return level.where((n) => n.isFolder).toList();
  }

  void _enterFolder(V2File folder) {
    if (_isSelf(folder)) return; // 不能进入待移动文件自身（子孙由此天然不可达）
    // 继承目录不接收移入，其子级也一并不作为可选目标（V7，对齐 :211）
    if (folder.inherited) return;
    setState(() {
      _path = [..._path, _MovePathItem(id: _keyOf(folder), name: folder.name)];
    });
    _loadFolders();
  }

  void _goToRoot() {
    if (_path.length == 1) return;
    setState(() => _path = [_MovePathItem(id: null, name: _rootLabel)]);
    _loadFolders();
  }

  void _goTo(int idx) {
    if (idx >= _path.length - 1) return;
    setState(() => _path = _path.sublist(0, idx + 1));
    _loadFolders();
  }

  Future<void> _confirm() async {
    if (_moving || widget.files.isEmpty) return;
    setState(() => _moving = true);
    // V3：根目录目标 id 恒为 '0'（资源区 dest_group_file_id / 下发区 parent_id 同款）
    final Object destId = _currentFolderId ?? '0';
    // V8：串行、失败不回滚、部分成功照样关窗回调
    final r = await v2MoveFilesSerially(
      api: widget.api,
      files: widget.files,
      zoneKey: widget.zoneKey,
      destId: destId,
    );
    if (!mounted) return;
    setState(() => _moving = false);
    if (r.allOk) {
      showTopNotice(context, r.ok == 1 ? '已移动' : '已移动 ${r.ok} 项',
          level: NoticeLevel.success);
    } else if (r.partial) {
      showTopNotice(
        context,
        '已移动 ${r.ok} 项，${r.failMessages.length} 项失败：${r.uniqueFailMessage}',
        level: NoticeLevel.warning,
      );
    } else {
      // 全失败：**保持弹窗打开**，让用户换个目标重试
      // （对齐 MoveTargetDialog.vue:262 —— throw 后既不 emit moved 也不关窗）
      showTopNotice(
        context,
        r.uniqueFailMessage.isNotEmpty ? r.uniqueFailMessage : '移动失败',
        level: NoticeLevel.error,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.files.isNotEmpty ? widget.files.first.name : '';
    final listHeight = context.isNarrow ? 420.0 : 280.0;

    return ResponsiveDialogScaffold(
      title: '移动到',
      maxWidth: 480,
      // 移动进行中禁止关窗：串行队列跑一半被中断，用户看不到剩余项的结果
      showCloseButton: !_moving,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.files.length > 1
                ? '将「$first」等 ${widget.files.length} 项移动到当前区的其他位置'
                : '将「$first」移动到当前区的其他位置',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          // V4：跨区移动不允许，把限制显式写给用户，避免"为什么看不到另一个区"的疑问
          Text(
            _isDist ? '仅限本下发目标内移动，不支持移动到资源区' : '仅限「$_rootLabel」内移动，不支持跨区移动',
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 10),
          _buildNav(),
          Container(
            constraints: BoxConstraints(maxHeight: listHeight),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFF1F3F6)),
                right: BorderSide(color: Color(0xFFF1F3F6)),
                bottom: BorderSide(color: Color(0xFFF1F3F6)),
              ),
              borderRadius:
                  BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
            ),
            child: _buildList(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF007AFF).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '目标：$_currentLabel',
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _moving ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: (_moving || widget.files.isEmpty) ? null : _confirm,
            child: _moving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('移动到此'),
          ),
        ],
      ),
    );
  }

  Widget _buildNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFBFC),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFFF1F3F6))),
        borderRadius:
            BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _goToRoot,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.home, size: 13, color: Color(0xFF007AFF)),
                    SizedBox(width: 4),
                    Text('根目录',
                        style: TextStyle(fontSize: 12, color: Color(0xFF007AFF))),
                  ],
                ),
              ),
            ),
            for (var i = 1; i < _path.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('/', style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
              ),
              InkWell(
                onTap: () => _goTo(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(_path[i].name,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF007AFF))),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text('加载中...',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ),
      );
    }
    if (_folders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text('当前目录无子文件夹',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(4),
      itemCount: _folders.length,
      itemBuilder: (context, i) {
        final f = _folders[i];
        final self = _isSelf(f);
        // V7：继承目录灰掉且不可进入
        final disabled = self || f.inherited;
        return Opacity(
          opacity: disabled ? 0.4 : 1,
          child: InkWell(
            onTap: disabled ? null : () => _enterFolder(f),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  const Icon(LucideIcons.folderOpen,
                      size: 15, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                    ),
                  ),
                  if (self)
                    const Text('（自身）',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)))
                  else if (f.inherited)
                    const Text('（继承，不可移入）',
                        style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.chevronRight,
                      size: 14, color: Color(0xFFCBD5E1)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
