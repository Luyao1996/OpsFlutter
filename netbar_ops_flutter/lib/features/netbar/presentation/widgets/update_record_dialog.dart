import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_error_view.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/update_status_api.dart';

// ===== 配色对齐 Web 端 UpdateRecordDialog.vue 的设计变量 =====
const Color _cPrimary = Color(0xFF409EFF);
const Color _cWarning = Color(0xFFE6A23C);
const Color _cSuccess = Color(0xFF67C23A);
const Color _cDanger = Color(0xFFF56C6C);
const Color _cText1 = Color(0xFF1F2329);
const Color _cText2 = Color(0xFF646A73);
const Color _cText3 = Color(0xFFA8ABB2);
const Color _cLine = Color(0xFFF2F3F5);
const Color _cInfoDot = Color(0xFFC0C4CC);
const Color _cPlaceholder = Color(0xFFDCDFE6);

/// 行状态元数据，顺序与文案对齐 Web STATUS_META
class _StatusMeta {
  final String value;
  final String label;
  final Color color;
  const _StatusMeta(this.value, this.label, this.color);
}

const List<_StatusMeta> _kStatusMeta = [
  _StatusMeta('none', '未上报', _cInfoDot),
  _StatusMeta('pending', '待更新', _cPrimary),
  _StatusMeta('updating', '更新中', _cWarning),
  _StatusMeta('success', '成功', _cSuccess),
  _StatusMeta('failed', '失败', _cDanger),
];

_StatusMeta _statusMeta(String status) {
  final key = status.toLowerCase();
  for (final m in _kStatusMeta) {
    if (m.value == key) return m;
  }
  // 未知状态按 Web 兜底：原样展示、info 灰；空串归到「未上报」
  return _StatusMeta(key, key.isEmpty ? '未上报' : key, _cInfoDot);
}

/// 概览 chip 定义，key 与 status 查询参数一一对应（all 除外），顺序对齐 Web summaryItems
class _ChipMeta {
  final String key;
  final String label;
  final Color? tone; // null = default 灰
  const _ChipMeta(this.key, this.label, this.tone);
}

const List<_ChipMeta> _kChipMeta = [
  _ChipMeta('all', '全部', null),
  _ChipMeta('none', '未上报', null),
  _ChipMeta('pending', '待更新', _cPrimary),
  _ChipMeta('updating', '更新中', _cWarning),
  _ChipMeta('success', '成功', _cSuccess),
  _ChipMeta('failed', '失败', _cDanger),
  _ChipMeta('suspect', '疑似卡住', _cWarning),
  _ChipMeta('stale', '过期', null),
];

/// 上报的是秒级时间戳；该带的字段没带时后端存 0，按约定显示 --。
/// 列表里省掉年份省空间，tooltip 用完整格式（对齐 Web ts()）
String _ts(int v, {bool full = false}) {
  if (v <= 0) return '--';
  final dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
  return DateFormat(full ? 'yyyy-MM-dd HH:mm:ss' : 'MM-dd HH:mm').format(dt);
}

/// 更新记录对话框
/// 对标 Vue 端 UpdateRecordDialog.vue
class UpdateRecordDialog extends StatefulWidget {
  const UpdateRecordDialog({super.key});

  @override
  State<UpdateRecordDialog> createState() => _UpdateRecordDialogState();
}

class _UpdateRecordDialogState extends State<UpdateRecordDialog> {
  final UpdateStatusApi _api = UpdateStatusApi();
  final TextEditingController _keywordCtrl = TextEditingController();

  List<UpdateStatusRow> _rows = [];
  int _total = 0;
  UpdateStatusSummary _summary = const UpdateStatusSummary();
  int _suspectMinutes = 0;
  bool _loading = false;
  Object? _error;

  int _page = 1;
  // 默认 50 条对齐 Web：一屏装不下由列表自己滚动
  final int _size = 50;

  /// 概览 chip 与搜索共用的状态筛选，落到 status 查询参数
  String _filterStatus = '';

  void _log(String level, String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts][$level][netbar][updateRecord][-] $msg');
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  String get _suspectTip => _suspectMinutes > 0
      ? '已开始更新但超过 $_suspectMinutes 分钟没有后续上报'
      : '已开始更新但长时间没有后续上报';

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getUpdateStatusList(
        page: _page,
        size: _size,
        keyword: _keywordCtrl.text,
        status: _filterStatus,
      );
      if (!mounted) return;
      setState(() {
        _rows = res.rows;
        _total = res.total;
        _summary = res.summary;
        _suspectMinutes = res.suspectMinutes;
        _loading = false;
      });
    } catch (e) {
      _log('ERROR', 'fetch fail page=$_page status=$_filterStatus err=$e');
      if (!mounted) return;
      setState(() {
        // 失败时清空行数据对齐 Web，避免残留旧页与页码错位
        _rows = [];
        _total = 0;
        _error = e;
        _loading = false;
      });
    }
  }

  void _reload() {
    _page = 1;
    _fetch();
  }

  /// 点击 chip：再点同一 chip（或点「全部」）取消筛选，对齐 Web applyChip
  void _applyChip(_ChipMeta item) {
    setState(() {
      _filterStatus =
          (item.key == 'all' || _filterStatus == item.key) ? '' : item.key;
    });
    _reload();
  }

  int _chipCount(String key) {
    switch (key) {
      case 'all':
        return _summary.total;
      case 'none':
        return _summary.none;
      case 'pending':
        return _summary.pending;
      case 'updating':
        return _summary.updating;
      case 'success':
        return _summary.success;
      case 'failed':
        return _summary.failed;
      case 'suspect':
        return _summary.suspect;
      case 'stale':
        return _summary.stale;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '更新记录',
      maxWidth: 1200,
      maxHeight: 900,
      scrollableBody: false,
      // scrollableBody=false 时骨架不套 bodyPadding，内边距自己加
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryBar(),
            const SizedBox(height: 10),
            _buildFilterBar(),
            const SizedBox(height: 12),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
      footer: _buildPagination(),
    );
  }

  // ---------- 状态概览：summary 为全量口径（不随筛选变化），点一下即按该状态筛选 ----------
  Widget _buildSummaryBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kChipMeta.map((item) {
        final active =
            item.key == 'all' ? _filterStatus.isEmpty : _filterStatus == item.key;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _applyChip(item),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFECF5FF) : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: active
                    ? _cPrimary.withOpacity(0.35)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.tone != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: item.tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: active ? _cPrimary : _cText2,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  '${_chipCount(item.key)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? _cPrimary : (item.tone ?? _cText1),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ---------- 搜索 + 计数 + 刷新 ----------
  Widget _buildFilterBar() {
    final searchField = TextField(
      controller: _keywordCtrl,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: '搜索网吧名称 / ID',
        hintStyle: const TextStyle(fontSize: 13, color: _cText3),
        prefixIcon: const Icon(LucideIcons.search, size: 15, color: _cText3),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 32),
        // 清空即重查，对齐 Web el-input 的 @clear="reload"
        suffixIcon: _keywordCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.xCircle, size: 14, color: _cText3),
                splashRadius: 14,
                onPressed: () {
                  _keywordCtrl.clear();
                  setState(() {});
                  _reload();
                },
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _cPrimary, width: 1.5),
        ),
      ),
      // 让清空按钮的显隐跟随输入
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _reload(),
    );

    final queryButton = ElevatedButton(
      onPressed: _reload,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('查询', style: TextStyle(fontSize: 13)),
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 13, color: Color(0xFF909399)),
            children: [
              const TextSpan(text: '当前筛选 '),
              TextSpan(
                text: '$_total',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF303133),
                ),
              ),
              const TextSpan(text: ' 条'),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: '刷新',
          splashRadius: 16,
          onPressed: _loading ? null : _fetch,
          icon: const Icon(LucideIcons.refreshCw, size: 15, color: _cText2),
        ),
      ],
    );

    return LayoutBuilder(builder: (context, constraints) {
      // 窄屏一行放不下：搜索行 + 计数行两段排布
      if (constraints.maxWidth < 500) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              queryButton,
            ]),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerRight, child: meta),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(width: 260, child: searchField),
          const SizedBox(width: 10),
          queryButton,
          const Spacer(),
          meta,
        ],
      );
    });
  }

  // ---------- 内容区：loading 覆盖层压在列表上（对齐 v-loading），失败可重试 ----------
  Widget _buildContent() {
    if (_error != null && _rows.isEmpty) {
      return AppErrorView(error: _error, onRetry: _fetch, compact: true);
    }
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 500;
      final list = _rows.isEmpty && !_loading
          ? const Center(
              child: Text('暂无更新记录',
                  style: TextStyle(fontSize: 13, color: _cText3)),
            )
          : isMobile
              ? _buildMobileList()
              : _buildTable(constraints);
      return Stack(
        children: [
          Positioned.fill(child: list),
          if (_loading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            ),
        ],
      );
    });
  }

  // ---------- 宽屏表格 ----------
  Widget _buildTable(BoxConstraints constraints) {
    // 固定列宽合计约 700，弹窗被压窄时整表横向滚动而不是挤爆
    const double minTableWidth = 1100;
    final tableWidth = constraints.maxWidth < minTableWidth
        ? minTableWidth
        : constraints.maxWidth;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        height: constraints.maxHeight,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE6E8EB)),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildTableHeader(),
              const Divider(height: 1, color: _cLine),
              Expanded(
                child: ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: _cLine),
                  itemBuilder: (context, index) =>
                      _buildTableRow(_rows[index], index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const TextStyle _headerStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
    color: _cText2,
  );

  Widget _headerCell(String label,
      {double? width, int? flex, bool center = false}) {
    final text = Text(label,
        style: _headerStyle,
        textAlign: center ? TextAlign.center : TextAlign.left);
    if (width != null) return SizedBox(width: width, child: text);
    return Expanded(flex: flex ?? 1, child: text);
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFFAFBFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _headerCell('网吧', flex: 3),
          _headerCell('所属分组', flex: 2),
          _headerCell('状态', width: 160, center: true),
          _headerCell('版本号', width: 100, center: true),
          _headerCell('预计更新', width: 110, center: true),
          _headerCell('开始时间', width: 110, center: true),
          _headerCell('完成时间', width: 110, center: true),
          _headerCell('最后上报', width: 110, center: true),
          _headerCell('失败原因', flex: 2),
        ],
      ),
    );
  }

  Widget _timeCell(int v, {double width = 110, bool fullTooltip = false}) {
    final text = Text(
      _ts(v),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: _cText2),
    );
    final child = (fullTooltip && v > 0)
        ? Tooltip(message: _ts(v, full: true), child: text)
        : (v > 0
            ? text
            : const Text('--',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: _cPlaceholder)));
    return SizedBox(width: width, child: Center(child: child));
  }

  Widget _buildTableRow(UpdateStatusRow row, int index) {
    return Container(
      // stripe 隔行浅灰，1300 多行时扫读不串行
      color: index.isOdd ? const Color(0xFFFAFBFC) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: _buildNetbarCell(row)),
          Expanded(
            flex: 2,
            child: row.groupNames.isEmpty
                ? const Text('--',
                    style: TextStyle(fontSize: 13, color: _cPlaceholder))
                : Text(
                    row.groupNames.join('、'),
                    style: const TextStyle(fontSize: 13, color: _cText2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          SizedBox(width: 160, child: Center(child: _buildStatusCell(row))),
          SizedBox(
            width: 100,
            child: Center(
              child: row.version.isEmpty
                  ? const Text('--',
                      style: TextStyle(fontSize: 13, color: _cPlaceholder))
                  : Text('v${row.version}',
                      style: const TextStyle(fontSize: 13, color: _cText2)),
            ),
          ),
          _timeCell(row.expectedAt),
          _timeCell(row.startedAt),
          _timeCell(row.finishedAt),
          _timeCell(row.reportedAt, fullTooltip: true),
          Expanded(
            flex: 2,
            child: row.msg.isEmpty
                ? const Text('--',
                    style: TextStyle(fontSize: 13, color: _cPlaceholder))
                : Tooltip(
                    message: row.msg,
                    child: Text(
                      row.msg,
                      style: const TextStyle(fontSize: 13, color: _cDanger),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetbarCell(UpdateStatusRow row) {
    return Row(
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 34),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${row.merchantId}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF909399)),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            row.merchantName.isEmpty ? '-' : row.merchantName,
            style: const TextStyle(fontSize: 13, color: _cText1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!row.isOnline) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE9E9EB)),
            ),
            child: Text(
              row.offlineDays > 0 ? '离线 ${row.offlineDays}天' : '离线',
              style: const TextStyle(fontSize: 11, color: Color(0xFF909399)),
            ),
          ),
        ],
      ],
    );
  }

  /// 状态圆点 + 文字（比实心 tag 轻），附加「卡住/过期」小标记与状态并排
  Widget _buildStatusCell(UpdateStatusRow row) {
    final meta = _statusMeta(row.status);
    return Wrap(
      spacing: 5,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: meta.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              meta.label,
              // info 类（未上报/未知状态）对齐 web pill：灰点 + 次级灰文字
              style: TextStyle(
                fontSize: 13,
                color: meta.color == _cInfoDot ? _cText2 : meta.color,
              ),
            ),
          ],
        ),
        if (row.isSuspect)
          Tooltip(message: _suspectTip, child: _miniFlag('卡住', warning: true)),
        if (row.isStale)
          Tooltip(message: '该轮记录已过期', child: _miniFlag('过期', warning: false)),
      ],
    );
  }

  Widget _miniFlag(String label, {required bool warning}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: warning ? const Color(0xFFFDF6EC) : const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: warning ? _cWarning : _cText3),
      ),
    );
  }

  // ---------- 手机端多行卡片 ----------
  Widget _buildMobileList() {
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _rows[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE6E8EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 首行：网吧名 + 状态徽章（含卡住/过期附加标记）
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.merchantName.isEmpty
                          ? '网吧${row.merchantId}'
                          : row.merchantName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _cText1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusCell(row),
                ],
              ),
              const SizedBox(height: 6),
              // 次行：分组 + 版本号
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.groupNames.isEmpty ? '--' : row.groupNames.join('、'),
                      style: const TextStyle(fontSize: 12, color: _cText2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.version.isEmpty ? '--' : 'v${row.version}',
                    style: const TextStyle(fontSize: 12, color: _cText2),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 三行：最后上报 + 失败原因（有才显示，红字省略）
              Row(
                children: [
                  Text(
                    '最后上报 ${_ts(row.reportedAt)}',
                    style: const TextStyle(fontSize: 12, color: _cText3),
                  ),
                  if (row.msg.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.msg,
                        style: const TextStyle(fontSize: 12, color: _cDanger),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- 分页（沿用本项目 operation_log_view 的分页样式） ----------
  Widget _buildPagination() {
    final totalPages = (_total / _size).ceil().clamp(1, 99999);
    return Row(
      children: [
        Text(
          '共 $_total 条记录',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const Spacer(),
        Text(
          '第 $_page / $totalPages 页',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        IconButton(
          onPressed: (!_loading && _page > 1)
              ? () {
                  setState(() => _page -= 1);
                  _fetch();
                }
              : null,
          icon: const Icon(LucideIcons.chevronLeft, size: 16),
          tooltip: '上一页',
        ),
        IconButton(
          onPressed: (!_loading && _page < totalPages)
              ? () {
                  setState(() => _page += 1);
                  _fetch();
                }
              : null,
          icon: const Icon(LucideIcons.chevronRight, size: 16),
          tooltip: '下一页',
        ),
      ],
    );
  }
}
