import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:webrtc_remote/webrtc_remote.dart' as webrtc;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../data/terminal_api.dart';
import '../../desktop/data/desktop_api.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/providers/terminal_dock_provider.dart';
import '../../../../shared/services/terminal_window_bridge.dart';
import '../../../../shared/services/window_control.dart';
import '../../../../shared/utils/platform_utils.dart';
import '../../../../shared/utils/top_notice.dart';

import 'widgets/file_manager_tab.dart';
import 'widgets/process_manager_tab.dart';
import 'widgets/console_manager_tab.dart';
import 'widgets/hardware_info_tab.dart';
import 'widgets/network_monitor_tab.dart';
import 'widgets/log_manager_tab.dart';
import 'widgets/chat_window_tab.dart';

final terminalDetailProvider = FutureProvider.autoDispose.family<Terminal, int>((ref, terminalId) async {
  final api = ref.read(terminalApiProvider);
  final currentNetbar = ref.watch(currentNetbarProvider);
  final domain = currentNetbar.subdomainFull;

  // 调试日志
  debugPrint('[TerminalDetailProvider] ========== 开始获取终端详情 ==========');
  debugPrint('[TerminalDetailProvider] terminalId: $terminalId');
  debugPrint('[TerminalDetailProvider] currentNetbar.id: ${currentNetbar.id}');
  debugPrint('[TerminalDetailProvider] currentNetbar.name: ${currentNetbar.name}');
  debugPrint('[TerminalDetailProvider] currentNetbar.subdomainFull: $domain');

  if (domain == null || domain.isEmpty) {
    debugPrint('[TerminalDetailProvider] ERROR: domain 为空！');
    throw Exception('网吧域名为空，无法获取终端详情');
  }

  try {
    debugPrint('[TerminalDetailProvider] 开始调用 api.getById($terminalId, domain: $domain)');
    final terminal = await api.getById(terminalId, domain: domain);
    debugPrint('[TerminalDetailProvider] 成功获取终端: ${terminal.name}');
    return terminal;
  } catch (e, stack) {
    debugPrint('[TerminalDetailProvider] ERROR: 获取终端失败: $e');
    debugPrint('[TerminalDetailProvider] Stack: $stack');
    rethrow;
  }
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

  // 实时截图相关
  final ScreenshotApi _screenshotApi = ScreenshotApi();
  Uint8List? _liveScreenshot;
  bool _screenshotLoading = false;
  bool _screenshotRunning = false; // 是否正在自动获取截图
  Timer? _countdownTimer; // 倒计时 Timer
  static const int _screenshotInterval = 5; // 截图间隔（秒）
  int _screenshotCountdown = _screenshotInterval; // 倒计时剩余秒数
  bool _screenshotCancelled = false; // 用于标记请求是否被取消

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

  /// 开始自动获取截图
  void _startScreenshotTimer() {
    if (_screenshotRunning) return;
    setState(() {
      _screenshotRunning = true;
      _screenshotCancelled = false;
    });
    // 立即获取一次（获取成功后会自动启动倒计时）
    _fetchScreenshotOnce(autoStart: true);
  }

  /// 启动倒计时（截图成功后调用）
  void _startCountdown() {
    _countdownTimer?.cancel();
    if (!_screenshotRunning || !mounted) return;

    setState(() => _screenshotCountdown = _screenshotInterval);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_screenshotRunning) {
        timer.cancel();
        return;
      }
      setState(() {
        _screenshotCountdown--;
        if (_screenshotCountdown <= 0) {
          timer.cancel();
          // 倒计时结束，再次获取截图
          _fetchScreenshotOnce(autoStart: true);
        }
      });
    });
  }

  /// 暂停自动获取截图
  void _stopScreenshotTimer() {
    // 标记取消，正在进行的请求会检查此标志
    _screenshotCancelled = true;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (mounted) {
      setState(() {
        _screenshotRunning = false;
        _screenshotLoading = false;
        _screenshotCountdown = _screenshotInterval;
      });
    }
  }

  /// 立即获取截图并重置计时器
  void _fetchScreenshotNow() {
    // 取消当前倒计时
    _countdownTimer?.cancel();
    // 立即获取
    _fetchScreenshotOnce(autoStart: _screenshotRunning);
  }

  /// 获取单次截图
  /// [autoStart] 为 true 时，成功后会自动启动倒计时
  Future<void> _fetchScreenshotOnce({bool autoStart = false}) async {
    if (!mounted) return;

    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    if (domain == null || domain.isEmpty) return;

    final terminalAsync = ref.read(terminalDetailProvider(widget.terminalId));
    final terminal = terminalAsync.valueOrNull;
    if (terminal == null) return;

    setState(() => _screenshotLoading = true);

    try {
      final result = await _screenshotApi.requestScreenshot(
        domain: domain,
        seatId: terminal.seatId,
      );

      // 检查是否已被取消
      if (!mounted || _screenshotCancelled) {
        if (mounted) setState(() => _screenshotLoading = false);
        return;
      }

      Uint8List? bytes;
      if (result.type == ScreenshotResultType.bytes && result.bytes != null) {
        bytes = result.bytes;
      } else if (result.type == ScreenshotResultType.base64 && result.base64Data != null) {
        bytes = base64Decode(result.base64Data!);
      }

      if (bytes != null) {
        setState(() {
          _liveScreenshot = bytes;
          _screenshotLoading = false;
        });
        // 获取成功后，如果在自动模式下，启动倒计时
        if (autoStart && _screenshotRunning) {
          _startCountdown();
        }
      } else {
        setState(() => _screenshotLoading = false);
        // 获取失败，如果在自动模式下，重试
        if (autoStart && _screenshotRunning && !_screenshotCancelled) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _screenshotRunning && !_screenshotCancelled) {
              _fetchScreenshotOnce(autoStart: true);
            }
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _screenshotLoading = false);
        // 获取失败，如果在自动模式下，重试
        if (autoStart && _screenshotRunning && !_screenshotCancelled) {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _screenshotRunning && !_screenshotCancelled) {
              _fetchScreenshotOnce(autoStart: true);
            }
          });
        }
      }
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
        data: (terminal) => SafeArea(
          bottom: false,
          child: Column(
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
                if (isDesktopPlatform) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(LucideIcons.minus, size: 18, color: Colors.grey.shade600),
                    tooltip: '最小化到 Dock',
                    onPressed: () => _handleMinimize(terminal),
                  ),
                ],
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
                // 浏览器模式不显示关闭按钮
                if (!kIsWeb)
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
              // 浏览器模式不显示关闭按钮
              if (!kIsWeb)
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
      // Minimize-to-dock should keep window alive to avoid refresh on restore.
      await TerminalWindowBridge.hideWindowById(widget.windowId!);
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
                Row(
                  children: [
                    // 加载指示器
                    if (_screenshotLoading)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.green.shade400,
                          ),
                        ),
                      ),
                    // 开始/暂停按钮（带倒计时）
                    Tooltip(
                      message: _screenshotRunning ? '暂停自动刷新' : '开始自动刷新',
                      child: InkWell(
                        onTap: () {
                          if (_screenshotRunning) {
                            _stopScreenshotTimer();
                          } else {
                            _startScreenshotTimer();
                          }
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: _screenshotRunning
                                ? Colors.green.withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _screenshotRunning ? LucideIcons.pause : LucideIcons.play,
                                size: 12,
                                color: _screenshotRunning ? Colors.green : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _screenshotRunning
                                    ? (_screenshotLoading ? '获取中...' : '${_screenshotCountdown}s')
                                    : '已暂停',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _screenshotRunning ? Colors.green : Colors.grey.shade600,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 立即获取按钮（放在最右边）
                    Tooltip(
                      message: '立即获取',
                      child: InkWell(
                        onTap: _screenshotLoading ? null : _fetchScreenshotNow,
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.camera,
                                size: 12,
                                color: _screenshotLoading ? Colors.grey.shade300 : Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '获取',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _screenshotLoading ? Colors.grey.shade300 : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
                  // 优先显示实时截图
                  if (_liveScreenshot != null)
                    Image.memory(
                      _liveScreenshot!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true, // 避免切换图片时闪烁
                    )
                  else
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
                  // 全屏按钮
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        onTap: () => _showFullscreenPreview(terminal),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            LucideIcons.maximize2,
                            size: 16,
                            color: Colors.white,
                          ),
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

  /// 全屏查看实时画面
  void _showFullscreenPreview(Terminal terminal) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _FullscreenPreviewDialog(
        screenshotBytes: _liveScreenshot,
        fallbackUrl: terminal.desktopPreviewUrl(width: 1920, height: 1080),
        terminalName: terminal.name,
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
            if (showOverviewCards) ...[
              const SizedBox(height: 24),
              _buildRemarkCard(terminal),
            ],
          ],
        ),
      );
    } else if (_selectedTab == '文件管理') {
      return FileManagerTab(terminalId: terminal.id, seatId: terminal.seatId);
    } else if (_selectedTab == '进程管理') {
      return ProcessManagerTab(terminalId: terminal.id, seatId: terminal.seatId);
    } else if (_selectedTab == '终端命令') {
      return ConsoleManagerTab(terminalId: terminal.id, seatId: terminal.seatId);
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
    _screenshotCancelled = true; // 标记取消
    _countdownTimer?.cancel(); // 停止倒计时
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHeartbeat(int terminalId, {bool silent = false}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull;
      final hb = await api.getHeartbeat(terminalId, domain: domain);
      setState(() {
        _liveTerminal = hb;
      });
      if (mounted && !silent) {
        showTopNotice(context, '已刷新状态', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '刷新失败：$e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Widget _buildPowerGrid(Terminal terminal, {required bool isNarrow}) {
    if (!isNarrow) {
      return Row(
        children: [
          Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _remoteAction(terminal.seatId, 'shutdown'))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _remoteAction(terminal.seatId, 'restart'))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _remoteAction(terminal.seatId, 'logout'))), // placeholder
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _remoteAction(terminal.seatId, 'lock'))), // placeholder
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _remoteAction(terminal.seatId, 'shutdown'), compact: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _remoteAction(terminal.seatId, 'restart'), compact: true)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _remoteAction(terminal.seatId, 'logout'), compact: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _remoteAction(terminal.seatId, 'lock'), compact: true)),
          ],
        ),
      ],
    );
  }

  Widget _buildPowerCard(String label, IconData icon, VoidCallback onTap, {bool compact = false}) {
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
          padding: EdgeInsets.symmetric(vertical: compact ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 8 : 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: compact ? 18 : 20, color: Colors.grey.shade700),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
              'WebRTC 远程',
              'WebRTC低延迟',
              LucideIcons.video,
              const Color(0xFF10B981),  // 绿色
              Colors.white,
              () => _openWebRTCRemote(terminal),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: _buildBigActionButton(
              'VNC 远程桌面',
              '极速连接，低延迟',
              LucideIcons.monitor,
              AppColors.iosBlue,
              Colors.white,
              () => _openVncRemote(terminal, type: 'control'),
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
              () => _remoteAction(terminal.seatId, 'rustdesk'),
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
              () => _remoteAction(terminal.seatId, 'screenshot'),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildBigActionButton(
          'WebRTC 远程',
          'WebRTC低延迟',
          LucideIcons.video,
          const Color(0xFF10B981),  // 绿色
          Colors.white,
          () => _openWebRTCRemote(terminal),
        ),
        const SizedBox(height: 12),
        _buildBigActionButton(
          'VNC 远程桌面',
          '极速连接，低延迟',
          LucideIcons.monitor,
          AppColors.iosBlue,
          Colors.white,
          () => _openVncRemote(terminal, type: 'control'),
        ),
        const SizedBox(height: 12),
        _buildBigActionButton(
          'RustDesk',
          '备用远程方案',
          LucideIcons.settings,
          Colors.white,
          Colors.black87,
          () => _remoteAction(terminal.seatId, 'rustdesk'),
        ),
        const SizedBox(height: 12),
        _buildBigActionButton(
          '截图',
          '获取当前屏幕',
          LucideIcons.moreHorizontal,
          Colors.white,
          Colors.black87,
          () => _remoteAction(terminal.seatId, 'screenshot'),
        ),
      ],
    );
  }

  /// 打开 WebRTC 远程桌面
  Future<void> _openWebRTCRemote(Terminal terminal) async {
    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    if (domain == null || domain.isEmpty) {
      showTopNotice(context, '网吧域名缺失，无法远程', level: NoticeLevel.error);
      return;
    }

    // 显示 loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 获取用户信息
      final authState = ref.read(authNotifierProvider);
      final user = authState.user;

      // 发送 task 命令
      final api = ref.read(terminalApiProvider);
      final result = await api.remote(
        terminal.seatId,
        'webrtc',
        domain: domain,
        user: {
          'name': user?.nickname ?? user?.name ?? 'unknown',
          'seat': terminal.name,
          'mchName': netbar.name ?? '',
        },
      );

      // 关闭 loading
      if (mounted) Navigator.pop(context);

      // 检查返回结果
      final mark = result['mark'];
      if (mark != null && mark.toString().isNotEmpty) {
        // 构造 WebRTC 参数并打开
        final subdomain = domain.split('.')[0];
        final peerId = '${terminal.seatId}-$subdomain';
        final wsUrl = 'wss://webrtc.03kan.com/ws?Peer=$peerId&type=Client';

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => webrtc.RemoteScreen(
              server: webrtc.ServerConfig(
                id: 'webrtc_${terminal.id}',
                name: 'WebRTC ${terminal.name}',
                host: 'webrtc.03kan.com',
                port: 443,
                wsUrl: wsUrl,
              ),
              onDisconnect: () => Navigator.pop(context),
            ),
          ),
        );
      } else {
        if (mounted) {
          showTopNotice(context, '远程连接失败：未返回有效标识', level: NoticeLevel.error);
        }
      }
    } catch (e) {
      // 关闭 loading
      if (mounted) Navigator.pop(context);
      if (mounted) {
        showTopNotice(context, '远程连接失败: $e', level: NoticeLevel.error);
      }
    }
  }

  /// 打开 VNC 远程桌面
  /// type: 'control' (控制) 或 'view' (仅查看)
  Future<void> _openVncRemote(Terminal terminal, {String type = 'control'}) async {
    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    if (domain == null || domain.isEmpty) {
      showTopNotice(context, '网吧域名缺失，无法远程', level: NoticeLevel.error);
      return;
    }

    // 获取用户信息
    final authState = ref.read(authNotifierProvider);
    final user = authState.user;

    try {
      // 发送远程连接请求
      final api = ref.read(terminalApiProvider);
      final result = await api.remote(
        terminal.seatId,
        type,
        domain: domain,
        user: {
          'name': user?.nickname ?? user?.name ?? 'unknown',
          'seat': terminal.name,
          'mchName': netbar.name ?? '',
        },
      );

      // 检查返回结果
      final mark = result['mark'];
      if (mark != null && mark.toString().isNotEmpty) {
        // 构造 VNC URL
        // 格式: {protocol}//{host}/noVnc/vnc.html?host={seatId}-{subdomain}&port=880&path=websockify&autoconnect=true&encrypt=0&password=hudd416
        final subdomain = domain.split(':')[0]; // 去掉端口
        final vncUrl = Uri.parse(
          'http://net.hudd.cc:888/noVnc/vnc.html'
          '?host=${terminal.seatId}-$subdomain'
          '&port=880'
          '&path=websockify'
          '&autoconnect=true'
          '&encrypt=0'
          '&password=hudd416'
          '${type == 'view' ? '&view_only=true' : ''}',
        );

        if (mounted) {
          showTopNotice(context, '正在打开 VNC 远程...', level: NoticeLevel.success);
        }

        // 打开浏览器
        if (await canLaunchUrl(vncUrl)) {
          await launchUrl(vncUrl, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            showTopNotice(context, '无法打开浏览器', level: NoticeLevel.error);
          }
        }
      } else {
        if (mounted) {
          showTopNotice(context, '远程连接失败：未返回有效标识', level: NoticeLevel.error);
        }
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '远程连接失败: $e', level: NoticeLevel.error);
      }
    }
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

  Future<void> _remoteAction(String seatId, String action) async {
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      if (action == 'wakeup') {
        await api.wakeOnLan(seatId, domain: domain);
      } else {
        await api.remote(seatId, action, domain: domain);
      }
      if (mounted) {
        showTopNotice(context, '指令 [$action] 已发送', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }
}

/// 全屏预览对话框
class _FullscreenPreviewDialog extends StatelessWidget {
  final Uint8List? screenshotBytes;
  final String fallbackUrl;
  final String terminalName;

  const _FullscreenPreviewDialog({
    required this.screenshotBytes,
    required this.fallbackUrl,
    required this.terminalName,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          // 图片区域（可缩放）
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: screenshotBytes != null
                  ? Image.memory(
                      screenshotBytes!,
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      fallbackUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Icon(LucideIcons.monitor, color: Colors.white24, size: 64),
                        ),
                      ),
                    ),
            ),
          ),
          // 顶部栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '实时画面 - $terminalName',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                    tooltip: '关闭',
                  ),
                ],
              ),
            ),
          ),
          // 底部提示
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '双指缩放或滚轮缩放查看细节',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
