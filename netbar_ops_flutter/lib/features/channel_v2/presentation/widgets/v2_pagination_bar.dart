import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 通道 V2 弹窗底部分页条（策略列表 / 任务列表共用）。
///
/// 【为什么抽成共用组件，留痕】策略列表与任务列表各写了一份几乎逐字重复的分页
/// Row，同一类溢出问题已经各修各的修了两轮（策略侧修完任务侧还在溢出）。抽一份后
/// 布局约束只有一处口径。
///
/// 【不溢出的三条保证】
///   1. 外层 Wrap(spaceBetween)：放得下左右分列，放不下整块换行，Row 那种硬溢出
///      不可能发生；
///   2. 每页下拉用固定宽 Container 自绘边框 + `isExpanded: true`：DropdownButton
///      默认按「最宽 item 的固有宽度」撑开自己，宽度不够时内部 Row 会硬溢出；
///      isExpanded 把 item 塞进 Expanded，最坏只会 ellipsis，不会溢出；
///   3. 翻页按钮去掉 IconButton 的 48x48 默认约束，压到 32x32。
class V2PaginationBar extends StatelessWidget {
  /// 总条数
  final int total;

  /// 当前页（1 基）
  final int page;

  /// 每页条数
  final int perPage;

  /// 窄屏（手机）：隐藏「每页条数」下拉，只留翻页
  final bool isNarrow;

  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onPerPageChanged;

  static const List<int> perPageOptions = [10, 20, 50];

  /// 每页下拉宽度。
  /// 算式：文本区 + 左右 padding(8*2) + 箭头(14)。「20 条/页」在 12 号字下约
  /// 45~60px（中文全角 12px/字），这里留到 ~98px 文本区，是实测截断宽度的近 2 倍。
  static const double _perPageWidth = 120;

  static const double _controlHeight = 32;

  const V2PaginationBar({
    super.key,
    required this.total,
    required this.page,
    required this.perPage,
    required this.isNarrow,
    required this.onPageChanged,
    required this.onPerPageChanged,
  });

  int get _maxPage {
    if (perPage <= 0) return 1;
    final count = (total + perPage - 1) ~/ perPage;
    return count < 1 ? 1 : count;
  }

  @override
  Widget build(BuildContext context) {
    final maxPage = _maxPage;

    Widget pageButton(IconData icon, VoidCallback? onPressed) => IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
              minWidth: _controlHeight, minHeight: _controlHeight),
          splashRadius: 18,
        );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        Text('共 $total 条',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 6,
          children: [
            if (!isNarrow) _buildPerPage(),
            pageButton(
              LucideIcons.chevronLeft,
              page > 1 ? () => onPageChanged(page - 1) : null,
            ),
            Text('$page / $maxPage',
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF1F2937))),
            pageButton(
              LucideIcons.chevronRight,
              page < maxPage ? () => onPageChanged(page + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  /// 每页条数下拉。
  ///
  /// 【不走 DropdownButtonFormField】InputDecorator 的可见边框高度是它自己按内容
  /// 算的（isDense 时 minContainerHeight=0），外面套 SizedBox 只是占位、并不会把
  /// 边框撑到指定高度 → 和旁边控件对不齐。这里边框由 Container 自绘，高度即
  /// [_controlHeight]，与翻页按钮严格一致。
  Widget _buildPerPage() {
    return Container(
      width: _perPageWidth,
      height: _controlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDCDFE6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: perPage,
          isDense: true,
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown,
              size: 14, color: Color(0xFF9CA3AF)),
          style: const TextStyle(fontSize: 12, color: Color(0xFF1F2937)),
          items: [
            for (final v in perPageOptions)
              DropdownMenuItem(
                value: v,
                // maxLines/ellipsis 是 isExpanded 的配套：宽度不够时截断而不是
                // 换行（换行会顶破 isDense 的 24px 按钮高度）
                child: Text('$v 条/页',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null || v == perPage) return;
            onPerPageChanged(v);
          },
        ),
      ),
    );
  }
}
