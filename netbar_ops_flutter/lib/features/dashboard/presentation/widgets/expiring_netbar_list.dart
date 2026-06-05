import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../netbar/data/netbar_api.dart';

/// 网维即将到期网吧列表（橙色主题）
///
/// 参考 toolboxPage DashboardPage 的「网维即将到期」区块，
/// 展示全局范围内网维到期 / 即将到期的网吧。点击行回调 [onTapNetbar]。
class ExpiringNetbarList extends StatelessWidget {
  final List<Netbar> netbars;
  final bool loading;
  final Object? error;
  final VoidCallback? onRefresh;
  final ValueChanged<Netbar>? onTapNetbar;
  final bool compact;
  /// 嵌入模式（手机端全屏弹窗内）：去外壳/标题栏，列表撑满高度
  final bool embedded;

  const ExpiringNetbarList({
    super.key,
    required this.netbars,
    this.loading = false,
    this.error,
    this.onRefresh,
    this.onTapNetbar,
    this.compact = false,
    this.embedded = false,
  });

  // 橙色主题色（与 toolboxPage 对齐）
  static const Color _border = Color(0xFFFED7AA);
  static const Color _titleColor = Color(0xFF9A3412);
  static const Color _headerBg = Color(0xFFFFF7ED);
  static const Color _badgeBg = Color(0xFFFFEDD5);
  static const Color _nameColor = Color(0xFF7C2D12);
  static const Color _accent = Color(0xFFEA580C);

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
              const Icon(LucideIcons.clock, color: _accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                '网维即将到期',
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
                  color: _accent,
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
            color: _accent.withValues(alpha: 0.08),
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
        iconColor: _accent,
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
    // 3) 成功但无数据 → 空状态
    if (netbars.isEmpty) {
      return _StatePlaceholder(
        icon: Icons.event_available_outlined,
        iconColor: Colors.grey.shade400,
        message: '暂无即将到期的网吧',
      );
    }
    // 4) 有数据 → 表头 + 列表
    final listView = ListView.separated(
      shrinkWrap: !embedded,
      padding: EdgeInsets.zero,
      itemCount: netbars.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: Color(0xFFFFEDD5)),
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
          Expanded(flex: 3, child: Center(child: Text('到期时间', style: h()))),
          Expanded(flex: 3, child: Center(child: Text('状态', style: h()))),
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

  Widget _rowWide(Netbar n) {
    final st = _expireStatus(n.maintenanceExpiredAt);
    return Row(
      children: [
        Expanded(flex: 4, child: _nameCell(n)),
        Expanded(
          flex: 3,
          child: Center(
            child: Text(
              _formatDate(n.maintenanceExpiredAt),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _titleColor,
              ),
            ),
          ),
        ),
        Expanded(flex: 3, child: Center(child: _statusTag(st))),
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

  Widget _rowCompact(Netbar n) {
    final st = _expireStatus(n.maintenanceExpiredAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _nameCell(n)),
            _statusTag(st),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _formatDate(n.maintenanceExpiredAt),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _titleColor,
              ),
            ),
            const Spacer(),
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

  Widget _statusTag(_ExpireStatus st) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: st.color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        st.text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: st.color,
        ),
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

/// 到期状态结果
class _ExpireStatus {
  final String text;
  final Color color;
  const _ExpireStatus(this.text, this.color);
}

/// 到期状态：按「天」为单位计算（移植 toolboxPage expireStatus）
/// - 已到期 → 红；今天到期 → 红；<=7天 → 橙；其余 → 灰
_ExpireStatus _expireStatus(String? raw) {
  const red = Color(0xFFDC2626);
  const orange = Color(0xFFEA580C);
  final grey = Colors.grey.shade500;
  if (raw == null || raw.isEmpty) return _ExpireStatus('-', grey);
  final dt = DateTime.tryParse(raw);
  if (dt == null) return _ExpireStatus('-', grey);
  final l = dt.toLocal();
  final target = DateTime(l.year, l.month, l.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diffDays = target.difference(today).inDays;
  if (diffDays < 0) return const _ExpireStatus('已到期', red);
  if (diffDays == 0) return const _ExpireStatus('今天到期', red);
  return _ExpireStatus('$diffDays天后到期', diffDays <= 7 ? orange : grey);
}

/// 解析后端时间字符串并格式化为 `yyyy-MM-dd`
String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '-';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final l = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}
