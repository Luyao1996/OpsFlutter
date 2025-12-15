import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/terminal_dock_provider.dart';
import '../../../shared/services/terminal_window_bridge.dart';
import '../../../shared/utils/platform_utils.dart';
import '../data/terminal_api.dart';
import 'widgets/terminal_card.dart';

/// 终端列表 Provider - 移除 autoDispose 避免频繁重载
final terminalsProvider = FutureProvider<List<Terminal>>((ref) async {
  final netbar = ref.watch(currentNetbarProvider);
  final api = ref.read(terminalApiProvider);
  return api.getAll(netbarId: netbar.id);
});

class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> {
  String _searchQuery = '';
  bool _isListView = false;
  String _filterStatus = 'all'; // all, busy, online_idle, offline
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  // 右键菜单状态
  OverlayEntry? _menuOverlay;
  Terminal? _selectedTerminal;

  @override
  void dispose() {
    _hideContextMenu();
    super.dispose();
  }

  void _hideContextMenu() {
    _menuOverlay?.remove();
    _menuOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final terminalsAsync = ref.watch(terminalsProvider);

    return GestureDetector(
      onTap: _hideContextMenu,
      child: Container(
        color: AppColors.iosBg,
        child: terminalsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _buildErrorView(error.toString()),
          data: (terminals) => _buildContent(terminals),
        ),
      ),
    );
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
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.alertTriangle, color: Colors.red.shade500),
            ),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
            const SizedBox(height: 8),
            Text(error, style: TextStyle(fontSize: 14, color: Colors.red.shade600)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.invalidate(terminalsProvider),
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('重新加载'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<Terminal> terminals) {
    // 分离关键设备和普通终端
    final devices = terminals.where((t) => t.isKeyDevice).toList();
    final clients = terminals.where((t) => !t.isKeyDevice).toList();

    // 过滤
    var filteredClients = clients.where((t) {
      // 搜索过滤
      if (_searchQuery.isNotEmpty && !t.name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      // 状态过滤
      if (_filterStatus == 'online_idle' && t.status != 1) return false; // 在线空闲
      if (_filterStatus == 'busy' && t.status != 2) return false; // 使用中
      if (_filterStatus == 'offline' && t.status != 0) return false; // 离线

      return true;
    }).toList();

    // 排序
    filteredClients.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0: // 终端ID (Name)
          // Try to parse as int for correct numerical sorting
          final intA = int.tryParse(a.name) ?? 0;
          final intB = int.tryParse(b.name) ?? 0;
          if (intA > 0 && intB > 0) {
            cmp = intA.compareTo(intB);
          } else {
            cmp = a.name.compareTo(b.name);
          }
          break;
        case 1: // 状态
          cmp = b.status.compareTo(a.status);
          break;
        case 2: // IP
          cmp = a.ip.compareTo(b.ip);
          break;
        case 3: cmp = a.mac.compareTo(b.mac); break;
        case 4: cmp = a.uptime.compareTo(b.uptime); break;
        case 5:
          final aTime = _parseToCst(a.updatedAt);
          final bTime = _parseToCst(b.updatedAt);
          cmp = (aTime ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(bTime ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        default:
          // 默认排序：在线在前
          if (a.status > 0 && b.status == 0) return -1;
          if (a.status == 0 && b.status > 0) return 1;
          return 0;
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (context.isPhone) {
      return DefaultTabController(
        length: 2,
        initialIndex: 0, // 默认“关键设备状态”
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Container(
                height: 40,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.iosCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.iosSeparator),
                  boxShadow: AppShadows.sm,
                ),
                child: TabBar(
                  indicator: BoxDecoration(
                    color: AppColors.iosBlue,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey.shade600,
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  unselectedLabelStyle:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: '关键设备状态'),
                    Tab(text: '终端列表'),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // 关键设备状态
                  CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildDevicesSection(
                          devices,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        ),
                      ),
                    ],
                  ),
                  // 终端列表
                  CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _buildToolbar(filteredClients.length),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        sliver: _isListView
                            ? SliverToBoxAdapter(
                                child: _buildTerminalDataTable(filteredClients),
                              )
                            : SliverLayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.crossAxisExtent;
                                  int columns = 2;
                                  if (width >= 640) columns = 3;

                                  return SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      childAspectRatio: 0.9,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final terminal = filteredClients[index];
                                        return TerminalCard(
                                          terminal: terminal,
                                          onTap: () => _openTerminalDetail(terminal),
                                          onSecondaryTapDown: (details) =>
                                              _showContextMenu(details, terminal),
                                        );
                                      },
                                      childCount: filteredClients.length,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 关键设备区域
        SliverToBoxAdapter(child: _buildDevicesSection(devices)),
        // 工具栏
        SliverToBoxAdapter(child: _buildToolbar(filteredClients.length)),
        // 终端列表/网格
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          sliver: _isListView
              ? SliverToBoxAdapter(
                  child: _buildTerminalDataTable(filteredClients),
                )
              : SliverLayoutBuilder(
                  builder: (context, constraints) {
                    // 响应式列数: 类似 Vue 的 grid-cols-2 sm:3 md:4 lg:5 xl:6 2xl:8
                    final width = constraints.crossAxisExtent;
                    int columns;
                    if (width >= 1536) {
                      columns = 8;
                    } else if (width >= 1280) {
                      columns = 6;
                    } else if (width >= 1024) {
                      columns = 5;
                    } else if (width >= 768) {
                      columns = 4;
                    } else if (width >= 640) {
                      columns = 3;
                    } else {
                      columns = 2;
                    }

                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        childAspectRatio: 0.9, // 接近 16:9 图片 + 底部名称栏
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final terminal = filteredClients[index];
                          return TerminalCard(
                            terminal: terminal,
                            onTap: () => _openTerminalDetail(terminal),
                            onSecondaryTapDown: (details) => _showContextMenu(details, terminal),
                          );
                        },
                        childCount: filteredClients.length,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTerminalDataTable(List<Terminal> terminals) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.iosCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator),
        boxShadow: AppShadows.sm,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  showCheckboxColumn: false,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  columns: [
                    _buildDataColumn('终端ID', 0),
                    _buildDataColumn('状态', 1),
                    _buildDataColumn('IP地址', 2),
                    _buildDataColumn('MAC地址', 3),
                    _buildDataColumn('在线时长', 4),
                    _buildDataColumn('最后活动时间', 5),
                  ],
                  rows: terminals.map((t) {
                    return DataRow(
                      cells: [
                        DataCell(Text(t.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(_buildStatusCell(t.status)),
                        DataCell(Text(t.ip, style: const TextStyle(fontFamily: 'monospace'))),
                        DataCell(Text(t.mac, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                        DataCell(Text(t.uptime)),
                        DataCell(Text(_formatUpdatedAt(t.updatedAt))),
                      ],
                      onSelectChanged: (selected) {
                        if (selected == true) _openTerminalDetail(t);
                      },
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  DataColumn _buildDataColumn(String label, int index) {
    return DataColumn(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      onSort: (colIndex, ascending) {
        setState(() {
          _sortColumnIndex = colIndex;
          _sortAscending = ascending;
        });
      },
    );
  }

  Widget _buildStatusCell(int status) {
    Color color;
    String text;
    if (status == 0) {
      color = Colors.grey;
      text = '离线';
    } else if (status == 1) {
      color = Colors.green;
      text = '在线空闲';
    } else if (status == 2) {
      color = Colors.orange;
      text = '使用中';
    } else {
      color = Colors.grey; // Default for unknown status
      text = '未知';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  /// 打开终端详情
  void _openTerminalDetail(Terminal terminal) {
    if (isDesktopPlatform) {
      final lastTab =
          ref.read(terminalDockProvider.notifier).lastTabFor(terminal.id);
      TerminalWindowBridge.openTerminalWindow(
        terminalId: terminal.id,
        initialTab: lastTab,
        terminalSnapshot: terminal,
      );
      return;
    }
    context.push('/terminal/${terminal.id}');
  }

  /// 转换并格式化为东八区时间
  String _formatUpdatedAt(String? value) {
    final dt = _parseToCst(value);
    if (dt == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  DateTime? _parseToCst(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final parsed = DateTime.parse(value);
      return parsed.toUtc().add(const Duration(hours: 8));
    } catch (_) {
      return null;
    }
  }

  /// 显示右键菜单
  void _showContextMenu(TapDownDetails details, Terminal terminal) {
    _hideContextMenu();
    _selectedTerminal = terminal;

    final overlay = Overlay.of(context);
    final position = details.globalPosition;

    _menuOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 背景遮罩
          Positioned.fill(
            child: GestureDetector(
              onTap: _hideContextMenu,
              child: Container(color: Colors.transparent),
            ),
          ),
          // 菜单
          Positioned(
            left: position.dx,
            top: position.dy,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: AppColors.iosCard, // 使用 AppColors.iosCard
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.iosSeparator), // 使用 AppColors.iosSeparator
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildContextMenuItem('查看详情', LucideIcons.eye, () {
                      _hideContextMenu();
                      _openTerminalDetail(terminal);
                    }),
                    _buildMenuDivider(),
                    _buildContextMenuItem('重启', LucideIcons.refreshCw, () => _remoteAction('restart')),
                    _buildContextMenuItem('关机', LucideIcons.power, () => _remoteAction('shutdown')),
                    _buildContextMenuItem('唤醒', LucideIcons.sunrise, () => _remoteAction('wakeup')),
                    _buildMenuDivider(),
                    _buildContextMenuItem('截图', LucideIcons.camera, () => _remoteAction('screenshot')),
                    _buildContextMenuItem('远程桌面', LucideIcons.monitor, () => _remoteAction('remote')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(_menuOverlay!);
  }

  Widget _buildContextMenuItem(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      hoverColor: AppColors.iosHover, // 添加悬停效果
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.iosGray), // 使用 AppColors.iosGray
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333))), // 使用更深的灰色文本
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(height: 1, color: AppColors.iosSeparator); // 使用 AppColors.iosSeparator
  }

  /// 远程操作
  Future<void> _remoteAction(String action) async {
    _hideContextMenu();
    if (_selectedTerminal == null) return;

    try {
      final api = ref.read(terminalApiProvider);
      await api.remote(_selectedTerminal!.id, action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作 $action 已发送到 ${_selectedTerminal!.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildDevicesSection(List<Terminal> devices, {EdgeInsets? padding}) {
    return Padding(
      padding: padding ?? const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (context.isPhone)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '关键设备状态',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '服务器 / 控制台 / 收银机 / 路由器',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            )
          else
            Row(
              children: [
                const Text('关键设备状态',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text(
                  '服务器 / 控制台 / 收银机 / 路由器',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
              ],
            ),
          const SizedBox(height: 16),
          // 使用响应式网格布局
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isPhone = context.isPhone;
              int columns;
              if (isPhone) {
                columns = width >= 320 ? 2 : 1;
              } else if (width >= 1024) {
                columns = 4;
              } else if (width >= 640) {
                columns = 2;
              } else {
                columns = 1;
              }

              final gap = isPhone ? 12.0 : 16.0;
              final itemWidth = (width - (columns - 1) * gap) / columns;
              final itemHeight = isPhone ? 160.0 : 200.0;

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  // 关键设备卡片 (使用 TerminalCard 样式)
                  ...devices.map((d) => SizedBox(
                    width: itemWidth,
                    height: itemHeight, // 固定高度
                    child: TerminalCard(
                      terminal: d,
                      onTap: () => _openTerminalDetail(d),
                      onSecondaryTapDown: (details) => _showContextMenu(details, d),
                    ),
                  )),
                  // 路由器卡片
                  SizedBox(
                    width: itemWidth,
                    height: itemHeight,
                    child: _buildRouterCard(),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 路由器卡片 - 与 Vue 版本一致
  Widget _buildRouterCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.iosCard, // 使用 AppColors.iosCard
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator), // 使用 AppColors.iosSeparator
        boxShadow: AppShadows.sm,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部: 图标 + 标题 + 延迟
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(LucideIcons.router, size: 16, color: Colors.blue.shade600),
                        ),
                        const SizedBox(width: 8),
                        Text('路由器', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('2ms', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
                    ),
                  ],
                ),
                const Spacer(),
                // 上行带宽
                _buildBandwidthRow('上行', '50 Mbps', 0.25, Colors.blue.shade500),
                const SizedBox(height: 8),
                // 下行带宽
                _buildBandwidthRow('下行', '200 Mbps', 0.75, Colors.green.shade500),
              ],
            ),
          ),
          // 装饰性大图标
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(
              LucideIcons.router,
              size: 80,
              color: AppColors.iosBg.withOpacity(0.5), // 使用 AppColors.iosBg 并调整透明度
            ),
          ),
        ],
      ),
    );
  }

  /// 带宽行 (含进度条)
  Widget _buildBandwidthRow(String label, String value, double progress, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.grey.shade900)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(int count) {
    final isNarrow = MediaQuery.of(context).size.width < 900;
    if (isNarrow && _isListView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _isListView = false);
      });
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('终端列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
              ),
              const Spacer(),
              // 搜索框
              if (!isNarrow)
                SizedBox(
                  width: 260,
                  child: _buildSearchBox(),
                ),
              if (!isNarrow) const SizedBox(width: 12),
              // 筛选按钮
              PopupMenuButton<String>(
                tooltip: '筛选',
                offset: const Offset(0, 40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.iosCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.iosSeparator),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Icon(LucideIcons.filter, size: 18, color: _filterStatus != 'all' ? AppColors.iosBlue : Colors.grey.shade600),
                ),
                onSelected: (val) => setState(() => _filterStatus = val),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'all', child: Text('全部')),
                  const PopupMenuItem(value: 'busy', child: Text('使用中')),
                  const PopupMenuItem(value: 'online_idle', child: Text('在线空闲')),
                  const PopupMenuItem(value: 'offline', child: Text('离线')),
                ],
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: AppColors.iosSeparator),
              const SizedBox(width: 8),
              // 视图切换
              if (!isNarrow)
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.iosCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.iosSeparator),
                    boxShadow: AppShadows.sm,
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      _buildToolbarSwitchItem(
                        icon: LucideIcons.layoutGrid,
                        isSelected: !_isListView,
                        onTap: () => setState(() => _isListView = false),
                      ),
                      _buildToolbarSwitchItem(
                        icon: LucideIcons.list,
                        isSelected: _isListView,
                        onTap: () => setState(() => _isListView = true),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
              // 刷新按钮
              _buildToolbarButton(
                icon: LucideIcons.refreshCw,
                tooltip: '刷新',
                onPressed: () => ref.invalidate(terminalsProvider),
                size: isNarrow ? 40 : 44,
              ),
            ],
          ),
          if (isNarrow) const SizedBox(height: 12),
          if (isNarrow) _buildSearchBox(),
        ],
      ),
    );
  }

  /// 构建工具栏按钮
  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double size = 44,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.iosCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator),
        boxShadow: AppShadows.sm,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: Colors.grey.shade600),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tightFor(width: size, height: size),
        splashRadius: size / 2,
      ),
      ),
    );
  }

  /// 构建工具栏切换项 (例如, 网格/列表视图切换)
  Widget _buildToolbarSwitchItem({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.iosBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : Colors.grey.shade500,
          ),
        ), // AnimatedContainer 结束
      ), // GestureDetector 结束
    ); // MouseRegion 结束
  }

  Widget _buildSearchBox() {
    return Container(
      width: double.infinity,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.iosCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.iosSeparator),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                filled: false,
                hintText: '搜索机号...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
