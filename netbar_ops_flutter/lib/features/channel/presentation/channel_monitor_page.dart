import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/startup_item_api.dart';
import '../data/startup_monitor_models.dart';
import 'widgets/monitor_item_dialog.dart';

class ChannelMonitorPage extends ConsumerStatefulWidget {
  const ChannelMonitorPage({super.key});

  @override
  ConsumerState<ChannelMonitorPage> createState() => _ChannelMonitorPageState();
}

class _ChannelMonitorPageState extends ConsumerState<ChannelMonitorPage> {
  final StartupItemMonitorApi _api = StartupItemMonitorApi();
  final TextEditingController _searchController = TextEditingController();

  List<NetbarMonitorData> _data = [];
  bool _loading = true;
  String? _error;

  String _statusFilter = 'all'; // all | online | offline
  bool _showOnlyAbnormal = false;
  bool _showCharts = true;

  ProviderSubscription<CurrentNetbar>? _netbarSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _netbarSub = ref.listenManual(currentNetbarProvider, (prev, next) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _netbarSub?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final netbar = ref.read(currentNetbarProvider);
      // 使用网吧名称作为 keyword 搜索
      final list = await _api.getMonitor(keyword: netbar.name);
      setState(() {
        _data = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _isItemAbnormal(StartupItemStats item) {
    return item.failureRate > 10 || item.shortLifeRate > 50;
  }

  List<NetbarMonitorData> get _filteredData {
    final query = _searchController.text.trim().toLowerCase();
    return _data
        .map((netbar) {
          var items = netbar.items;
          if (query.isNotEmpty) {
            items = items
                .where(
                  (i) =>
                      i.name.toLowerCase().contains(query) ||
                      i.path.toLowerCase().contains(query),
                )
                .toList();
          }
          if (_showOnlyAbnormal) {
            items = items.where(_isItemAbnormal).toList();
          }
          return NetbarMonitorData(
            id: netbar.id,
            name: netbar.name,
            group: netbar.group,
            status: netbar.status,
            terminalCount: netbar.terminalCount,
            items: items,
          );
        })
        .where((netbar) {
          final matchesStatus =
              _statusFilter == 'all' || netbar.status == _statusFilter;
          final matchesAbnormal =
              !_showOnlyAbnormal || netbar.items.any(_isItemAbnormal);
          final matchesSearch = query.isEmpty
              ? true
              : netbar.items.isNotEmpty ||
                    netbar.name.toLowerCase().contains(query);
          return matchesStatus && matchesAbnormal && matchesSearch;
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 900;
    final content = _error != null
        ? _buildError()
        : _loading
        ? const Center(child: CircularProgressIndicator())
        : _buildList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          _buildHeader(isNarrow: isNarrow),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool isNarrow}) {
    if (isNarrow) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '通道监控',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_data.length} 家网吧',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const Spacer(),
                _buildChartsToggle(),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildStatusChip('全部', 'all', AppColors.iosBlue),
                _buildStatusChip('在线', 'online', Colors.green),
                _buildStatusChip('离线', 'offline', Colors.grey),
                _buildAbnormalToggle(),
              ],
            ),
            const SizedBox(height: 10),
            _buildSearch(width: double.infinity),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '通道监控',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_data.length} 家网吧',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  _buildStatusChips(),
                  const SizedBox(width: 12),
                  _buildAbnormalToggle(),
                  const SizedBox(width: 12),
                  _buildChartsToggle(),
                  const SizedBox(width: 12),
                  _buildSearch(width: 220),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    final isActive = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? color.withOpacity(0.3) : Colors.grey.shade200,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: color.withOpacity(0.12), blurRadius: 12)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != 'all')
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            if (value != 'all') const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildStatusChip('全部', 'all', AppColors.iosBlue),
        _buildStatusChip('在线', 'online', Colors.green),
        _buildStatusChip('离线', 'offline', Colors.grey),
      ],
    );
  }

  Widget _buildAbnormalToggle() {
    final isActive = _showOnlyAbnormal;
    return GestureDetector(
      onTap: () => setState(() => _showOnlyAbnormal = !isActive),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.red.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? Colors.red.shade200 : Colors.grey.shade200,
          ),
          boxShadow: isActive
              ? [BoxShadow(color: Colors.red.withOpacity(0.12), blurRadius: 12)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertTriangle,
              size: 16,
              color: isActive ? Colors.red : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Text(
              '只看异常',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.red : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsToggle() {
    return IconButton(
      onPressed: () => setState(() => _showCharts = !_showCharts),
      icon: Icon(
        _showCharts ? LucideIcons.layoutGrid : LucideIcons.barChart2,
        size: 18,
        color: _showCharts ? AppColors.iosBlue : Colors.grey.shade600,
      ),
      tooltip: _showCharts ? '收起图表' : '显示图表',
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(
          _showCharts ? Colors.blue.shade50 : Colors.white,
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Widget _buildSearch({required double width}) {
    return SizedBox(
      width: width,
      height: 38,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textAlignVertical: TextAlignVertical.center,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '搜索启动项...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            isDense: true,
            suffixIcon: Icon(
              LucideIcons.search,
              size: 16,
              color: Colors.grey.shade400,
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 38,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.alertTriangle,
                color: Colors.red.shade500,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '加载监控数据失败',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('重新加载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade700,
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final data = _filteredData;
    final isNarrow = MediaQuery.sizeOf(context).width < 900;
    final netbar = ref.read(currentNetbarProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          if (_showCharts) _buildChartsSection(),
          if (_showCharts) const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (data.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.monitorOff,
                      size: 32,
                      color: Colors.blue.shade300,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    netbar.name ?? '当前网吧',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '暂无通道启动项配置',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => context.go('/channel-management?tab=startup&zone=BRANCH'),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('前往配置启动项'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.iosBlue,
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: data
                  .map((nb) => _buildNetbarCard(nb, isNarrow: isNarrow))
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    final stats = _buildStatusStats(_data);
    final ranking = _buildRanking(_data);
    const double boxHeight = 260;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1100;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: _HealthTrendChart(
                  width: constraints.maxWidth,
                  height: boxHeight,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _StatusDistributionChart(
                  width: constraints.maxWidth,
                  stats: stats,
                  height: boxHeight,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _AbnormalRankingChart(
                  width: constraints.maxWidth,
                  ranking: ranking,
                  height: boxHeight,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            _HealthTrendChart(width: constraints.maxWidth, height: boxHeight),
            const SizedBox(height: 16),
            _StatusDistributionChart(
              width: constraints.maxWidth,
              stats: stats,
              height: boxHeight,
            ),
            const SizedBox(height: 16),
            _AbnormalRankingChart(
              width: constraints.maxWidth,
              ranking: ranking,
              height: boxHeight,
            ),
          ],
        );
      },
    );
  }

  Map<String, int> _buildStatusStats(List<NetbarMonitorData> data) {
    int normal = 0, warning = 0, critical = 0;
    for (final nb in data) {
      for (final item in nb.items) {
        if (item.failureRate > 10) {
          critical++;
        } else if (item.failureRate > 0 || item.shortLifeRate > 20) {
          warning++;
        } else {
          normal++;
        }
      }
    }
    return {'normal': normal, 'warning': warning, 'critical': critical};
  }

  List<_RankingItem> _buildRanking(List<NetbarMonitorData> data) {
    final list = data
        .map(
          (nb) => _RankingItem(
            name: nb.name,
            failures: nb.items.fold<int>(
              0,
              (sum, item) => sum + item.failureCount,
            ),
          ),
        )
        .where((r) => r.failures > 0)
        .toList();
    list.sort((a, b) => b.failures.compareTo(a.failures));
    return list.take(5).toList();
  }

  Widget _buildNetbarCard(NetbarMonitorData netbar, {required bool isNarrow}) {
    final abnormalCount = netbar.items.where((i) => _isItemAbnormal(i)).length;
    final hasAbnormal = abnormalCount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Stack(
        children: [
          if (hasAbnormal)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(hasAbnormal ? 16 : 16, 16, 16, 16),
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: netbar.status == 'online'
                                  ? Colors.green.shade100
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              netbar.status == 'online'
                                  ? LucideIcons.wifi
                                  : LucideIcons.wifiOff,
                              color: netbar.status == 'online'
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  netbar.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildTag(
                                      netbar.group,
                                      Colors.grey.shade100,
                                      Colors.grey.shade600,
                                    ),
                                    if (netbar.status == 'online')
                                      _buildTag(
                                        '${netbar.terminalCount} 终端',
                                        Colors.green.shade50,
                                        Colors.green.shade700,
                                      ),
                                    if (abnormalCount > 0)
                                      _buildTag(
                                        '$abnormalCount 异常',
                                        Colors.red.shade50,
                                        Colors.red.shade700,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (netbar.items.isEmpty)
                        Row(
                          children: [
                            Icon(
                              LucideIcons.monitor,
                              size: 16,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '暂无监控数据',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: netbar.items
                              .map((item) => _buildItemChip(item, netbar))
                              .toList(),
                        ),
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 240,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: netbar.status == 'online'
                                      ? Colors.green.shade100
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  netbar.status == 'online'
                                      ? LucideIcons.wifi
                                      : LucideIcons.wifiOff,
                                  color: netbar.status == 'online'
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      netbar.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _buildTag(
                                          netbar.group,
                                          Colors.grey.shade100,
                                          Colors.grey.shade600,
                                        ),
                                        if (netbar.status == 'online')
                                          _buildTag(
                                            '${netbar.terminalCount} 终端',
                                            Colors.green.shade50,
                                            Colors.green.shade700,
                                          ),
                                        if (abnormalCount > 0)
                                          _buildTag(
                                            '$abnormalCount 异常',
                                            Colors.red.shade50,
                                            Colors.red.shade700,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: netbar.items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        LucideIcons.monitor,
                                        size: 16,
                                        color: Colors.grey.shade300,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '暂无监控数据',
                                        style: TextStyle(
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: netbar.items
                                      .map(
                                        (item) =>
                                            _buildItemChip(item, netbar),
                                      )
                                      .toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buildItemChip(StartupItemStats item, NetbarMonitorData netbar) {
    final failureRate = item.failureRate;
    final isCritical = failureRate > 10 || item.shortLifeRate > 50;
    final isWarning =
        !isCritical && (failureRate > 0 || item.shortLifeRate > 20);
    final bgColor = isCritical
        ? Colors.red.shade50
        : isWarning
        ? Colors.amber.shade50
        : Colors.blue.shade50;
    final fgColor = isCritical
        ? Colors.red.shade700
        : isWarning
        ? Colors.amber.shade700
        : AppColors.iosBlue;

    return GestureDetector(
      onTap: () {
        final startupItemId = int.tryParse(item.id);
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.3),
          builder: (context) => MonitorItemDialog(
            item: item,
            netbarName: netbar.name,
            onClose: () => Navigator.of(context).pop(),
            onEdit: startupItemId == null
                ? null
                : () async {
                    await ref.read(currentNetbarProvider.notifier).setNetbar(
                          netbar.id,
                          netbar.name,
                          netbar.status,
                        );
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    context.go('/channel-management?tab=startup&zone=BRANCH&edit_startup_item_id=$startupItemId');
                  },
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCritical
                ? Colors.red.shade100
                : isWarning
                ? Colors.amber.shade100
                : Colors.blue.shade100,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.playCircle, size: 16, color: fgColor),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isCritical
                        ? LucideIcons.alertTriangle
                        : LucideIcons.checkCircle2,
                    size: 14,
                    color: fgColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${failureRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fgColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankingItem {
  final String name;
  final int failures;
  _RankingItem({required this.name, required this.failures});
}

class _HealthTrendChart extends StatelessWidget {
  final double width;
  final double height;
  const _HealthTrendChart({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    const data = [
      {'time': '00:00', 'successRate': 98},
      {'time': '04:00', 'successRate': 99},
      {'time': '08:00', 'successRate': 95},
      {'time': '12:00', 'successRate': 94},
      {'time': '16:00', 'successRate': 96},
      {'time': '20:00', 'successRate': 92},
      {'time': '24:00', 'successRate': 97},
    ];

    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: height, maxHeight: height),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '启动项健康度趋势 (24h)',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SfCartesianChart(
              plotAreaBorderWidth: 0,
              primaryXAxis: CategoryAxis(
                majorGridLines: const MajorGridLines(width: 0),
                axisLine: const AxisLine(width: 0),
                majorTickLines: const MajorTickLines(width: 0),
                labelStyle: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 10,
                ),
              ),
              primaryYAxis: NumericAxis(
                isVisible: false,
                minimum: 80,
                maximum: 100,
              ),
              series: <CartesianSeries>[
                SplineAreaSeries<Map<String, Object>, String>(
                  dataSource: data,
                  xValueMapper: (d, _) => d['time'] as String,
                  yValueMapper: (d, _) => d['successRate'] as num,
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade100],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderColor: Colors.green.shade500,
                  borderWidth: 2,
                  splineType: SplineType.natural,
                ),
              ],
            ),
          ),
          Text(
            '成功率趋势',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusDistributionChart extends StatelessWidget {
  final double width;
  final Map<String, int> stats;
  final double height;

  const _StatusDistributionChart({
    required this.width,
    required this.stats,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    final total =
        (stats['normal'] ?? 0) +
        (stats['warning'] ?? 0) +
        (stats['critical'] ?? 0);

    final data = [
      _PieData('正常', stats['normal'] ?? 0, Colors.green),
      _PieData('警告', stats['warning'] ?? 0, Colors.amber),
      _PieData('异常', stats['critical'] ?? 0, Colors.red),
    ];

    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: height, maxHeight: height),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '启动状态分布',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SfCircularChart(
                    legend: const Legend(isVisible: false),
                    series: <CircularSeries>[
                      DoughnutSeries<_PieData, String>(
                        dataSource: data,
                        xValueMapper: (d, _) => d.label,
                        yValueMapper: (d, _) => d.value,
                        pointColorMapper: (d, _) => d.color,
                        innerRadius: '60%',
                        dataLabelSettings: const DataLabelSettings(
                          isVisible: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: data.map((d) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: d.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${d.label} ${d.value}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Text(
                  '总计 $total 个启动项',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AbnormalRankingChart extends StatelessWidget {
  final double width;
  final List<_RankingItem> ranking;
  final double height;

  const _AbnormalRankingChart({
    required this.width,
    required this.ranking,
    this.height = 260,
  });

  @override
  Widget build(BuildContext context) {
    final max = ranking.isEmpty
        ? 1
        : ranking.map((r) => r.failures).reduce((a, b) => a > b ? a : b);

    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: height, maxHeight: height),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '异常网吧 TOP 5',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (ranking.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  '暂无异常数据',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          else
            ...ranking.map((r) {
              final ratio = r.failures / max;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: ratio,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red.shade500,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 28,
                      child: Text(
                        r.failures.toString(),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PieData {
  final String label;
  final int value;
  final Color color;

  _PieData(this.label, this.value, this.color);
}
