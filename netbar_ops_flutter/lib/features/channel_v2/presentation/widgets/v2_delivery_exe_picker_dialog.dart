import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/providers/permission_provider.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../strategy/presentation/widgets/strategy_exe_picker.dart';
import '../../data/channel_v2_api.dart';
import '../../data/channel_v2_models.dart';
import 'v2_toolbar_controls.dart';

/// 「下发文件区」执行文件选择器（T8c-2 新增，评审 A-4）。
///
/// 【为什么不复用共享层 ExePickerDialog，留痕】
/// ExePickerDialog 的数据源是**资源中心**（resource_api → /file/view），
/// 而 web 的策略表单选执行文件走的是**下发文件区**
/// （FileSelectDialog source='delivery' → GET /delivery/tree，
/// StrategyAddDialog.vue:247-250）。两者是不同的文件域：资源中心里存在的文件
/// 未必已下发到目标网吧，按它填出来的路径客户端取不到文件。
/// ExePickerDialog 本体被 V1 两个旧页面在用，不改；这里新写一个下发树版本。
///
/// 【导航范式】沿用 v2_move_target_dialog 的**逐层导航**（一次只显示当前层），
/// 而不是 web 的"整棵树就地展开"：web 实测单个 scope 有 **9308 个节点**
/// （FileSelectDialog.vue:178-179），一次性铺平成可滚动树在移动端不可用。
/// 逐层导航 + ListView.builder 虚拟化，任一层都只构建可见行。
///
/// 【路径拼接规则，与 web 逐字符对齐】
/// 下发节点没有绝对路径，路径由前端按层级拼：
///   `path = parentPath.isEmpty ? name : '$parentPath/$name'`
/// 逐字符对照 FileSelectDialog.vue:232（indexDeliveryTree）与 :489（flatList）：
///   - 分隔符是 **'/'**（不是 Windows 的 '\'）
///   - **不含**根节点名（web 的 walk 以 parentPath='' 起步，根层节点的 path 就是自身
///     name；面包屑上的「下发文件区」只是 UI 文案，不进路径）
///   - **无**前导 '/'、无 './'、无 '../'
/// 这三条任何一条对不上，下发到客户端的执行路径就全错。
///
/// 【待真机验证】web 表单里执行文件输入框的 placeholder 是 `../开机文件/开机启动.exe`
/// （StrategyAddDialog.vue:81，带 `../` 前缀），而 FileSelectDialog 选完实际回填的是
/// `开机文件/开机启动.exe`（无前缀，见上面的拼接规则）—— web 自身这两处就不一致。
/// 本弹窗按"选择器实际返回值"的口径实现（与 web 运行时行为一致）；
/// 后端到底接受哪一种、是否会自行补 `../`，需真机验证后再定。
class V2DeliveryExePickerDialog extends ConsumerStatefulWidget {
  final ChannelV2Api api;

  /// 显式 scope（对齐 web fileScope，StrategyAddDialog.vue:573-579：
  /// 私有策略编辑态按该策略所属网吧查它自己的下发区，数据量小且贴合实际）。
  /// 传 null 时按当前登录账号身份推导（web resolvedScope，FileSelectDialog.vue:166-173：
  /// group_id 为空或 0 → hq/0，否则 group/<group_id>）。
  final String? scopeType;
  final String? scopeId;

  /// 标题（新增/编辑/本地化复用同一个弹窗时区分用）
  final String title;

  const V2DeliveryExePickerDialog({
    super.key,
    required this.api,
    this.scopeType,
    this.scopeId,
    this.title = '选择执行文件',
  });

  @override
  ConsumerState<V2DeliveryExePickerDialog> createState() =>
      _V2DeliveryExePickerDialogState();
}

/// 导航栈项。
///
/// 【刻意不按 id 定位，留痕】这里直接持有该层的 children 列表引用，而不是像
/// v2_move_target_dialog 那样存 `delivery_node_id ?? id` 再逐层按 id 找回去：
/// web 自己实测过 **delivery_node_id 是整棵下发子树共用一条记录**（9308 个节点只有
/// 6 个不同值，FileSelectDialog.vue:178-179），源文件 id 在树里也可能重复出现 ——
/// 两者都不是唯一行键，按它定位会进错目录 / 选中串行。整棵树只拉一次且全程不重建，
/// 持有引用是安全的。
class _DirItem {
  /// 面包屑显示名
  final String name;

  /// 该目录的**完整虚拟路径**（根层为 ''）。
  /// 必须单独存：从搜索结果里点进一个深层目录时，它的祖先并不在导航栈上，
  /// 拿栈上的 name 拼路径会丢掉中间层级 → 选出来的文件路径直接是错的。
  final String path;

  /// null = 根层（取整棵树）
  final List<V2File>? nodes;
  const _DirItem({required this.name, this.path = '', this.nodes});
}

/// 搜索命中项：节点 + 它的完整虚拟路径
class _Hit {
  final V2File file;
  final String path;
  const _Hit(this.file, this.path);
}

class _V2DeliveryExePickerDialogState
    extends ConsumerState<V2DeliveryExePickerDialog> {
  static const String _rootLabel = '下发文件区';

  final TextEditingController _kw = TextEditingController();

  List<V2File> _tree = const [];
  List<_DirItem> _path = const [_DirItem(name: _rootLabel)];
  bool _loading = true;
  String? _error;

  /// 搜索命中（关键字非空时展示这一份，否则展示当前层）
  List<_Hit> _hits = const [];

  V2File? _selected;
  String? _selectedPath;

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

  ({String scopeType, String scopeId}) _resolveScope() {
    final st = widget.scopeType;
    if (st != null && st.isNotEmpty) {
      return (scopeType: st, scopeId: widget.scopeId ?? '0');
    }
    // 对齐 FileSelectDialog.vue:166-173
    final perm = ref.read(permissionProvider);
    if (perm.isHQUser) return (scopeType: 'hq', scopeId: '0');
    return (scopeType: 'group', scopeId: '${perm.userGroupId}');
  }

  Future<void> _load() async {
    try {
      final scope = _resolveScope();
      final tree = await widget.api.getDeliveryTree(
        scopeType: scope.scopeType,
        scopeId: scope.scopeId,
      );
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '下发文件区加载失败: $e';
        _loading = false;
      });
    }
  }

  /// 当前目录的虚拟路径（**不含**根节点名，见类注释的拼接规则）
  String get _currentDirPath => _path.last.path;

  String _joinPath(String parentPath, String name) =>
      parentPath.isEmpty ? name : '$parentPath/$name';

  /// 当前层的节点（本地导航，整棵树只拉一次）
  List<V2File> _currentLevel() => _path.last.nodes ?? _tree;

  /// 搜索：根层搜全树、子目录搜其子孙（对齐 FileSelectDialog.vue:280-285），
  /// 路径按层级实时拼出来，保证搜索命中项与逐层点选拿到的路径完全一致。
  void _runSearch() {
    final kw = _kw.text.trim().toLowerCase();
    if (kw.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final out = <_Hit>[];
    void walk(List<V2File> nodes, String parentPath) {
      for (final n in nodes) {
        final p = _joinPath(parentPath, n.name);
        if (n.name.toLowerCase().contains(kw)) out.add(_Hit(n, p));
        if (n.children.isNotEmpty) walk(n.children, p);
      }
    }

    walk(_currentLevel(), _currentDirPath);
    setState(() => _hits = out);
  }

  /// 进入目录。[path] 是该目录的完整虚拟路径（搜索结果里点进来时它含祖先层级，
  /// 面包屑上也直接显示完整路径，避免"看着在根下、实际在深层"）。
  void _enter(V2File folder, String path, {required bool fromSearch}) {
    setState(() {
      _path = [
        ..._path,
        _DirItem(
          name: fromSearch ? path : folder.name,
          path: path,
          nodes: folder.children,
        ),
      ];
      _kw.clear();
      _hits = const [];
    });
  }

  void _goTo(int idx) {
    if (idx >= _path.length - 1) return;
    setState(() {
      _path = _path.sublist(0, idx + 1);
      _kw.clear();
      _hits = const [];
    });
  }

  void _pick(V2File f, String path) {
    setState(() {
      // 用对象同一性判定：下发树里 delivery_node_id / 源文件 id 都可能重复，
      // 按 id 比会把同 id 的另一个节点一起点亮
      if (identical(_selected, f)) {
        _selected = null;
        _selectedPath = null;
      } else {
        _selected = f;
        _selectedPath = path;
      }
    });
  }

  void _confirm() {
    final f = _selected;
    final p = _selectedPath;
    // onlyFile：文件夹不可作为结果（对齐 FileSelectDialog.vue:611-617）
    if (f == null || p == null || f.isFolder) return;
    Navigator.of(context).pop<StrategyExePicked>(
      // group_file_id 取**源文件 id**（V2File.id），不是 delivery_node_id：
      // 提交给后端的 startup[group_file_id] 属于 group_files 的 id 空间，
      // 混用会指向别人的下发记录（对齐 web handleFilePicked :741 `row.group_file_id`）。
      (path: p, groupFileId: f.groupFileId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _kw.text.trim().isNotEmpty;
    return ResponsiveDialogScaffold(
      title: widget.title,
      maxWidth: 560,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            // 搜索框与按钮统一走 v2_toolbar_controls 三件套：原来是
            // `SizedBox(height: 34)` 包 TextField + 裸 OutlinedButton，
            // 前者的边框只有 InputDecorator 自算的 ~20px、后者被全局 density
            // 压到 32px，肉眼就是「搜索框比按钮矮」（用户第三次反馈的位置）。
            child: Row(
              children: [
                Expanded(
                  child: V2ToolbarTextField(
                    controller: _kw,
                    hintText: '按文件名搜索当前目录及其子孙',
                    onSubmitted: (_) => _runSearch(),
                    onChanged: (v) {
                      if (v.trim().isEmpty) _runSearch();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                V2ToolbarButton(label: '搜索', onPressed: _runSearch),
              ],
            ),
          ),
          _buildNav(),
          Expanded(child: _buildList(searching)),
          if (_selectedPath != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF007AFF).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '已选：$_selectedPath',
                style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
              ),
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
            onPressed:
                (_selected != null && !_selected!.isFolder) ? _confirm : null,
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFFFAFBFC),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _path.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('/',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFFCBD5E1))),
                ),
              InkWell(
                onTap: () => _goTo(i),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _path[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      color: i == _path.length - 1
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF007AFF),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool searching) {
    if (_loading) {
      return const Center(
        child: Text('加载中...',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFFF56C6C))),
        ),
      );
    }

    final rows = searching
        ? _hits
        : [
            for (final f in _currentLevel())
              _Hit(f, _joinPath(_currentDirPath, f.name))
          ];
    if (rows.isEmpty) {
      return Center(
        child: Text(searching ? '无匹配文件' : '当前目录为空',
            style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }

    // 单个 scope 实测可达 9308 个节点（web FileSelectDialog.vue:178-179）→ 必须虚拟化
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final hit = rows[i];
        final f = hit.file;
        final isSel = identical(_selected, f) && !f.isFolder;
        return InkWell(
          // onlyFile：文件夹只能进入、不能选中（对齐 FileSelectDialog.vue:555）
          onTap: () => f.isFolder
              ? _enter(f, hit.path, fromSearch: searching)
              : _pick(f, hit.path),
          child: Container(
            color: isSel
                ? const Color(0xFF007AFF).withValues(alpha: 0.06)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Icon(
                  f.isFolder ? LucideIcons.folder : LucideIcons.file,
                  size: 15,
                  color: f.isFolder
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF374151)),
                      ),
                      // 搜索态展示完整虚拟路径，避免同名文件分不清来自哪一层
                      if (searching)
                        Text(
                          hit.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF)),
                        )
                      else if (f.sourceName.isNotEmpty)
                        Text(
                          '来源：${f.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9CA3AF)),
                        ),
                    ],
                  ),
                ),
                if (f.missing)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('源文件缺失',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFFF56C6C))),
                  ),
                if (isSel)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(LucideIcons.check,
                        size: 15, color: Color(0xFF007AFF)),
                  ),
                if (f.isFolder)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(LucideIcons.chevronRight,
                        size: 14, color: Color(0xFFCBD5E1)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 构造一个可注入共享层表单的下发树执行文件选择器。
///
/// 共享层（features/strategy）不认识 channel_v2 的 api / 模型，只认
/// [StrategyExePicker] 这个函数签名；本工厂在 channel_v2 侧把两者接起来。
StrategyExePicker v2DeliveryExePicker(
  ChannelV2Api api, {
  String? scopeType,
  String? scopeId,
  String title = '选择执行文件',
}) {
  return (BuildContext context) => showAdaptive<StrategyExePicked>(
        context,
        (_) => V2DeliveryExePickerDialog(
          api: api,
          scopeType: scopeType,
          scopeId: scopeId,
          title: title,
        ),
        routeName: '/dialog/v2-delivery-exe-picker',
      );
}
