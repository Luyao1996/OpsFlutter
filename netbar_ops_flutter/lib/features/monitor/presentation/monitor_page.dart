import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
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

    // 过滤和排序
    var filteredClients = clients.where((t) {
      if (_searchQuery.isEmpty) return true;
      return t.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    // 在线的排前面
    filteredClients.sort((a, b) {
      if (a.status > 0 && b.status == 0) return -1;
      if (a.status == 0 && b.status > 0) return 1;
      return 0;
    });

    return CustomScrollView(
      slivers: [
        // 关键设备区域
        SliverToBoxAdapter(child: _buildDevicesSection(devices)),
        // 工具栏
        SliverToBoxAdapter(child: _buildToolbar(filteredClients.length)),
        // 终端网格 - 使用响应式布局
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          sliver: SliverLayoutBuilder(
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

  /// 打开终端详情
  void _openTerminalDetail(Terminal terminal) {
    context.push('/terminal/${terminal.id}');
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(height: 1, color: Colors.grey.shade200);
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

  Widget _buildDevicesSection(List<Terminal> devices) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('关键设备状态', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
              int columns;
              if (width >= 1024) {
                columns = 4;
              } else if (width >= 640) {
                columns = 2;
              } else {
                columns = 1;
              }

              final itemWidth = (width - (columns - 1) * 16) / columns;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  // 关键设备卡片 (使用 TerminalCard 样式)
                  ...devices.map((d) => SizedBox(
                    width: itemWidth,
                    height: 140, // 固定高度
                    child: TerminalCard(
                      terminal: d,
                      onTap: () => _openTerminalDetail(d),
                      onSecondaryTapDown: (details) => _showContextMenu(details, d),
                    ),
                  )),
                  // 路由器卡片
                  SizedBox(
                    width: itemWidth,
                    height: 140,
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
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
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
              color: Colors.grey.shade100,
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
              // 筛选按钮
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: AppShadows.sm,
                ),
                child: IconButton(
                  onPressed: () {
                    // TODO: 打开筛选菜单
                  },
                  icon: Icon(LucideIcons.filter, size: 18, color: Colors.grey.shade600),
                  tooltip: '筛选',
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: Colors.grey.shade300),
              const SizedBox(width: 8),
              // 视图切换
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: AppShadows.sm,
                      ),
                      child: Icon(LucideIcons.layoutGrid, size: 16, color: Colors.grey.shade700),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.all(6),
                      child: Icon(LucideIcons.settings, size: 16, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 刷新按钮
              IconButton(
                onPressed: () => ref.invalidate(terminalsProvider),
                icon: Icon(LucideIcons.refreshCw, size: 18, color: Colors.grey.shade500),
                tooltip: '刷新',
              ),
              if (!isNarrow) const SizedBox(width: 12),
              if (!isNarrow)
                SizedBox(
                  width: 260,
                  child: _buildSearchBox(),
                ),
            ],
          ),
          if (isNarrow) const SizedBox(height: 12),
          if (isNarrow) _buildSearchBox(),
        ],
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      width: double.infinity,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
                hintText: '搜索机号...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
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
