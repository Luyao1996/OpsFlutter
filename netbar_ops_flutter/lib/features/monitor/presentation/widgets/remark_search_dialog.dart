import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/html_text.dart';
import '../../../../shared/utils/natural_sort.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/terminal_api.dart';

/// 备注搜索 —— 对齐 toolboxPage RemoteWakePage.vue:32 的 `<RemarkSearch>`。
///
/// 只收「已写备注」的终端（服务器和客户机一起，服务器带标签区分）：这是备注列表
/// 不是终端列表，把几百台空白机器混进来搜索就废了。新写备注仍走卡片上的备注角标。
///
/// 数据全部派生自已拉到的 terminals（`/terminals` 本来就带 remark），不额外发请求。
class RemarkSearchDialog extends StatefulWidget {
  final List<Terminal> terminals;

  /// 点某一条 → 关闭本窗并交给父级打开备注编辑器
  final void Function(Terminal terminal) onOpen;

  const RemarkSearchDialog({
    super.key,
    required this.terminals,
    required this.onOpen,
  });

  @override
  State<RemarkSearchDialog> createState() => _RemarkSearchDialogState();
}

class _RemarkItem {
  final Terminal terminal;

  /// 备注纯文本。stripHtml 每条都要跑一遍正则，几百台机器 × 每敲一个字重算一次
  /// 会明显卡（web 那边也特意从「每次 stripHtml」改成了整体缓存），所以在这里
  /// 一次性算好，之后搜索只在纯文本上做 contains。
  final String text;
  final String lowerText;
  final String lowerName;
  final String lowerSeat;

  _RemarkItem(this.terminal, this.text)
      : lowerText = text.toLowerCase(),
        lowerName = terminal.name.toLowerCase(),
        lowerSeat = terminal.seatId.toLowerCase();
}

class _RemarkSearchDialogState extends State<RemarkSearchDialog> {
  final _searchCtrl = TextEditingController();
  String _keyword = '';
  late List<_RemarkItem> _items;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  @override
  void didUpdateWidget(covariant RemarkSearchDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.terminals, widget.terminals)) {
      _items = _buildItems();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<_RemarkItem> _buildItems() {
    final out = <_RemarkItem>[];
    for (final t in widget.terminals) {
      final text = stripHtml(t.remark);
      if (text.isEmpty) continue;
      out.add(_RemarkItem(t, text));
    }
    // 机号形如 010 / T9 / T10，走自然序（纯字符串比较会把 T10 排到 T9 前面）
    out.sort((a, b) => naturalCompare(a.terminal.seatId, b.terminal.seatId));
    return out;
  }

  List<_RemarkItem> get _filtered {
    final kw = _keyword.trim().toLowerCase();
    if (kw.isEmpty) return _items;
    return _items
        .where((i) =>
            i.lowerSeat.contains(kw) ||
            i.lowerName.contains(kw) ||
            i.lowerText.contains(kw))
        .toList(growable: false);
  }

  void _open(Terminal terminal) {
    Navigator.of(context).pop();
    widget.onOpen(terminal);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return ResponsiveDialogScaffold(
      title: '备注搜索',
      maxWidth: 560,
      // 列表自己滚，骨架不要再包一层滚动容器（嵌套滚动会让列表吃不到手势）；
      // scrollableBody:false 时骨架也不再套 bodyPadding，内边距自己给
      scrollableBody: false,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: '按机号 / 名称 / 备注内容搜索',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(LucideIcons.x, size: 14),
                        splashRadius: 14,
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _keyword = '');
                        },
                      ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _items.isEmpty
                    ? '本网吧还没有写过备注的机器'
                    : '共 ${_items.length} 台写了备注，命中 ${list.length} 台',
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
            ),
            // 撑满剩余高度：桌面端 body 落在 Flexible 里（maxHeight 有界），
            // 手机端在 Scaffold body 里，两边 Expanded 都成立
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        _items.isEmpty ? '暂无备注' : '没有匹配的备注',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF9CA3AF)),
                      ),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _buildRow(list[i]),
                    ),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(_RemarkItem item) {
    final t = item.terminal;
    final isServer = t.isMainServer || t.isBackupServer;
    return InkWell(
      onTap: () => _open(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.status == 0 ? Colors.grey.shade400 : AppColors.green,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    t.name.isNotEmpty ? t.name : t.seatId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (isServer) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.iosBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      t.deviceTypeLabel,
                      style: TextStyle(fontSize: 10, color: AppColors.iosBlue),
                    ),
                  ),
                ],
                const Spacer(),
                const Icon(LucideIcons.chevronRight,
                    size: 14, color: Color(0xFFC0C4CC)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}
