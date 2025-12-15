import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../data/terminal_api.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/providers/terminal_dock_provider.dart';
import '../../../../shared/services/terminal_window_bridge.dart';
import '../../../../shared/services/window_control.dart';
import '../../../../shared/utils/platform_utils.dart';

import 'widgets/file_manager_tab.dart';
import 'widgets/process_manager_tab.dart';
import 'widgets/console_manager_tab.dart';
import 'widgets/hardware_info_tab.dart';
import 'widgets/network_monitor_tab.dart';
import 'widgets/log_manager_tab.dart';
import 'widgets/chat_window_tab.dart';

final terminalDetailProvider = FutureProvider.family<Terminal, int>((ref, terminalId) async {
  final api = ref.read(terminalApiProvider);
  return api.getById(terminalId);
});

class TerminalDetailPage extends ConsumerStatefulWidget {
  final int terminalId;
  final bool isStandaloneWindow;
  final int? windowId;
  final String? initialTab;

  const TerminalDetailPage({
    super.key,
    required this.terminalId,
    this.isStandaloneWindow = false,
    this.windowId,
    this.initialTab,
  });

  @override
  ConsumerState<TerminalDetailPage> createState() => _TerminalDetailPageState();
}

class _TerminalDetailPageState extends ConsumerState<TerminalDetailPage> {
  // 当前选中的功能 Tab
  String _selectedTab = '远程控制';
  Terminal? _liveTerminal;
  bool _refreshing = false;
  bool _isMaximized = false;
  Timer? _heartbeatTimer;

  final List<Map<String, dynamic>> _tabs = [
    {'icon': LucideIcons.gamepad2, 'label': '远程控制'},
    {'icon': LucideIcons.fileText, 'label': '文件管理'},
    {'icon': LucideIcons.activity, 'label': '进程管理'},
    {'icon': LucideIcons.terminal, 'label': '终端命令'},
    {'icon': LucideIcons.cpu, 'label': '硬件配置'},
    {'icon': LucideIcons.network, 'label': '网络监控'},
    {'icon': LucideIcons.fileSpreadsheet, 'label': '日志分析'},
    {'icon': LucideIcons.messageSquare, 'label': '聊天窗口'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialTab != null && widget.initialTab!.isNotEmpty) {
      _selectedTab = widget.initialTab!;
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshHeartbeat(widget.terminalId, silent: true);
    });

    if (isDesktopPlatform && widget.isStandaloneWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final wid = widget.windowId ?? 0;
        final maximized = await WindowControl.isMaximized(wid);
        if (mounted) setState(() => _isMaximized = maximized);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final terminalAsync = ref.watch(terminalDetailProvider(widget.terminalId));
    final isNarrow = context.isNarrow || context.isPhone;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6), // 接近 Vue 项目的背景灰
      body: terminalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (terminal) => Column(
          children: [
            _buildHeader(_liveTerminal ?? terminal, isNarrow: isNarrow),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isNarrow ? 12.0 : 16.0),
                child: isNarrow
                    ? Column(
                        children: [
                          _buildTabBar(isNarrow: true),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _buildRightContent(
                              _liveTerminal ?? terminal,
                              isNarrow: true,
                              showOverviewCards: _selectedTab == '远程控制',
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 左侧栏：实时画面 + 系统状态 + 备注
                          SizedBox(
                            width: 380,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildScreenPreviewCard(terminal),
                                  const SizedBox(height: 16),
                                  _buildSystemStatusCard(terminal),
                                  const SizedBox(height: 16),
                                  _buildRemarkCard(terminal),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 右侧栏：功能区
                          Expanded(
                            child: Column(
                              children: [
                                _buildTabBar(isNarrow: false),
                                const SizedBox(height: 16),
                                Expanded(
                                  child: _buildRightContent(
                                    _liveTerminal ?? terminal,
                                    isNarrow: false,
                                    showOverviewCards: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Header ---

  Widget _buildHeader(Terminal terminal, {required bool isNarrow}) {
    if (!isNarrow) {
      return Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '终端详情 - ${terminal.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: terminal.status == 1 ? AppColors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${terminal.statusString} | ${terminal.ip}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: MouseRegion(
                cursor: widget.isStandaloneWindow && isDesktopPlatform ? SystemMouseCursors.move : MouseCursor.defer,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: widget.isStandaloneWindow && isDesktopPlatform
                      ? (event) {
                          if ((event.buttons & kPrimaryButton) == 0) return;
                          final wid = widget.windowId ?? 0;
                          WindowControl.startDragging(wid);
                        }
                      : null,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CPU使用率: ${terminal.cpuUsage.round()}%',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'GPU使用率: ${terminal.gpuUsage.round()}%',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 右侧统计与设置
            Row(
              children: [
                TextButton.icon(
                  onPressed: _refreshing ? null : () => _refreshHeartbeat(terminal.id),
                  icon: _refreshing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 14, color: Colors.black87),
                  label: Text(
                    '刷新状态',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(LucideIcons.settings, size: 18, color: Colors.grey.shade600),
                  onPressed: () {},
                ),
                if (isDesktopPlatform)
                  IconButton(
                    icon: Icon(LucideIcons.minus, size: 18, color: Colors.grey.shade600),
                    tooltip: '最小化到 Dock',
                    onPressed: () => _handleMinimize(terminal),
                  ),
                if (isDesktopPlatform && widget.isStandaloneWindow)
                  IconButton(
                    icon: Icon(
                      _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
                      size: 18,
                      color: Colors.grey.shade600,
                    ),
                    tooltip: _isMaximized ? '还原窗口' : '最大化窗口',
                    onPressed: _handleToggleMaximize,
                  ),
                IconButton(
                  icon: Icon(LucideIcons.x, size: 18, color: Colors.grey.shade600),
                  tooltip: '关闭窗口',
                  onPressed: _handleClose,
                ),
              ],
            )
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '终端详情 - ${terminal.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: terminal.status == 1 ? AppColors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${terminal.statusString} | ${terminal.ip}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refreshing ? null : () => _refreshHeartbeat(terminal.id),
                tooltip: '刷新状态',
                icon: _refreshing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade600),
                      )
                    : Icon(LucideIcons.refreshCw, size: 18, color: Colors.grey.shade700),
              ),
              IconButton(
                icon: Icon(LucideIcons.settings, size: 18, color: Colors.grey.shade600),
                onPressed: () {},
              ),
              if (isDesktopPlatform)
                IconButton(
                  icon: Icon(LucideIcons.minus, size: 18, color: Colors.grey.shade600),
                  tooltip: '最小化到 Dock',
                  onPressed: () => _handleMinimize(terminal),
                ),
              if (isDesktopPlatform && widget.isStandaloneWindow)
                IconButton(
                  icon: Icon(
                    _isMaximized ? LucideIcons.minimize2 : LucideIcons.maximize2,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  tooltip: _isMaximized ? '还原窗口' : '最大化窗口',
                  onPressed: _handleToggleMaximize,
                ),
              IconButton(
                icon: Icon(LucideIcons.x, size: 18, color: Colors.grey.shade600),
                tooltip: '关闭',
                onPressed: _handleClose,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'CPU: ${terminal.cpuUsage.round()}%  ·  GPU: ${terminal.gpuUsage.round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMinimize(Terminal terminal) async {
    if (!isDesktopPlatform) return;
    await TerminalWindowBridge.sendToMain('terminal_minimize', {
      'terminalId': widget.terminalId,
      'terminal': terminal.toJson(),
      'lastTab': _selectedTab,
      'windowId': widget.windowId,
    });
    if (widget.isStandaloneWindow && widget.windowId != null) {
      await TerminalWindowBridge.closeWindowById(widget.windowId!);
    } else if (mounted) {
      context.pop();
    }
  }

  Future<void> _handleClose() async {
    if (isDesktopPlatform) {
      await TerminalWindowBridge.sendToMain('terminal_close', {
        'terminalId': widget.terminalId,
      });
      if (widget.isStandaloneWindow && widget.windowId != null) {
        await TerminalWindowBridge.closeWindowById(widget.windowId!);
        return;
      }
    }
    if (mounted) context.pop();
  }

  Future<void> _handleToggleMaximize() async {
    if (!isDesktopPlatform || !widget.isStandaloneWindow) return;
    final wid = widget.windowId ?? 0;
    final maximized = await WindowControl.toggleMaximize(wid);
    if (mounted) setState(() => _isMaximized = maximized);
  }

  // --- Left Column Widgets ---

  Widget _buildScreenPreviewCard(Terminal terminal) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('实时画面', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('实时', style: TextStyle(fontSize: 10, color: Colors.green)),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black87,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Placeholder for screen image
                  Image.network(
                    terminal.desktopPreviewUrl(width: 800, height: 450),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(LucideIcons.monitor, color: Colors.white24, size: 48),
                    ),
                  ),
                  // Overlay gradient
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withOpacity(0.3)],
                        ),
                      ),
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

  Widget _buildSystemStatusCard(Terminal terminal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('系统状态', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 16),
          _buildStatusRow('运行时间', terminal.uptime, null),
          const SizedBox(height: 12),
          _buildStatusRow('CPU', '${terminal.cpuUsage.round()}%', terminal.cpuUsage / 100, color: Colors.blue),
          const SizedBox(height: 12),
          _buildStatusRow('内存', '${terminal.ramUsage.round()}%', terminal.ramUsage / 100, color: Colors.purple),
          const SizedBox(height: 12),
          _buildStatusRow('GPU', '${terminal.gpuUsage.round()}%', terminal.gpuUsage / 100, color: Colors.orange),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, double? progress, {Color? color}) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade100,
                    valueColor: AlwaysStoppedAnimation<Color>(color ?? Colors.blue),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 50,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRemarkCard(Terminal terminal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('备注信息', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton(
                onPressed: () {}, // Save functionality
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(40, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('保存', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 4,
            decoration: InputDecoration(
              hintText: '此电脑运行良好，暂无异常。',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  // --- Right Column Widgets ---

  Widget _buildTabBar({required bool isNarrow}) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _tabs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isSelected = _selectedTab == tab['label'];
          return InkWell(
            onTap: () => _selectTab(tab['label'] as String),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: isSelected
                    ? const Border(bottom: BorderSide(color: AppColors.iosBlue, width: 2))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    tab['icon'],
                    size: 16,
                    color: isSelected ? AppColors.iosBlue : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tab['label'],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? AppColors.iosBlue : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _selectTab(String label) {
    setState(() => _selectedTab = label);

    if (widget.isStandaloneWindow && isDesktopPlatform) {
      TerminalWindowBridge.sendToMain('terminal_tab_changed', {
        'terminalId': widget.terminalId,
        'lastTab': label,
      });
    } else {
      ref.read(terminalDockProvider.notifier).setLastTab(widget.terminalId, label);
    }
  }

  Widget _buildRightContent(
    Terminal terminal, {
    required bool isNarrow,
    required bool showOverviewCards,
  }) {
    // 根据 _selectedTab 返回不同内容，目前仅实现 远程控制
    if (_selectedTab == '远程控制') {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showOverviewCards) ...[
              _buildScreenPreviewCard(terminal),
              const SizedBox(height: 16),
              _buildSystemStatusCard(terminal),
              const SizedBox(height: 16),
              _buildRemarkCard(terminal),
              const SizedBox(height: 24),
            ],
            _buildSectionTitle('电源管理'),
            const SizedBox(height: 12),
            _buildPowerGrid(terminal, isNarrow: isNarrow),
            const SizedBox(height: 24),
            _buildSectionTitle('远程协助'),
            const SizedBox(height: 12),
            _buildRemoteAssistRow(terminal, isNarrow: isNarrow),
            const SizedBox(height: 24),
            _buildSectionTitle('最近日志'),
            const SizedBox(height: 12),
            _buildRecentLogsTable(),
          ],
        ),
      );
    } else if (_selectedTab == '文件管理') {
      return FileManagerTab(terminalId: terminal.id);
    } else if (_selectedTab == '进程管理') {
      return ProcessManagerTab(terminalId: terminal.id);
    } else if (_selectedTab == '终端命令') {
      return ConsoleManagerTab(terminalId: terminal.id);
    } else if (_selectedTab == '硬件配置') {
      return HardwareInfoTab(terminalId: terminal.id);
    } else if (_selectedTab == '网络监控') {
      return const NetworkMonitorTab();
    } else if (_selectedTab == '日志分析') {
      return LogManagerTab(terminalId: terminal.id);
    } else if (_selectedTab == '聊天窗口') {
      return ChatWindowTab(terminalId: terminal.id, terminalName: terminal.name);
    }
    return Center(child: Text('功能模块 [$_selectedTab] 开发中...'));
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600));
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHeartbeat(int terminalId, {bool silent = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final api = ref.read(terminalApiProvider);
      final hb = await api.getHeartbeat(terminalId);
      setState(() {
        _liveTerminal = hb;
      });
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已刷新状态')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刷新失败：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _buildPowerGrid(Terminal terminal, {required bool isNarrow}) {
    if (!isNarrow) {
      return Row(
        children: [
          Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _remoteAction(terminal.id, 'shutdown'))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _remoteAction(terminal.id, 'restart'))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _remoteAction(terminal.id, 'logout'))), // placeholder
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _remoteAction(terminal.id, 'lock'))), // placeholder
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _remoteAction(terminal.id, 'shutdown'))),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _remoteAction(terminal.id, 'restart'))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _remoteAction(terminal.id, 'logout'))),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _remoteAction(terminal.id, 'lock'))),
          ],
        ),
      ],
    );
  }

  Widget _buildPowerCard(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteAssistRow(Terminal terminal, {required bool isNarrow}) {
    if (!isNarrow) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildBigActionButton(
              'VNC 远程桌面',
              '极速连接，低延迟',
              LucideIcons.monitor,
              AppColors.iosBlue,
              Colors.white,
              () => _remoteAction(terminal.id, 'vnc'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildBigActionButton(
              'RustDesk',
              '备用远程方案',
              LucideIcons.settings,
              Colors.white,
              Colors.black87,
              () => _remoteAction(terminal.id, 'rustdesk'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildBigActionButton(
              '截图',
              '获取当前屏幕',
              LucideIcons.moreHorizontal,
              Colors.white,
              Colors.black87,
              () => _remoteAction(terminal.id, 'screenshot'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildBigActionButton(
          'VNC 远程桌面',
          '极速连接，低延迟',
          LucideIcons.monitor,
          AppColors.iosBlue,
          Colors.white,
          () => _remoteAction(terminal.id, 'vnc'),
        ),
        const SizedBox(height: 12),
        _buildBigActionButton(
          'RustDesk',
          '备用远程方案',
          LucideIcons.settings,
          Colors.white,
          Colors.black87,
          () => _remoteAction(terminal.id, 'rustdesk'),
        ),
        const SizedBox(height: 12),
        _buildBigActionButton(
          '截图',
          '获取当前屏幕',
          LucideIcons.moreHorizontal,
          Colors.white,
          Colors.black87,
          () => _remoteAction(terminal.id, 'screenshot'),
        ),
      ],
    );
  }

  Widget _buildBigActionButton(
      String title, String subtitle, IconData icon, Color bgColor, Color textColor, VoidCallback onTap) {
    final isPrimary = bgColor == AppColors.iosBlue;
    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isPrimary ? BorderSide.none : BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: textColor),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10, color: isPrimary ? Colors.white.withOpacity(0.8) : Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentLogsTable() {
    // 模拟数据
    final logs = [
      {'time': '14:30:22', 'level': 'INFO', 'msg': '系统启动成功'},
      {'time': '14:30:25', 'level': 'INFO', 'msg': '网络连接已建立'},
      {'time': '14:35:10', 'level': 'WARN', 'msg': 'CPU 温度略高'},
      {'time': '15:00:00', 'level': 'INFO', 'msg': '用户登录'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: logs.map((log) {
          final isWarn = log['level'] == 'WARN';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Row(
              children: [
                SizedBox(width: 80, child: Text(log['time']!, style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: 'monospace'))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isWarn ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    log['level']!,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isWarn ? Colors.orange : Colors.green),
                  ),
                ),
                const SizedBox(width: 16),
                Text(log['msg']!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _remoteAction(int terminalId, String action) async {
    try {
      final api = ref.read(terminalApiProvider);
      await api.remote(terminalId, action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('指令 [$action] 已发送')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red));
      }
    }
  }
}
