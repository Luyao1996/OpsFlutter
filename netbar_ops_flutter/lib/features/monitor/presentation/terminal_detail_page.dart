import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb, immutable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:webrtc_remote/webrtc_remote.dart' as webrtc;
import 'package:url_launcher/url_launcher.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:ffi' as ffi hide Size;
import 'package:win32/win32.dart' as win32;
import '../../../../core/logging/webrtc_crash_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../data/terminal_api.dart';
import '../../desktop/data/desktop_api.dart';
import '../../logs/data/operation_log_api.dart';
import 'monitor_page.dart' show terminalsProvider;
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/providers/terminal_dock_provider.dart';
import '../../../../shared/services/terminal_window_bridge.dart';
import '../../../../shared/services/window_control.dart';
import '../../../../shared/utils/platform_utils.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../netbar/data/netbar_api.dart' as netbar_api;

import 'widgets/file_manager_tab.dart';
import 'widgets/process_manager_tab.dart';
import 'widgets/console_manager_tab.dart';
import 'widgets/hardware_info_tab.dart';
import 'widgets/network_monitor_tab.dart';
import 'widgets/log_manager_tab.dart';


/// 终端详情 provider 的复合 key：(netbarId, terminalId)。
/// 跨网吧时即便 terminalId 相同也视为不同 key，彻底避免缓存串台。
@immutable
class TerminalDetailKey {
  final int? netbarId;
  final int terminalId;
  const TerminalDetailKey(this.netbarId, this.terminalId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TerminalDetailKey &&
          other.netbarId == netbarId &&
          other.terminalId == terminalId;

  @override
  int get hashCode => Object.hash(netbarId, terminalId);

  @override
  String toString() => 'TerminalDetailKey(netbar=$netbarId, terminal=$terminalId)';
}

final terminalDetailProvider =
    FutureProvider.autoDispose.family<Terminal, TerminalDetailKey>((ref, key) async {
  final currentNetbar = ref.watch(currentNetbarProvider);
  // family key 必须与当前 netbar 对齐，防止切网吧后用旧 key 读到新网吧数据
  if (currentNetbar.id != key.netbarId) {
    throw Exception('网吧已切换，终端详情 key 失效 (key=$key current=${currentNetbar.id})');
  }
  final netbarId = key.netbarId;
  if (netbarId == null) {
    throw Exception('netbarId 为空，无法获取终端详情 (key=$key)');
  }

  // 优先从 terminalsProvider 缓存中查找，避免重复请求 /terminals
  final cachedTerminals = ref.read(terminalsProvider(netbarId)).valueOrNull;
  if (cachedTerminals != null && cachedTerminals.isNotEmpty) {
    final found = cachedTerminals.where((t) => t.id == key.terminalId);
    if (found.isNotEmpty) {
      debugPrint('[TerminalDetailProvider] 从缓存获取终端: ${found.first.name}');
      return found.first;
    }
  }

  // 缓存中没有，才发起请求
  debugPrint('[TerminalDetailProvider] 缓存未命中, 请求 /terminals (key=$key)');
  final api = ref.read(terminalApiProvider);
  final terminal = await api.getById(key.terminalId, merchantId: netbarId);
  return terminal;
});

class TerminalDetailPage extends ConsumerStatefulWidget {
  final int terminalId;
  final bool isStandaloneWindow;
  final int? windowId;
  final String? initialTab;
  final Uint8List? initialScreenshot;

  const TerminalDetailPage({
    super.key,
    required this.terminalId,
    this.isStandaloneWindow = false,
    this.windowId,
    this.initialTab,
    this.initialScreenshot,
  });

  @override
  ConsumerState<TerminalDetailPage> createState() => _TerminalDetailPageState();
}

class _TerminalDetailPageState extends ConsumerState<TerminalDetailPage> {
  static const _focusChannel = MethodChannel('com.netbar/window_focus');
  // 当前选中的功能 Tab
  String _selectedTab = '远程控制';
  Terminal? _liveTerminal;
  /// 打开本页时"所属网吧"的 id，锁定后作为不变量基准。
  /// - 独立子窗口：snapshot 自子 container，天然锁定
  /// - 主窗口 in-place：initState 一次读取后不再变化；
  ///   一旦主窗口切网吧，所有远程操作入口通过 _ensureSameNetbar 立即拦截
  late final int? _ownerNetbarId;
  /// 复合 key 助手：避免到处重复 new
  TerminalDetailKey get _detailKey =>
      TerminalDetailKey(_ownerNetbarId, widget.terminalId);

  /// 远程操作前的不变量校验：当前 netbar 必须与详情页打开时一致。
  /// - debug：assert 直接崩溃，暴露未来引入"详情页上可切网吧"UI 的破坏
  /// - release：返回 false，上层应立即中止操作并 toast 提示
  bool _ensureSameNetbar(String op) {
    final currentId = ref.read(currentNetbarProvider).id;
    if (currentId == _ownerNetbarId) return true;
    assert(false,
        '[TerminalDetail] netbarId 不变量被破坏 op=$op owner=$_ownerNetbarId current=$currentId terminalId=${widget.terminalId}');
    debugPrint(
        '[TerminalDetail] abort $op: owner=$_ownerNetbarId current=$currentId');
    if (mounted) {
      showTopNotice(context, '网吧已切换，请重新打开终端', level: NoticeLevel.warning);
    }
    return false;
  }
  bool _refreshing = false;
  bool _isMaximized = false;
  bool _isWebRTCActive = false;
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

  // 网吧信息（通过 API 获取）
  String _netbarName = '-';
  String _groupName = '-';

  final List<Map<String, dynamic>> _tabs = [
    {'icon': LucideIcons.gamepad2, 'label': '远程控制'},
    {'icon': LucideIcons.fileText, 'label': '文件管理'},
    {'icon': LucideIcons.activity, 'label': '进程管理'},
    {'icon': LucideIcons.terminal, 'label': '终端命令'},
    {'icon': LucideIcons.cpu, 'label': '硬件配置'},
    {'icon': LucideIcons.network, 'label': '网络监控'},
    {'icon': LucideIcons.fileSpreadsheet, 'label': '日志分析'},
  ];

  @override
  void initState() {
    super.initState();
    // 锁定"打开时所属网吧"，后续所有远程操作都以此为不变量基准
    _ownerNetbarId = ref.read(currentNetbarProvider).id;
    if (widget.initialScreenshot != null) {
      _liveScreenshot = widget.initialScreenshot;
    }
    if (widget.initialTab != null && widget.initialTab!.isNotEmpty) {
      _selectedTab = widget.initialTab!;
    }
    // Immediately fetch realtime data, then repeat every 15s
    _refreshHeartbeat(widget.terminalId, silent: true);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshHeartbeat(widget.terminalId, silent: true);
    });

    if (isDesktopPlatform && widget.isStandaloneWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          final wid = widget.windowId ?? 0;
          final maximized = await WindowControl.isMaximized(wid);
          if (mounted) setState(() => _isMaximized = maximized);
        }
      });
      _focusChannel.setMethodCallHandler((call) async {
        if (call.method == 'onBlur') {
          _onWindowBlur();
        } else if (call.method == 'onFocus') {
          _onWindowFocus();
        } else if (call.method == '_prepareForClose') {
          // Pop WebRTC route so RemoteScreen.dispose() runs while the engine is
          // still alive. This prevents a deadlock during window close:
          // DestroyWindow blocks the main thread -> Dart dispose() needs main
          // thread for platform channel calls -> deadlock.
          if (_isWebRTCActive && mounted) {
            Navigator.popUntil(context, (r) => r.isFirst);
            await WidgetsBinding.instance.endOfFrame;
          }
        }
      });
    }

    _fetchNetbarInfo();
  }

  /// 通过 subdomain 获取当前终端所属网吧的名称和分组
  Future<void> _fetchNetbarInfo() async {
    final domain = ref.read(currentNetbarProvider).subdomainFull;
    if (domain == null || domain.isEmpty) return;
    // subdomainFull 格式为 "xxx.frps.wwls.net"，subdomain 是第一段
    final subdomain = domain.split('.').first;
    try {
      final netbar = await netbar_api.NetbarApi().getBySubdomain(subdomain);
      if (netbar != null && mounted) {
        setState(() {
          _netbarName = netbar.name.isNotEmpty ? netbar.name : '-';
          _groupName = netbar.group.isNotEmpty ? netbar.group : '-';
        });
        // 更新窗口标题
        if (isDesktopPlatform) {
          final terminalName = _liveTerminal?.name ??
              ref.read(terminalDetailProvider(_detailKey)).valueOrNull?.name ?? '';
          final title = '终端详情 - $_netbarName - $_groupName - $terminalName';
          if (widget.isStandaloneWindow && widget.windowId != null) {
            WindowController.fromWindowId(widget.windowId!).setTitle(title);
          } else {
            windowManager.setTitle(title);
          }
        }
      }
    } catch (_) {}
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
    if (!_ensureSameNetbar('fetchScreenshot')) return;

    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    if (domain == null || domain.isEmpty) return;

    final terminalAsync = ref.read(terminalDetailProvider(_detailKey));
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
    final terminalAsync = ref.watch(terminalDetailProvider(_detailKey));
    final isNarrow = context.isNarrow || context.isPhone;

    final bool showWindowBorder = isDesktopPlatform && widget.isStandaloneWindow && !_isMaximized;

    return Container(
      decoration: showWindowBorder
          ? BoxDecoration(
              border: Border.all(color: const Color(0xFF6B7280), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            )
          : null,
      clipBehavior: showWindowBorder ? Clip.antiAlias : Clip.none,
      child: Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF3F4F6),
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
                                    _buildScreenPreviewCard(_liveTerminal ?? terminal),
                                    const SizedBox(height: 16),
                                    _buildSystemStatusCard(_liveTerminal ?? terminal),
                                    const SizedBox(height: 16),
                                    _buildRemarkCard(_liveTerminal ?? terminal),
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
      ),
      ],
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
                  '终端详情 - $_netbarName - $_groupName - ${terminal.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
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
                      '终端详情 - $_netbarName - $_groupName - ${terminal.name}',
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
    if (!_ensureSameNetbar('handleMinimize')) return;
    final netbar = ref.read(currentNetbarProvider);
    await TerminalWindowBridge.sendToMain('terminal_minimize', {
      'terminalId': widget.terminalId,
      'netbarId': netbar.id ?? 0,
      'terminal': terminal.toJson(),
      'lastTab': _selectedTab,
      'windowId': widget.windowId,
      if (_liveScreenshot != null) 'screenshot': base64Encode(_liveScreenshot!),
      'netbarName': _netbarName,
      'groupName': _groupName,
    });
    if (widget.isStandaloneWindow && widget.windowId != null) {
      // Minimize-to-dock should keep window alive to avoid refresh on restore.
      await TerminalWindowBridge.hideWindowById(widget.windowId!);
    } else if (mounted) {
      context.pop();
    }
  }

  void _onWindowBlur() {
    // 不再自动最小化，允许多窗口并存
  }

  void _onWindowFocus() {
    // 窗口恢复焦点时立即触发重绘，避免最小化恢复后黑屏
    if (_isWebRTCActive && isDesktopPlatform) {
      final hwnd = win32.GetForegroundWindow();
      if (hwnd != 0) {
        win32.InvalidateRect(hwnd, ffi.nullptr, 1);
        WidgetsBinding.instance.scheduleFrame();
      }
    }
  }

  Future<void> _handleClose() async {
    if (isDesktopPlatform) {
      // 关闭流程不拦截（用户就是要退出），但要记录不匹配供排查
      if (_ownerNetbarId != ref.read(currentNetbarProvider).id) {
        debugPrint('[TerminalDetail] handleClose: netbar mismatch owner=$_ownerNetbarId current=${ref.read(currentNetbarProvider).id}');
      }
      final netbar = ref.read(currentNetbarProvider);
      await TerminalWindowBridge.sendToMain('terminal_close', {
        'terminalId': widget.terminalId,
        'netbarId': netbar.id ?? 0,
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
          const SizedBox(height: 12),
          _buildStatusRow('磁盘', '${terminal.diskUsage.round()}%', terminal.diskUsage / 100, color: Colors.teal),
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

    final netbarId = ref.read(currentNetbarProvider).id ?? 0;
    final uniqueKey = '${netbarId}_${widget.terminalId}';

    if (widget.isStandaloneWindow && isDesktopPlatform) {
      TerminalWindowBridge.sendToMain('terminal_tab_changed', {
        'terminalId': widget.terminalId,
        'netbarId': netbarId,
        'lastTab': label,
      });
    } else {
      ref.read(terminalDockProvider.notifier).setLastTab(uniqueKey, label);
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
            _buildSectionTitle('远程协助'),
            const SizedBox(height: 12),
            _buildRemoteAssistRow(terminal, isNarrow: isNarrow),
            const SizedBox(height: 24),
            _buildSectionTitle('电源管理'),
            const SizedBox(height: 12),
            _buildPowerGrid(terminal, isNarrow: isNarrow),
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
      return HardwareInfoTab(terminalId: terminal.id, seatId: terminal.seatId);
    } else if (_selectedTab == '网络监控') {
      return NetworkMonitorTab(seatId: terminal.seatId);
    } else if (_selectedTab == '日志分析') {
      return LogManagerTab(terminalId: terminal.id);
    }
    return Center(child: Text('功能模块 [$_selectedTab] 开发中...'));
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600));
  }

  @override
  void dispose() {
    if (isDesktopPlatform && widget.isStandaloneWindow) {
      _focusChannel.setMethodCallHandler(null);
    }
    _screenshotCancelled = true; // 标记取消
    _countdownTimer?.cancel(); // 停止倒计时
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshHeartbeat(int terminalId, {bool silent = false}) async {
    if (_refreshing) return;
    if (!_ensureSameNetbar('refreshHeartbeat')) return;
    final ownerNetbarId = _ownerNetbarId;
    if (ownerNetbarId == null) return;
    setState(() => _refreshing = true);
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';

      // Step 1: fetch /terminals via central HTTP and update UI immediately
      final hb = await api.getHeartbeat(terminalId, merchantId: ownerNetbarId);
      if (mounted) setState(() => _liveTerminal = hb);

      // Step 2: fetch realtime hwinfo via frp HTTP in background, update UI when ready
      final seatId = hb.seatId.isNotEmpty ? hb.seatId : (_liveTerminal?.seatId ?? '');
      if (seatId.isNotEmpty && domain.isNotEmpty && hb.status > 0) {
        api.getHardwareRealtime(seatId, domain: domain).then((rt) {
          if (!mounted) return;
          double cpu = hb.cpuUsage, gpu = hb.gpuUsage, ram = hb.ramUsage;
          double disk = hb.diskUsage;
          try {
            // CPU: load_total (%)
            final cpuList = rt['cpu'] as List?;
            if (cpuList != null && cpuList.isNotEmpty) {
              final c = cpuList[0];
              if (c is Map<String, dynamic>) cpu = (c['load_total'] ?? 0).toDouble();
            }
            // GPU: load_gpu (%)
            final gpuList = rt['gpu'] as List?;
            if (gpuList != null && gpuList.isNotEmpty) {
              final g = gpuList[0];
              if (g is Map<String, dynamic>) gpu = (g['load_gpu'] ?? 0).toDouble();
            }
            // Memory: average load_total across modules
            final memData = rt['memory'];
            if (memData is List && memData.isNotEmpty) {
              double totalLoad = 0; int count = 0;
              for (final m in memData) {
                if (m is Map<String, dynamic>) { totalLoad += (m['load_total'] ?? 0).toDouble(); count++; }
              }
              if (count > 0) ram = totalLoad / count;
            } else if (memData is Map<String, dynamic>) {
              ram = (memData['load_total'] ?? 0).toDouble();
            }
            // Storage: used_space / (used_space + free_space)
            final storageList = rt['storage'] as List?;
            if (storageList != null && storageList.isNotEmpty) {
              double totalUsed = 0, totalFree = 0;
              for (final s in storageList) {
                if (s is Map<String, dynamic>) {
                  totalUsed += (s['used_space'] as num?)?.toDouble() ?? 0;
                  totalFree += (s['free_space'] as num?)?.toDouble() ?? 0;
                }
              }
              final totalSize = totalUsed + totalFree;
              if (totalSize > 0) disk = (totalUsed / totalSize * 100);
            }
          } catch (e) {
            debugPrint('[TerminalDetail] hwinfo parse error: $e');
          }
          debugPrint('[TerminalDetail] realtime: cpu=$cpu, gpu=$gpu, ram=$ram, disk=$disk');
          if (mounted) {
            setState(() {
              _liveTerminal = Terminal(
                id: hb.id, seatId: hb.seatId, name: hb.name, code: hb.code,
                netbarId: hb.netbarId, areaId: hb.areaId, ip: hb.ip, mac: hb.mac,
                os: hb.os, type: hb.type, status: hb.status,
                cpuUsage: cpu, ramUsage: ram, gpuUsage: gpu, diskUsage: disk,
                uptime: hb.uptime, screenshotUrl: hb.screenshotUrl,
                lastOnline: hb.lastOnline, lastHeartbeat: hb.lastHeartbeat,
                createdAt: hb.createdAt, updatedAt: hb.updatedAt, remote: hb.remote,
              );
            });
          }
        }).catchError((e) {
          debugPrint('[TerminalDetail] hwinfo realtime failed (non-critical): $e');
        });
      }
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
          Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _confirmAction('关机', () => _remoteAction(terminal.seatId, 'shutdown')))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _confirmAction('重启', () => _remoteAction(terminal.seatId, 'reboot')))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _confirmAction('注销', () => _remoteAction(terminal.seatId, 'logoff')))),
          const SizedBox(width: 12),
          Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _confirmAction('锁定', () => _remoteAction(terminal.seatId, 'lock')))),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildPowerCard('关机', LucideIcons.power, () => _confirmAction('关机', () => _remoteAction(terminal.seatId, 'shutdown')), compact: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('重启', LucideIcons.refreshCw, () => _confirmAction('重启', () => _remoteAction(terminal.seatId, 'reboot')), compact: true)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildPowerCard('注销', LucideIcons.logOut, () => _confirmAction('注销', () => _remoteAction(terminal.seatId, 'logoff')), compact: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildPowerCard('锁定', LucideIcons.lock, () => _confirmAction('锁定', () => _remoteAction(terminal.seatId, 'lock')), compact: true)),
          ],
        ),
      ],
    );
  }

  void _confirmAction(String actionName, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => _ConfirmActionDialog(
        actionName: actionName,
        onConfirm: onConfirm,
      ),
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
              '笨鸟远程',
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
              () => _handleVncButtonTap(terminal),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildBigActionButton(
          '笨鸟远程',
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
          () => _handleVncButtonTap(terminal),
        ),
      ],
    );
  }

  /// 点击 VNC 按钮：先弹出"是否以只读方式打开"的选择框，再根据结果打开
  Future<void> _handleVncButtonTap(Terminal terminal) async {
    final readOnly = await _showVncReadOnlyDialog();
    if (readOnly == null) return; // 用户取消
    await _openVncRemote(terminal, type: readOnly ? 'view' : 'control');
  }

  /// 询问用户是否以只读方式打开 VNC。
  /// 返回：true=只读，false=控制模式，null=取消
  Future<bool?> _showVncReadOnlyDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('VNC 远程桌面'),
          content: const Text('是否以"只读"模式打开？\n只读模式下仅能观看画面，无法操作鼠标键盘。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('否（控制模式）'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.iosBlue),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('是（只读）'),
            ),
          ],
        );
      },
    );
  }

  /// 打开 WebRTC 远程桌面
  Future<void> _openWebRTCRemote(Terminal terminal) async {
    if (!_ensureSameNetbar('openWebRTCRemote')) return;
    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    final ctxId =
        'netbar_${netbar.id ?? 'null'}_seat_${terminal.seatId.isEmpty ? 'empty' : terminal.seatId}';
    if (domain == null || domain.isEmpty) {
      WebRtcCrashLogger.I.log(
        'WARN',
        'webrtc',
        'open_remote',
        ctxId,
        'abort domainMissing netbarId=${netbar.id} netbarName=${netbar.name} subdomainFull=$domain',
      );
      showTopNotice(context, '网吧域名缺失，无法远程', level: NoticeLevel.error);
      return;
    }

    final authState = ref.read(authNotifierProvider);
    final user = authState.user;
    WebRtcCrashLogger.I.log(
      'INFO',
      'webrtc',
      'open_remote',
      ctxId,
      "entry netbarId=${netbar.id} netbarName='${netbar.name}' groupName='${netbar.groupName}' "
          "terminalId=${terminal.id} seatId='${terminal.seatId}' seatIdLen=${terminal.seatId.length} "
          "terminalName='${terminal.name}' domain='$domain' userNickname='${user?.nickname}' userName='${user?.name}'",
    );

    // 显示 loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // 发送 task 命令（走 WebSocket 任务通道）
      final api = ref.read(terminalApiProvider);
      final result = await api.remote(
        terminal.seatId,
        'webrtc',
        merchantId: netbar.id!,
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
      WebRtcCrashLogger.I.log(
        'INFO',
        'webrtc',
        'open_remote',
        ctxId,
        'api_return mark=${mark} markType=${mark?.runtimeType} '
            'resultKeys=${result.keys.toList()} '
            'resultJson=${WebRtcCrashLogger.I.jsonOrString(result)}',
      );
      if (mark != null && mark.toString().isNotEmpty) {
        // 上报操作日志（fire-and-forget）
        ref.read(operationLogApiProvider).add(
              event: 'remote.connect',
              description: '远程连接 ${terminal.name}',
            );

        // ⚠️ WS 链路升级后 remote() 调用 ~33ms 就返回，但 Host 端启动 webrtc-remote
        // 服务需要 100~500ms。若立即拉信令 WS 会被服务端以 host_offline 拒绝
        // （webrtc_remote 包不内置重试，单次失败就 INITIAL CONNECTION ERROR）。
        // 此处固定 delay 1500ms 给 Host 端启动留 3 倍冗余。
        // 旧 frp HTTP 链路天然有几百 ms 延迟，掩盖了这个时序竞态。
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;

        // 构造 WebRTC 参数并打开
        final subdomain = domain.split('.')[0];
        final peerId = '${terminal.seatId}-$subdomain';
        final wsUrl = 'wss://webrtc.03kan.com:443/ws?Peer=$peerId&type=Client';
        WebRtcCrashLogger.I.log(
          'INFO',
          'webrtc',
          'open_remote',
          ctxId,
          "built_url subdomain='$subdomain' subdomainLen=${subdomain.length} "
              "peerId='$peerId' peerIdLen=${peerId.length} wsUrl='$wsUrl'",
        );

        _isWebRTCActive = true;
        // 进入 WebRTC 时暂停截图和心跳（远程桌面已有实时画面，无需后台刷新）
        _stopScreenshotTimer();
        _heartbeatTimer?.cancel();
        WebRtcCrashLogger.I.log(
          'INFO',
          'webrtc',
          'open_remote',
          ctxId,
          "pushing_screen serverId='webrtc_${terminal.id}' serverName='WebRTC ${terminal.name}' "
              "host='webrtc.03kan.com' port=443 windowId=${widget.windowId} isStandaloneWindow=${widget.isStandaloneWindow}",
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => Theme(
              data: Theme.of(context).copyWith(
                textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Segoe UI'),
              ),
              child: _WebRTCWindowWrapper(
                title: '$_netbarName - $_groupName - ${terminal.name}',
                windowId: widget.windowId ?? 0,
                isStandaloneWindow: widget.isStandaloneWindow,
                onMinimize: widget.isStandaloneWindow
                    ? () => _handleMinimize(terminal)
                    : null,
                childBuilder: (toggleFullscreen, isFullscreen) => webrtc.RemoteScreen(
                  server: webrtc.ServerConfig(
                    id: 'webrtc_${terminal.id}',
                    name: 'WebRTC ${terminal.name}',
                    host: 'webrtc.03kan.com',
                    port: 443,
                    wsUrl: wsUrl,
                  ),
                  onDisconnect: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ),
        );
        _isWebRTCActive = false;
        WebRtcCrashLogger.I.log(
          'INFO',
          'webrtc',
          'open_remote',
          ctxId,
          'exited_screen resume_heartbeat',
        );
        // 退出 WebRTC，恢复心跳定时器
        _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
          _refreshHeartbeat(widget.terminalId, silent: true);
        });
      } else {
        WebRtcCrashLogger.I.log(
          'WARN',
          'webrtc',
          'open_remote',
          ctxId,
          'abort invalid_mark mark=$mark',
        );
        if (mounted) {
          showTopNotice(context, '远程连接失败：未返回有效标识', level: NoticeLevel.error);
        }
      }
    } catch (e, s) {
      WebRtcCrashLogger.I.log(
        'ERROR',
        'webrtc',
        'open_remote',
        ctxId,
        'exception e=$e stack=${s.toString().split('\n').take(10).join(' | ')}',
      );
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
    if (!_ensureSameNetbar('openVncRemote')) return;
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
      // 发送远程连接请求（走 WebSocket 任务通道）
      final api = ref.read(terminalApiProvider);
      final result = await api.remote(
        terminal.seatId,
        type,
        merchantId: netbar.id!,
        user: {
          'name': user?.nickname ?? user?.name ?? 'unknown',
          'seat': terminal.name,
          'mchName': netbar.name ?? '',
        },
      );

      // 检查返回结果
      final mark = result['mark'];
      if (mark != null && mark.toString().isNotEmpty) {
        // 上报操作日志（fire-and-forget）
        ref.read(operationLogApiProvider).add(
              event: 'remote.connect',
              description: '远程连接 ${terminal.name}',
            );
        // 构造 VNC URL
        final subdomain = domain.split(':')[0]; // 去掉端口
        final vncUrl = Uri.https('admin.wwls.net', '/noVnc/vnc.html', {
          '网吧分组': netbar.groupName ?? '',
          '网吧名称': netbar.name ?? '',
          'host': '${terminal.seatId}-$subdomain',
          'path': 'websockify',
          'autoconnect': 'true',
          'encrypt': '1',
          'password': 'hudd416',
          if (type == 'view') 'view_only': 'true',
        },
        );

        debugPrint('[VNC] 打开URL: ${vncUrl.toString()}');

        if (mounted) {
          showTopNotice(context, '正在打开 VNC 远程...', level: NoticeLevel.success);
        }

        // 打开浏览器
        bool launched = false;
        try {
          launched = await launchUrl(vncUrl, mode: LaunchMode.externalApplication);
          debugPrint('[VNC] launchUrl结果: $launched');
        } catch (e) {
          debugPrint('[VNC] launchUrl异常: $e');
        }
        if (!launched && Platform.isWindows) {
          debugPrint('[VNC] 使用powershell兜底打开');
          await Process.run('powershell', ['-Command', 'Start-Process', "'${vncUrl.toString()}'"]);
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
    if (!_ensureSameNetbar('remoteAction:$action')) return;
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      if (action == 'wakeup') {
        await api.wakeOnLan(seatId, domain: domain);
        // 唤醒成功上报操作日志（fire-and-forget）
        final terminalName = _liveTerminal?.name ?? seatId;
        ref.read(operationLogApiProvider).add(
              event: 'remote.awaken',
              description: '唤醒: $terminalName',
            );
      } else {
        await api.controlPc(seatId, action, domain: domain);
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

class _ConfirmActionDialog extends StatefulWidget {
  final String actionName;
  final VoidCallback onConfirm;
  const _ConfirmActionDialog({
    required this.actionName,
    required this.onConfirm,
  });

  @override
  State<_ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<_ConfirmActionDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matched = _controller.text.trim() == widget.actionName;
    return AlertDialog(
      title: Text(widget.actionName),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('此操作不可撤销，请输入「${widget.actionName}」以确认对该终端执行操作。'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: '请输入 ${widget.actionName}',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: matched
              ? () {
                  Navigator.pop(context);
                  widget.onConfirm();
                }
              : null,
          child: const Text('继续'),
        ),
      ],
    );
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

/// WebRTC remote wrapper: title bar with fullscreen sync via WindowListener
class _WebRTCWindowWrapper extends StatefulWidget {
  final String title;
  final int windowId;
  final bool isStandaloneWindow;
  final VoidCallback? onMinimize;

  /// Builder 模式：向子 widget 注入全屏切换回调和全屏状态
  final Widget Function(VoidCallback toggleFullscreen, bool isFullscreen) childBuilder;

  const _WebRTCWindowWrapper({
    required this.title,
    required this.windowId,
    required this.isStandaloneWindow,
    required this.childBuilder,
    this.onMinimize,
  });

  @override
  State<_WebRTCWindowWrapper> createState() => _WebRTCWindowWrapperState();
}

class _WebRTCWindowWrapperState extends State<_WebRTCWindowWrapper> {
  bool _isMaximized = false;
  bool _isFullscreen = false;
  Timer? _fullscreenPollTimer;


  int _hwnd = 0;

  // 进入 Wrapper 前的原始窗口样式（用于退出时恢复原生标题栏）
  int _originalStyle = 0;
  bool _didHideNativeChrome = false;

  // 最小化状态追踪（用于恢复时强制重绘）
  bool _wasMinimized = false;

  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform) {
      _hwnd = win32.GetForegroundWindow();
      _hideNativeChrome();
      _initWindowManager();
      if (widget.isStandaloneWindow) _checkMaximized();
      _fullscreenPollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _pollFullscreenState(),
      );
    }
  }

  /// 隐藏 Windows 原生标题栏（进入远程桌面时）
  void _hideNativeChrome() {
    if (_hwnd == 0) return;
    _originalStyle = win32.GetWindowLongPtr(
        _hwnd, win32.WINDOW_LONG_PTR_INDEX.GWL_STYLE);
    if ((_originalStyle & win32.WINDOW_STYLE.WS_CAPTION) != 0) {
      final newStyle = _originalStyle &
          ~(win32.WINDOW_STYLE.WS_CAPTION |
            win32.WINDOW_STYLE.WS_SYSMENU |
            win32.WINDOW_STYLE.WS_MINIMIZEBOX |
            win32.WINDOW_STYLE.WS_MAXIMIZEBOX);
      win32.SetWindowLongPtr(
          _hwnd, win32.WINDOW_LONG_PTR_INDEX.GWL_STYLE, newStyle);
      win32.SetWindowPos(_hwnd, 0, 0, 0, 0, 0,
          win32.SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
          win32.SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
          win32.SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
          win32.SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
          win32.SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED);
      _didHideNativeChrome = true;
    }
  }

  /// 恢复 Windows 原生标题栏（退出远程桌面时）
  void _restoreNativeChrome() {
    if (!_didHideNativeChrome || _hwnd == 0 || _originalStyle == 0) return;
    win32.SetWindowLongPtr(
        _hwnd, win32.WINDOW_LONG_PTR_INDEX.GWL_STYLE, _originalStyle);
    win32.SetWindowPos(_hwnd, 0, 0, 0, 0, 0,
        win32.SET_WINDOW_POS_FLAGS.SWP_NOMOVE |
        win32.SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
        win32.SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
        win32.SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE |
        win32.SET_WINDOW_POS_FLAGS.SWP_FRAMECHANGED);
    _didHideNativeChrome = false;
  }

  Future<void> _initWindowManager() async {
    try {
      await windowManager.ensureInitialized();
    } catch (e) {
      print('[WebRTCWrapper] windowManager.ensureInitialized failed: $e');
    }
  }

  @override
  void dispose() {
    _fullscreenPollTimer?.cancel();
    if (isDesktopPlatform) _restoreNativeChrome();
    super.dispose();
  }

  void _pollFullscreenState() {
    if (_hwnd == 0 || !mounted) return;

    // 检测最小化恢复 → 强制重绘
    final isMinimized = win32.IsIconic(_hwnd) != 0;
    if (_wasMinimized && !isMinimized) {
      _forceRepaint();
    }
    _wasMinimized = isMinimized;

    // 同步全屏状态：同时支持 IsZoomed（SW_MAXIMIZE）和 style 检测（windowManager.setFullScreen）
    final isZoomed = win32.IsZoomed(_hwnd) != 0;
    final style = win32.GetWindowLongPtr(
        _hwnd, win32.WINDOW_LONG_PTR_INDEX.GWL_STYLE);
    final isStyleFullscreen =
        (style & win32.WINDOW_STYLE.WS_OVERLAPPEDWINDOW) == 0;
    final isNowFullscreen = isZoomed || isStyleFullscreen;
    if (isNowFullscreen != _isFullscreen) {
      setState(() => _isFullscreen = isNowFullscreen);
    }
  }

  /// 强制窗口重绘 —— 解决全屏/最小化恢复后黑屏问题
  /// 延迟确保 ANGLE swap chain 重建完成后再触发
  void _forceRepaint() {
    win32.InvalidateRect(_hwnd, ffi.nullptr, 1);
    WidgetsBinding.instance.scheduleFrame();
    for (final ms in [50, 150, 500]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _hwnd == 0) return;
        win32.InvalidateRect(_hwnd, ffi.nullptr, 1);
        WidgetsBinding.instance.scheduleFrame();
        setState(() {});
      });
    }
  }

  Future<void> _checkMaximized() async {
    final maximized = await WindowControl.isMaximized(widget.windowId);
    if (mounted) setState(() => _isMaximized = maximized);
  }

  Future<void> _handleToggleMaximize() async {
    if (!isDesktopPlatform || !widget.isStandaloneWindow) return;
    final maximized = await WindowControl.toggleMaximize(widget.windowId);
    if (mounted) setState(() => _isMaximized = maximized);
  }

  void _handleFullscreen() {
    if (!isDesktopPlatform || _hwnd == 0) return;
    // 用 IsZoomed 判断当前实际窗口状态，不依赖 _isFullscreen
    final isZoomed = win32.IsZoomed(_hwnd) != 0;
    if (isZoomed) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

  void _enterFullscreen() {
    // 只做 Win32 原生最大化，不设 _isFullscreen，不调 setState
    // 标题栏显隐由 _pollFullscreenState 延迟驱动（此时 ANGLE 已稳定）
    win32.ShowWindow(_hwnd, win32.SHOW_WINDOW_CMD.SW_MAXIMIZE);
    _forceRepaint();
  }

  void _exitFullscreen() {
    win32.ShowWindow(_hwnd, win32.SHOW_WINDOW_CMD.SW_RESTORE);
    _forceRepaint();
  }

  void _handleClose() {
    if (_hwnd != 0 && win32.IsZoomed(_hwnd) != 0) {
      win32.ShowWindow(_hwnd, win32.SHOW_WINDOW_CMD.SW_RESTORE);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform) return widget.childBuilder(_handleFullscreen, _isFullscreen);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: Column(
        children: [
          // 标题栏：仅非全屏时显示。全屏后由 webrtc_remote 内置按钮（toggleFullscreen 回调）退出
          if (!_isFullscreen)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                color: Color(0xCC1a1a2e),
                border: Border(bottom: BorderSide(color: Color(0x882a2a3e))),
              ),
              child: Row(
                children: [
                  Icon(Icons.connected_tv, size: 14, color: Colors.blue.shade300),
                  const SizedBox(width: 8),
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                  const SizedBox(width: 16),
                  // Drag area
                  Expanded(
                    child: MouseRegion(
                      cursor: widget.isStandaloneWindow ? SystemMouseCursors.move : MouseCursor.defer,
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: widget.isStandaloneWindow
                            ? (event) {
                                if ((event.buttons & kPrimaryButton) == 0) return;
                                WindowControl.startDragging(widget.windowId);
                              }
                            : null,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  // Minimize button
                  if (widget.onMinimize != null)
                    _windowButton(
                      icon: LucideIcons.minus,
                      tooltip: '最小化到 Dock',
                      onPressed: widget.onMinimize!,
                    ),
                  // Close button
                  _windowButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close',
                    onPressed: _handleClose,
                    hoverColor: Colors.red.withOpacity(0.2),
                  ),
                ],
              ),
            ),
          // 视频内容：填充剩余空间（全屏时占满整个 Scaffold）
          Expanded(
            child: widget.childBuilder(_handleFullscreen, _isFullscreen),
          ),
        ],
      ),
    );
  }

  Widget _windowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? hoverColor,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16, color: Colors.white54),
      tooltip: tooltip,
      onPressed: onPressed,
      hoverColor: hoverColor ?? Colors.white.withOpacity(0.1),
      splashRadius: 16,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
