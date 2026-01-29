import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/channel_monitor_api.dart';

/// 通道监控数据 Provider
final channelMonitorProvider = FutureProvider.autoDispose<ChannelMonitorResponse>((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  final api = ChannelMonitorApi();
  // 使用当前网吧名称作为关键词查询
  return api.getChannelMonitor(
    page: 1,
    size: 100,
    type: 'merchant',
    keyword: netbar.name,
  );
});

/// 表格行数据模型（展平后的启动项数据）
class MonitorRowData {
  final int merchantId;
  final String merchantName;
  final int terminalCount;
  final int terminalAvg;
  final bool isOnline;
  final String groupNames;
  final String startupPath;
  final int startupTotal;
  final int startupFail;
  final int durationLt1;
  final int durationLt10;
  final int durationLt20;
  final int rowSpan; // 用于合并单元格

  MonitorRowData({
    required this.merchantId,
    required this.merchantName,
    required this.terminalCount,
    required this.terminalAvg,
    required this.isOnline,
    required this.groupNames,
    required this.startupPath,
    required this.startupTotal,
    required this.startupFail,
    required this.durationLt1,
    required this.durationLt10,
    required this.durationLt20,
    this.rowSpan = 1,
  });
}

class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> {
  String _statusFilter = ''; // '', '1' 在线, '0' 离线

  @override
  Widget build(BuildContext context) {
    final monitorAsync = ref.watch(channelMonitorProvider);
    final netbar = ref.watch(currentNetbarProvider);
    final isPhone = context.isPhone;

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Column(
        children: [
          // 头部
          _buildHeader(netbar.name ?? '监控中心'),
          // 工具栏
          _buildToolbar(),
          // 内容区
          Expanded(
            child: monitorAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => _buildErrorView(err.toString()),
              data: (response) {
                final rows = _buildTableRows(response.merchants);
                final filteredRows = _filterRows(rows);
                if (filteredRows.isEmpty) {
                  return _buildEmptyView();
                }
                return isPhone
                    ? _buildMobileList(filteredRows)
                    : _buildDesktopTable(filteredRows);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            '通道监控',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.iosBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.iosBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => ref.invalidate(channelMonitorProvider),
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          // 状态筛选
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                isDense: true,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                icon: Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade500),
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部状态')),
                  DropdownMenuItem(value: '1', child: Text('在线')),
                  DropdownMenuItem(value: '0', child: Text('离线')),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? ''),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建表格行数据（展平启动项）
  List<MonitorRowData> _buildTableRows(List<ChannelMerchant> merchants) {
    final rows = <MonitorRowData>[];
    for (final m in merchants) {
      if (m.startups.isEmpty) {
        rows.add(MonitorRowData(
          merchantId: m.id,
          merchantName: m.name,
          terminalCount: m.terminalCount,
          terminalAvg: m.terminalAvg,
          isOnline: m.isOnline,
          groupNames: m.groupNames,
          startupPath: '',
          startupTotal: 0,
          startupFail: 0,
          durationLt1: 0,
          durationLt10: 0,
          durationLt20: 0,
          rowSpan: 1,
        ));
      } else {
        for (int i = 0; i < m.startups.length; i++) {
          final s = m.startups[i];
          rows.add(MonitorRowData(
            merchantId: m.id,
            merchantName: m.name,
            terminalCount: m.terminalCount,
            terminalAvg: m.terminalAvg,
            isOnline: m.isOnline,
            groupNames: m.groupNames,
            startupPath: s.path,
            startupTotal: s.analysis.startupTotal,
            startupFail: s.analysis.startupFail,
            durationLt1: s.analysis.durationLt1,
            durationLt10: s.analysis.durationLt10,
            durationLt20: s.analysis.durationLt20,
            rowSpan: i == 0 ? m.startups.length : 0,
          ));
        }
      }
    }
    return rows;
  }

  /// 过滤行
  List<MonitorRowData> _filterRows(List<MonitorRowData> rows) {
    if (_statusFilter.isEmpty) return rows;
    final isOnline = _statusFilter == '1';
    return rows.where((r) => r.isOnline == isOnline).toList();
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(fontSize: 14, color: Colors.red.shade600)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(channelMonitorProvider),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.inbox, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('暂无数据', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  /// 桌面端表格
  Widget _buildDesktopTable(List<MonitorRowData> rows) {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
          headingTextStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
          dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          columnSpacing: 16,
          horizontalMargin: 16,
          columns: const [
            DataColumn(label: Text('ID')),
            DataColumn(label: Text('网络名称')),
            DataColumn(label: Text('终端数')),
            DataColumn(label: Text('近7日终端')),
            DataColumn(label: Text('所属分组')),
            DataColumn(label: Text('状态')),
            DataColumn(label: Text('启动项')),
            DataColumn(label: Text('启动次数')),
            DataColumn(label: Text('失败次数')),
            DataColumn(label: Text('<1分钟')),
            DataColumn(label: Text('<10分钟')),
            DataColumn(label: Text('<20分钟')),
          ],
          rows: rows.map((r) => _buildDataRow(r)).toList(),
        ),
      ),
    );
  }

  DataRow _buildDataRow(MonitorRowData row) {
    return DataRow(
      cells: [
        DataCell(_buildIdBadge(row.merchantId)),
        DataCell(Text(row.merchantName, style: const TextStyle(fontWeight: FontWeight.w500))),
        DataCell(_buildTerminalCell(row.terminalCount)),
        DataCell(Text('${row.terminalAvg}')),
        DataCell(_buildGroupCell(row.groupNames)),
        DataCell(_buildStatusTag(row.isOnline)),
        DataCell(_buildStartupPath(row.startupPath)),
        DataCell(_buildStatCell(row.startupTotal, Colors.green)),
        DataCell(_buildFailCell(row.startupFail)),
        DataCell(_buildDurationTag(row.durationLt1, Colors.red)),
        DataCell(_buildDurationTag(row.durationLt10, Colors.orange)),
        DataCell(_buildDurationTag(row.durationLt20, Colors.grey)),
      ],
    );
  }

  Widget _buildIdBadge(int id) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '$id',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3B82F6),
        ),
      ),
    );
  }

  Widget _buildTerminalCell(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.monitor, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Text('$count'),
      ],
    );
  }

  Widget _buildGroupCell(String groupNames) {
    if (groupNames == '-') return Text(groupNames, style: TextStyle(color: Colors.grey.shade400));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.folder, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Text(groupNames),
      ],
    );
  }

  Widget _buildStatusTag(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.green : Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline ? '在线' : '离线',
            style: TextStyle(
              fontSize: 12,
              color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupPath(String path) {
    if (path.isEmpty) return Text('-', style: TextStyle(color: Colors.grey.shade400));
    return Tooltip(
      message: path,
      child: Text(
        path,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildStatCell(int value, Color color) {
    return Text(
      '$value',
      style: TextStyle(fontWeight: FontWeight.w500, color: value > 0 ? color : Colors.grey.shade400),
    );
  }

  Widget _buildFailCell(int value) {
    if (value == 0) return Text('0', style: TextStyle(color: Colors.grey.shade400));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.alertTriangle, size: 12, color: Colors.red.shade400),
        const SizedBox(width: 2),
        Text('$value', style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildDurationTag(int value, Color color) {
    if (value == 0) return Text('-', style: TextStyle(color: Colors.grey.shade300));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$value',
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  /// 移动端列表
  Widget _buildMobileList(List<MonitorRowData> rows) {
    // 按商户分组
    final Map<int, List<MonitorRowData>> grouped = {};
    for (final r in rows) {
      grouped.putIfAbsent(r.merchantId, () => []).add(r);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final merchantId = grouped.keys.elementAt(index);
        final merchantRows = grouped[merchantId]!;
        final first = merchantRows.first;
        return _buildMobileCard(first, merchantRows);
      },
    );
  }

  Widget _buildMobileCard(MonitorRowData merchant, List<MonitorRowData> startupRows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部
          Row(
            children: [
              _buildIdBadge(merchant.merchantId),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  merchant.merchantName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              _buildStatusTag(merchant.isOnline),
            ],
          ),
          const SizedBox(height: 12),
          // 基本信息
          Row(
            children: [
              _buildInfoItem('分组', merchant.groupNames),
              const SizedBox(width: 24),
              _buildInfoItem('终端数', '${merchant.terminalCount} (近7日: ${merchant.terminalAvg})'),
            ],
          ),
          // 启动项列表
          if (startupRows.any((r) => r.startupPath.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '启动项监控',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                  ),
                  const SizedBox(height: 8),
                  ...startupRows.where((r) => r.startupPath.isNotEmpty).map((r) => _buildStartupItem(r)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _buildStartupItem(MonitorRowData r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.startupPath,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildStatTag('启动', r.startupTotal, Colors.green),
              const SizedBox(width: 8),
              _buildStatTag('失败', r.startupFail, Colors.red),
              const Spacer(),
              _buildDurationBadge('<1m', r.durationLt1, Colors.red),
              const SizedBox(width: 4),
              _buildDurationBadge('<10m', r.durationLt10, Colors.orange),
              const SizedBox(width: 4),
              _buildDurationBadge('<20m', r.durationLt20, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTag(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: value > 0 ? color : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _buildDurationBadge(String label, int value, Color color) {
    final hasValue = value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: hasValue ? color.withOpacity(0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 10,
          color: hasValue ? color : Colors.grey.shade400,
        ),
      ),
    );
  }
}
