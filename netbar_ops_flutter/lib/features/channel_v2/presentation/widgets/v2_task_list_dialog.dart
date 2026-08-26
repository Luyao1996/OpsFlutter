import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/channel_v2_api.dart';
import '../../data/channel_v2_models.dart';
import '../channel_v2_file_actions.dart' show v2ErrMessage;
import 'v2_pagination_bar.dart';

/// 任务列表弹窗（对齐 web channel-v2/dialogs/TaskListDialog.vue）。
///
/// 只读视图：GET /task 分页展示后台任务（目前只有 /file/extract 投递的解压任务）。
/// 打开方必须包在 ChannelV2Page 的 `_guardDialog` 里（弹窗计数器，快捷键靠它避让）。
class V2TaskListDialog extends StatefulWidget {
  final ChannelV2Api api;

  const V2TaskListDialog({super.key, required this.api});

  @override
  State<V2TaskListDialog> createState() => _V2TaskListDialogState();
}

class _V2TaskListDialogState extends State<V2TaskListDialog> {
  final ScrollController _hScroll = ScrollController();

  int _page = 1;
  int _perPage = 20;
  int _total = 0;
  bool _loading = false;
  String? _error;
  List<V2Task> _items = const [];

  @override
  void initState() {
    super.initState();
    // 对齐 web `watch(visible)` → 打开即拉一次
    _fetch();
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.listTasks(page: _page, perPage: _perPage);
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        // 后端可能纠正页码/页长（如请求页越界），以响应为准回写，
        // 否则分页器显示的页码与实际展示的数据对不上（web:172-173 同款回写）
        _page = result.currentPage;
        _perPage = result.perPage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = v2ErrMessage(e, '获取任务列表失败'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ====== 枚举映射（照抄 web getTypeName / getStatusName / getStatusType） ======

  String _typeName(int? type) => switch (type) {
        100 => '文件解压缩',
        null => '-',
        _ => '$type',
      };

  String _statusName(int? status) => switch (status) {
        0 => '等待中',
        1 => '解压中',
        2 => '成功',
        3 => '失败',
        null => '-',
        _ => '$status',
      };

  /// 对应 element-plus tag type：info / primary / success / danger
  Color _statusColor(int? status) => switch (status) {
        0 => const Color(0xFF909399),
        1 => AppColors.iosBlue,
        2 => const Color(0xFF13CE66),
        3 => AppColors.red,
        _ => const Color(0xFF909399),
      };

  /// 失败且带原因时才有 tooltip（对齐 web:19「status === 3 && row.message」）
  bool _hasFailReason(V2Task t) => t.status == 3 && t.message.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow;
    return ResponsiveDialogScaffold(
      title: '任务列表',
      maxWidth: 1280,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          Expanded(child: _buildBody(isNarrow)),
        ],
      ),
      footer: _buildPagination(isNarrow),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Text(
            _loading ? '加载中…' : '共 $_total 个任务',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _fetch,
            icon: Icon(LucideIcons.refreshCw,
                size: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isNarrow) {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: Text('加载中...',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.red)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _fetch, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('暂无任务',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
      );
    }
    return isNarrow ? _buildCardList() : _buildTable();
  }

  // ---------- 宽屏：表格 ----------

  /// 列定义与 web el-table-column 一一对应（TaskListDialog.vue:10-35）
  static const _columns =
      <({String label, double width, Alignment align})>[
    (label: '任务ID', width: 240.0, align: Alignment.centerLeft),
    (label: '类型', width: 110.0, align: Alignment.centerLeft),
    (label: '任务名称', width: 240.0, align: Alignment.centerLeft),
    (label: '状态', width: 140.0, align: Alignment.center),
    (label: '执行次数', width: 90.0, align: Alignment.center),
    (label: '创建时间', width: 170.0, align: Alignment.center),
    (label: '修改时间', width: 170.0, align: Alignment.center),
  ];

  static const double _rowHeight = 40;

  double get _tableWidth =>
      _columns.fold<double>(0, (sum, c) => sum + c.width);

  Widget _buildTable() {
    return LayoutBuilder(
      builder: (context, cons) {
        final w = _tableWidth > cons.maxWidth ? _tableWidth : cons.maxWidth;
        return Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTableHeader(),
                  Expanded(
                    // 【虚拟化】与策略列表不同，任务行没有子列表，每格恒为单行文本
                    // → 行高固定，可用 itemExtent 让 ListView 跳过逐项布局测量。
                    child: ListView.builder(
                      itemExtent: _rowHeight,
                      itemCount: _items.length,
                      itemBuilder: (_, i) => _buildTableRow(_items[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFFAFBFC),
      height: 36,
      child: Row(
        children: [
          for (final c in _columns)
            SizedBox(
              width: c.width,
              child: Align(
                alignment: c.align,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    c.label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableRow(V2Task t) {
    final cells = <Widget>[
      _ellipsisCell(t.id),
      _ellipsisCell(_typeName(t.type)),
      _ellipsisCell(t.name),
      _statusTag(t, compact: false),
      _ellipsisCell(t.attempt?.toString() ?? '-'),
      _ellipsisCell(t.createdAt),
      _ellipsisCell(t.updatedAt),
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F6))),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _columns.length; i++)
            SizedBox(
              width: _columns[i].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(alignment: _columns[i].align, child: cells[i]),
              ),
            ),
        ],
      ),
    );
  }

  /// 单行省略 + 悬浮看全文（对齐 web `show-overflow-tooltip`）
  Widget _ellipsisCell(String text) {
    final shown = text.isEmpty ? '-' : text;
    return Tooltip(
      message: shown,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        shown,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
      ),
    );
  }

  /// 状态标签；失败且有 message 时挂 tooltip 展示失败原因（web:19-30）
  Widget _statusTag(V2Task t, {required bool compact}) {
    final color = _statusColor(t.status);
    final tag = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_statusName(t.status),
              style: TextStyle(fontSize: compact ? 10 : 11, color: color)),
          if (_hasFailReason(t)) ...[
            const SizedBox(width: 3),
            Icon(LucideIcons.alertCircle, size: compact ? 11 : 12, color: color),
          ],
        ],
      ),
    );
    if (!_hasFailReason(t)) return tag;
    return Tooltip(
      message: t.message,
      // 失败原因常是多行堆栈/命令输出，限宽换行，别拉成一条横线
      preferBelow: false,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      textStyle: const TextStyle(fontSize: 12, color: AppColors.red),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF0F0),
        border: Border.all(color: const Color(0xFFFDE2E2)),
        borderRadius: BorderRadius.circular(6),
      ),
      // 桌面端给"可查看"的光标暗示（web 用 cursor: help）
      child: MouseRegion(cursor: SystemMouseCursors.help, child: tag),
    );
  }

  // ---------- 窄屏：卡片列表（web 自带 mobile 分支 :45-88） ----------

  Widget _buildCardList() {
    // 卡片里任务名/ID 允许换行 → 行高不定，**不能**用 itemExtent（会截断）
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildCard(_items[i]),
    );
  }

  Widget _buildCard(V2Task t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF0F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_typeName(t.type),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF303133))),
              ),
              _statusTag(t, compact: true),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFF5F7FA)),
          _cardRow('任务名称', t.name),
          _cardRow('任务ID', t.id),
          _cardRow('执行次数', t.attempt?.toString() ?? '-'),
          _cardRow('创建时间', t.createdAt),
          _cardRow('修改时间', t.updatedAt),
          // 触屏没有 hover，tooltip 形同虚设 → 失败原因在卡片里直接展开
          if (_hasFailReason(t)) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF0F0),
                border: Border.all(color: const Color(0xFFFDE2E2)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(t.message,
                  style: const TextStyle(fontSize: 12, color: AppColors.red)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text('$label:',
                style: const TextStyle(fontSize: 13, color: Color(0xFF909399))),
          ),
          Expanded(
            child: Text(value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 13, color: Color(0xFF606266))),
          ),
        ],
      ),
    );
  }

  // ---------- 分页 ----------

  /// 用户反馈：本行原来是 `Row + Spacer` + `SizedBox(width:90)` 包
  /// DropdownButtonFormField，且**漏了 `isExpanded: true`** → DropdownButton 按最宽
  /// item 的固有宽度撑开自己，把 90px 顶爆（右溢出）。现统一走共用分页条。
  Widget _buildPagination(bool isNarrow) {
    return V2PaginationBar(
      total: _total,
      page: _page,
      perPage: _perPage,
      isNarrow: isNarrow,
      onPageChanged: (p) {
        _page = p;
        _fetch();
      },
      onPerPageChanged: (v) {
        _perPage = v;
        _page = 1;
        _fetch();
      },
    );
  }
}
