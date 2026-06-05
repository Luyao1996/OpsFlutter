import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../netbar/data/netbar_api.dart';

/// 终端异常网吧列表（红色主题）
///
/// 参考 toolboxPage DashboardPage 的「终端异常网吧」区块，
/// 展示全局范围内终端在线异常的网吧。点击行回调 [onTapNetbar]。
class AlertNetbarList extends StatelessWidget {
  final List<Netbar> netbars;
  final bool loading;
  final Object? error;
  final VoidCallback? onRefresh;
  final ValueChanged<Netbar>? onTapNetbar;
  final bool compact;
  /// 嵌入模式（手机端全屏弹窗内）：去外壳/标题栏，列表撑满高度
  final bool embedded;

  const AlertNetbarList({
    super.key,
    required this.netbars,
    this.loading = false,
    this.error,
    this.onRefresh,
    this.onTapNetbar,
    this.compact = false,
    this.embedded = false,
  });

  // 红色主题色（与 toolboxPage 对齐）
  static const Color _border = Color(0xFFFECACA);
  static const Color _titleColor = Color(0xFFB91C1C);
  static const Color _headerBg = Color(0xFFFEF2F2);
  static const Color _badgeBg = Color(0xFFFEE2E2);
  static const Color _nameColor = Color(0xFF7F1D1D);
  static const Color _numColor = Color(0xFFB91C1C);
  static const Color _dotColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        // 标题栏（嵌入弹窗时隐藏，用弹窗自身标题栏）
        if (!embedded) ...[
          Row(
            children: [
              const Icon(LucideIcons.alertTriangle, color: _dotColor, size: 20),
              const SizedBox(width: 8),
              const Text(
                '终端异常网吧',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _titleColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _dotColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${netbars.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              if (onRefresh != null)
                _RefreshButton(
                  color: _titleColor,
                  loading: loading,
                  onTap: onRefresh!,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // 内容区：失败 / 加载中 / 空 / 有数据 四态
        embedded ? Expanded(child: _buildBody()) : _buildBody(),
      ],
    );

    // 嵌入模式（手机端弹窗内）：无卡片外壳，撑满父级
    if (embedded) return column;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: column,
    );
  }

  /// 内容区四态切换
  Widget _buildBody() {
    // 1) 请求失败 → 错误提示，可点击刷新
    if (error != null) {
      return _StatePlaceholder(
        icon: Icons.error_outline,
        iconColor: _dotColor,
        message: '加载失败，点击刷新重试',
        onTap: onRefresh,
      );
    }
    // 2) 加载中且无旧数据 → loading
    if (loading && netbars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    // 3) 成功但无数据 → 空状态（绿色，表示一切正常）
    if (netbars.isEmpty) {
      return const _StatePlaceholder(
        icon: Icons.check_circle_outline,
        iconColor: Color(0xFF34C759),
        message: '暂无终端异常网吧，终端运行正常',
      );
    }
    // 4) 有数据 → 表头 + 列表
    final listView = ListView.separated(
      shrinkWrap: !embedded,
      padding: EdgeInsets.zero,
      itemCount: netbars.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFFFEE2E2)),
      itemBuilder: (context, index) => _buildRow(context, netbars[index]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (!compact) _buildHeader(),
        // 嵌入弹窗：占满剩余高度滚动；区块模式：限高 320 内部滚动
        embedded
            ? Expanded(child: Scrollbar(child: listView))
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Scrollbar(child: listView),
              ),
      ],
    );
  }

  Widget _buildHeader() {
    TextStyle h() => const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: _titleColor,
        );
    return Container(
      color: _headerBg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('网吧名称 / ID', style: h())),
          Expanded(flex: 2, child: Center(child: Text('状态', style: h()))),
          Expanded(flex: 2, child: Center(child: Text('在线/终端', style: h()))),
          Expanded(flex: 3, child: Center(child: Text('离线时间', style: h()))),
          Expanded(flex: 2, child: Center(child: Text('所属分组', style: h()))),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, Netbar n) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapNetbar == null ? null : () => onTapNetbar!(n),
        hoverColor: _badgeBg.withValues(alpha: 0.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: compact ? _rowCompact(n) : _rowWide(n),
        ),
      ),
    );
  }

  // ---- 宽屏：表格行 ----
  Widget _rowWide(Netbar n) {
    return Row(
      children: [
        Expanded(flex: 4, child: _nameCell(n)),
        Expanded(flex: 2, child: Center(child: _statusTag(n))),
        Expanded(flex: 2, child: Center(child: _onlineCell(n))),
        Expanded(
          flex: 3,
          child: Center(
            child: Text(
              _formatDateTime(n.offlineTime),
              style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Center(
            child: Text(
              _groupNames(n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ),
      ],
    );
  }

  // ---- 手机：卡片行 ----
  Widget _rowCompact(Netbar n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _nameCell(n)),
            _statusTag(n),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _onlineCell(n),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _formatDateTime(n.offlineTime),
                style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
              ),
            ),
            Flexible(
              child: Text(
                _groupNames(n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _nameCell(Netbar n) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _badgeBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${n.id}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            n.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _nameColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusTag(Netbar n) {
    final text = n.isOnline ? '异常' : '离线';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _dotColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _titleColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineCell(Netbar n) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _numColor,
        ),
        children: [
          TextSpan(text: '${n.terminalOnline}'),
          const TextSpan(
            text: ' / ',
            style: TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.normal),
          ),
          TextSpan(text: '${n.terminalCount}'),
        ],
      ),
    );
  }

  String _groupNames(Netbar n) {
    final g = n.groups;
    if (g != null && g.isNotEmpty) return g.map((e) => e.name).join('、');
    return '-';
  }
}

/// 状态占位（失败 / 空），可选点击回调
class _StatePlaceholder extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String message;
  final VoidCallback? onTap;

  const _StatePlaceholder({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
    if (onTap == null) return Center(child: content);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Center(child: content),
    );
  }
}

/// 刷新按钮（带 loading 旋转占位）
class _RefreshButton extends StatelessWidget {
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(LucideIcons.refreshCw, size: 14, color: color),
            const SizedBox(width: 4),
            Text('刷新', style: TextStyle(fontSize: 13, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 解析后端时间字符串并格式化为 `yyyy-MM-dd HH:mm`
String _formatDateTime(String? raw) {
  if (raw == null || raw.isEmpty) return '-';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final l = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
