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
import 'package:flutter_html/flutter_html.dart' as fhtml;
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'dart:ffi' as ffi hide Size;
import 'package:win32/win32.dart' as win32;
import '../../../../core/logging/webrtc_crash_logger.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/storage/token_store.dart';
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
import '../../game_library/presentation/game_manage_view.dart';


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
    {'icon': LucideIcons.hardDrive, 'label': '游戏管理'},
    {'icon': LucideIcons.fileText, 'label': '文件管理'},
    {'icon': LucideIcons.activity, 'label': '进程管理'},
    {'icon': LucideIcons.terminal, 'label': '终端命令'},
    {'icon': LucideIcons.cpu, 'label': '硬件配置'},
    {'icon': LucideIcons.network, 'label': '网络监控'},
    {'icon': LucideIcons.fileSpreadsheet, 'label': '操作日志'},
  ];

  /// 游戏管理 Tab 是否处于"应用内全屏"展示
  /// （仅影响布局：true 时隐藏 Header / 左侧栏 / TabBar，让内容铺满）
  bool _gameManageFullscreen = false;

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
        data: (terminal) {
          // 游戏管理 Tab 全屏：跳过 Header / 左侧栏 / TabBar，直接铺满
          if (_selectedTab == '游戏管理' && _gameManageFullscreen) {
            return SafeArea(bottom: false, child: _buildGameManageView());
          }
          return SafeArea(
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
        );
        },
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
                        color: terminal.status == 0 ? Colors.grey : AppColors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${terminal.status == 0 ? '离线' : '在线'} | ${terminal.ip}'
                      '${(terminal.version != null && terminal.version!.isNotEmpty) ? ' | v${terminal.version}' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            // 标题后联系人 hover 按钮
            _PersonnelHoverButton(
              netbarName: _netbarName,
              merchantId: ref.watch(currentNetbarProvider).id,
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
                            color: terminal.status == 0 ? Colors.grey : AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${terminal.status == 0 ? '离线' : '在线'} | ${terminal.ip}'
                            '${(terminal.version != null && terminal.version!.isNotEmpty) ? ' | v${terminal.version}' : ''}',
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
              // 标题后联系人 hover 按钮（窄屏）
              _PersonnelHoverButton(
                netbarName: _netbarName,
                merchantId: ref.watch(currentNetbarProvider).id,
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
    final remark = terminal.remark ?? '';
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
              const Text('备注信息',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              TextButton.icon(
                onPressed: () => _openRemarkEditor(terminal),
                icon: const Icon(LucideIcons.pencil, size: 14),
                label: const Text('编辑', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(40, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80, maxHeight: 240),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: remark.isEmpty
                ? Text('暂无备注，点击"编辑"添加',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade400))
                : SingleChildScrollView(
                    child: fhtml.Html(
                      data: remark,
                      style: {
                        'body': fhtml.Style(
                          fontSize: fhtml.FontSize(12),
                          margin: fhtml.Margins.zero,
                          padding: fhtml.HtmlPaddings.zero,
                        ),
                        'p': fhtml.Style(margin: fhtml.Margins.zero),
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 打开全屏备注编辑对话框；保存成功后用返回的新 HTML 刷新本地 _liveTerminal，
  /// 不必等下次心跳。取消/X 关闭返回 null，不更新。
  Future<void> _openRemarkEditor(Terminal terminal) async {
    if (!_ensureSameNetbar('openRemarkEditor')) return;
    final newHtml = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _RemarkEditDialog(
          terminalName: terminal.name,
          initialHtml: terminal.remark ?? '',
          onSave: (html) async {
            final api = ref.read(terminalApiProvider);
            await api.saveRemark(terminal.id, html);
          },
        ),
      ),
    );
    if (newHtml != null && mounted) {
      setState(() {
        _liveTerminal =
            _cloneTerminalWithRemark(_liveTerminal ?? terminal, newHtml);
      });
    }
  }

  /// 克隆 Terminal 并替换 remark，用于保存成功后立即刷新 UI（不等心跳）。
  Terminal _cloneTerminalWithRemark(Terminal src, String newRemark) {
    return Terminal(
      id: src.id, seatId: src.seatId, name: src.name, code: src.code,
      netbarId: src.netbarId, areaId: src.areaId, ip: src.ip, mac: src.mac,
      os: src.os, type: src.type, status: src.status,
      cpuUsage: src.cpuUsage, ramUsage: src.ramUsage,
      gpuUsage: src.gpuUsage, diskUsage: src.diskUsage,
      uptime: src.uptime, screenshotUrl: src.screenshotUrl,
      lastOnline: src.lastOnline, lastHeartbeat: src.lastHeartbeat,
      createdAt: src.createdAt, updatedAt: src.updatedAt, remote: src.remote,
      mode: src.mode, version: src.version,
      remark: newRemark,
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
    setState(() {
      _selectedTab = label;
      // 切离"游戏管理"时自动退出全屏，避免下次切回来仍然是全屏态
      if (label != '游戏管理') _gameManageFullscreen = false;
    });

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
            if (terminal.mode == 1) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('服务管理'),
              const SizedBox(height: 12),
              _buildServiceGrid(terminal, isNarrow: isNarrow),
            ],
            const SizedBox(height: 24),
            _buildSectionTitle('终端管理'),
            const SizedBox(height: 12),
            _buildTerminalManageGrid(terminal, isNarrow: isNarrow),
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
    } else if (_selectedTab == '游戏管理') {
      return _buildGameManageView();
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
    } else if (_selectedTab == '操作日志') {
      return LogManagerTab(terminalId: terminal.id);
    }
    return Center(child: Text('功能模块 [$_selectedTab] 开发中...'));
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade600));
  }

  /// 构建"游戏管理"Tab 内容
  ///
  /// 数据上下文取自 [currentNetbarProvider]，与终端绑定的网吧一致。
  /// 全屏切换由本组件控制（[_gameManageFullscreen]），实际全屏布局在
  /// build 顶层判定（隐藏 Header / 左侧栏 / TabBar）。
  Widget _buildGameManageView() {
    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull ?? '';
    return GameManageView(
      merchantId: netbar.id ?? 0,
      subdomainFull: domain,
      netbarName: netbar.name ?? '',
      isFullscreen: _gameManageFullscreen,
      onToggleFullscreen: () =>
          setState(() => _gameManageFullscreen = !_gameManageFullscreen),
    );
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

      // Step 1: fetch /terminals via central HTTP and update UI immediately
      final hb = await api.getHeartbeat(terminalId, merchantId: ownerNetbarId);
      if (mounted) setState(() => _liveTerminal = hb);

      // Step 2: fetch realtime hwinfo via WebSocket in background, update UI when ready
      final seatId = hb.seatId.isNotEmpty ? hb.seatId : (_liveTerminal?.seatId ?? '');
      if (seatId.isNotEmpty && hb.status > 0) {
        api.getHardwareRealtime(seatId, merchantId: ownerNetbarId).then((rt) {
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
                mode: hb.mode, // 透传 mode，否则刷新心跳后服务管理按钮会消失
                version: hb.version, // 透传 version，否则刷新心跳后卡片版本号会丢失
                remark: hb.remark, // 信任后端 remark 最新值；本地保存后已在 _openRemarkEditor 内立即 setState 更新
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

  /// 服务管理按钮区（仅 mode==1 的 server 终端展示）。
  /// 4 个按钮：重启反代/协助/路由 + 断开远程服务。
  /// 与电源管理同款卡片样式；点击后弹简单确认对话框（"确认X吗？"）再发 WS。
  Widget _buildServiceGrid(Terminal terminal, {required bool isNarrow}) {
    final items = <_ServiceItem>[
      const _ServiceItem(label: '重启反代服务', name: '反代服务', type: 'frpc'),
      const _ServiceItem(label: '重启协助服务', name: '协助服务', type: 'client'),
      const _ServiceItem(label: '重启路由服务', name: '路由服务', type: 'router'),
      const _ServiceItem(label: '重启游戏库服务', name: '游戏库服务', type: 'gamelibray'),
      // 特殊 type 标记：路由到 _openWindowsPasswordDialog（HTTP set/reset/clear）
      // 区块本身仅 mode==1 显示，所以此项天然只在服务端可见
      const _ServiceItem(
        label: 'Windows密码',
        name: 'Windows密码',
        type: '__windows_pwd__',
        icon: LucideIcons.keyRound,
      ),
      // 复制 2FA：服务管理整体仅 mode==1 显示，与你需求一致。
      // 不弹 dialog，调 authApi.getTwoFactorCode 拿一次性 code → 写剪贴板 + toast
      const _ServiceItem(
        label: '复制2FA',
        name: '2FA',
        type: '__copy_2fa__',
        icon: LucideIcons.shieldCheck,
      ),
    ];
    Widget card(_ServiceItem it, {bool compact = false}) {
      return _buildPowerCard(
        it.label,
        it.icon,
        () => _confirmRestartService(terminal, it),
        compact: compact,
      );
    }

    if (!isNarrow) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: card(items[i])),
          ],
        ],
      );
    }
    // 窄屏：每行 2 个，动态适应 items.length（最后一行不满则右侧留白）
    // 历史 bug：曾经写死 items[0..3]，新增"复制2FA"后第 5 个按钮被吞。
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: card(items[i], compact: true)),
          const SizedBox(width: 12),
          Expanded(
            child: i + 1 < items.length
                ? card(items[i + 1], compact: true)
                : const SizedBox(),
          ),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  /// 简单确认对话框（"确认X吗？"），与电源管理的强校验对话框不同：
  /// 服务管理操作明确选用了简单 AlertDialog，避免每次让用户打字（用户决策 selection B）。
  /// 路由：
  ///   - `__windows_pwd__` → 直接弹自定义 dialog（不走简单确认）
  ///   - `__copy_2fa__` → 直接调 [_handleCopy2FA]（无确认，立即复制 + toast）
  ///   - `__disconnect_remote__` → 简单确认 → [_disconnectRemoteService]
  ///   - 其它（frpc/client/router） → 简单确认 → [_restartService]
  void _confirmRestartService(Terminal terminal, _ServiceItem item) {
    // Windows 密码自有完整 dialog（设置/重置/清除），跳过简单确认直接打开
    if (item.type == '__windows_pwd__') {
      _openWindowsPasswordDialog(terminal);
      return;
    }
    // 复制 2FA 是无副作用动作（仅本地剪贴板 + 调一次接口），不走二次确认
    if (item.type == '__copy_2fa__') {
      _handleCopy2FA();
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.label),
        content: Text('确认${item.label}吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok != true) return;
      if (item.type == '__disconnect_remote__') {
        _disconnectRemoteService(terminal);
      } else {
        _restartService(terminal, item.type, item.name);
      }
    });
  }

  Future<void> _restartService(Terminal terminal, String type, String name) async {
    if (!_ensureSameNetbar('restartService:$type')) return;
    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }
    try {
      final api = ref.read(terminalApiProvider);
      await api.restartService(type, merchantId: merchantId);
      ref.read(operationLogApiProvider).add(
            event: 'service.restart',
            description: '重启$name: ${terminal.name}',
          );
      if (mounted) {
        showTopNotice(context, '$name 重启指令已下发', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }

  /// 断开远程服务 —— 复用 [TerminalApi.remote] 的 disconnect 分支
  /// （fun:'remote', data:{enable:false}），seat 用 terminal.seatId（一般是 ServerChannel）。
  Future<void> _disconnectRemoteService(Terminal terminal) async {
    if (!_ensureSameNetbar('disconnectRemoteService')) return;
    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }
    try {
      final api = ref.read(terminalApiProvider);
      await api.remote(terminal.seatId, 'disconnect', merchantId: merchantId);
      ref.read(operationLogApiProvider).add(
            event: 'remote.disconnect',
            description: '断开远程服务: ${terminal.name}',
          );
      if (mounted) {
        showTopNotice(context, '断开指令已下发', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }

  // ============= 终端管理（更新 / 唤醒 / Windows密码 / 编辑） =============
  // 本批次仅实现：更新 + 唤醒。后两项分批做（待 WS 协议 / API 调研）。

  /// 终端管理按钮区。所有终端都展示；按钮列表按状态/mode 动态过滤。
  Widget _buildTerminalManageGrid(Terminal terminal, {required bool isNarrow}) {
    final items = <_ManageItem>[
      _ManageItem(
        label: terminal.version != null && terminal.version!.isNotEmpty
            ? '更新(v${terminal.version})'
            : '更新',
        confirmText:
            '确定要将当前版本 ${terminal.version ?? "未知"} 更新至最新版本吗？',
        icon: LucideIcons.downloadCloud,
        onConfirm: () => _doUpdateProgram(terminal),
      ),
      // 唤醒：仅离线（status==0）显示；toolboxPage 等价 useRemoteAwaken.wakeUp 入口
      if (terminal.status == 0)
        _ManageItem(
          label: '唤醒',
          confirmText: '确定要唤醒此终端吗？',
          icon: LucideIcons.power,
          onConfirm: () => _doAwaken(terminal),
        ),
      // 断开远程服务：所有终端可用（无 mode 限制）
      _ManageItem(
        label: '断开远程服务',
        confirmText: '确定要断开远程服务吗？',
        icon: LucideIcons.unplug,
        onConfirm: () => _disconnectRemoteService(terminal),
      ),
    ];

    Widget card(_ManageItem it, {bool compact = false}) {
      return _buildPowerCard(
        it.label,
        it.icon,
        () => _confirmManageAction(it),
        compact: compact,
      );
    }

    if (!isNarrow) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: card(items[i])),
          ],
          // 不足 4 列时右侧补占位，与服务管理对齐
          for (var i = items.length; i < 4; i++) ...[
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ],
      );
    }
    // 窄屏：每行 2 个
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Row(
        children: [
          Expanded(child: card(items[i], compact: true)),
          const SizedBox(width: 12),
          Expanded(
            child: i + 1 < items.length
                ? card(items[i + 1], compact: true)
                : const SizedBox(),
          ),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }

  /// 终端管理统一确认对话框（与 _confirmRestartService 同款简单 AlertDialog）。
  /// skipDefaultConfirm=true 时直接执行（用于自定义 dialog 场景，如 Windows 密码）。
  void _confirmManageAction(_ManageItem item) {
    if (item.skipDefaultConfirm) {
      item.onConfirm();
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.label),
        content: Text(item.confirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) item.onConfirm();
    });
  }

  /// 触发远端程序自更新（fun:'update'）。
  Future<void> _doUpdateProgram(Terminal terminal) async {
    if (!_ensureSameNetbar('updateProgram')) return;
    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }
    try {
      final api = ref.read(terminalApiProvider);
      await api.updateProgram(terminal.seatId, merchantId: merchantId);
      ref.read(operationLogApiProvider).add(
            event: 'terminal.update',
            description: '更新程序: ${terminal.name} (v${terminal.version ?? "?"})',
          );
      if (mounted) {
        showTopNotice(context, '更新指令已下发', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }

  /// 复制 2FA 一次性验证码 —— 调 authApi.getTwoFactorCode(terminalId) 拿 6 位 code，
  /// 写入剪贴板 + toast 提示完整 code + 剩余秒数。不弹 dialog。
  /// 后端按 terminal_id 区分 TOTP 密钥，必须传当前终端 id。
  Future<void> _handleCopy2FA() async {
    if (_copying2FA) return;
    setState(() => _copying2FA = true);
    try {
      final api = ref.read(authApiProvider);
      final res = await api.getTwoFactorCode(terminalId: widget.terminalId);
      final code = res['code']?.toString() ?? '';
      final expiresIn = res['expires_in'];
      if (code.isEmpty) {
        throw Exception('2FA 码为空');
      }
      await Clipboard.setData(ClipboardData(text: code));
      if (!mounted) return;
      final msg = expiresIn is int
          ? '2FA 已复制（$code，剩 $expiresIn 秒）'
          : '2FA 已复制：$code';
      showTopNotice(context, msg, level: NoticeLevel.success);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '复制 2FA 失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _copying2FA = false);
    }
  }

  bool _copying2FA = false;

  /// 打开 Windows 密码对话框（仅 mode==1 服务端入口）。
  /// dialog 内部走 set/reset/clear 三种 WS 协议，详见 [_WindowsPasswordDialog]。
  /// 打开前实时拉一次 `GET /merchant?keyword={网吧名称}` 取最新 server_pwd 回填，
  /// 避免缓存导致显示旧密码（保存/重置/清除后下次打开看到的也是最新值）。
  /// 注意：keyword 是模糊查询，可能返回多条结果，需用 name 全匹配二次筛选。
  Future<void> _openWindowsPasswordDialog(Terminal terminal) async {
    if (_winPwdOpening) return; // 防重入：拉取期间用户重复点不再触发
    if (!_ensureSameNetbar('openWinPwdDialog')) return;
    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    final merchantName = netbar.name;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }
    if (merchantName == null || merchantName.isEmpty) {
      if (mounted) {
        showTopNotice(context, '当前网吧名称为空，无法查询密码',
            level: NoticeLevel.error);
      }
      return;
    }
    _winPwdOpening = true;
    String initialPassword = '';
    try {
      // 用 keyword 模糊查询，再用 name 全匹配筛选（避免同名前缀干扰）
      final list = await netbar_api.NetbarApi().getList(keyword: merchantName);
      netbar_api.Netbar? matched;
      for (final m in list) {
        if (m.name == merchantName) {
          matched = m;
          break;
        }
      }
      initialPassword = matched?.serverPwd ?? '';
      debugPrint(
          '[WinPwd] keyword=$merchantName matched=${matched?.id} hasPwd=${initialPassword.isNotEmpty}');
    } catch (e) {
      // 拉取失败不阻塞 UX：用空字符串兜底，用户可重新输入
      debugPrint('[WinPwd] 拉取 server_pwd 失败: $e');
    } finally {
      _winPwdOpening = false;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WindowsPasswordDialog(
        terminalName: terminal.name,
        merchantId: merchantId,
        initialPassword: initialPassword,
      ),
    );
  }

  bool _winPwdOpening = false;

  /// 唤醒（fun:'awaken'，data:{mac}）。
  Future<void> _doAwaken(Terminal terminal) async {
    if (!_ensureSameNetbar('awakenViaWs')) return;
    if (terminal.mac.isEmpty) {
      if (mounted) {
        showTopNotice(context, '终端缺少 MAC 地址，无法唤醒',
            level: NoticeLevel.error);
      }
      return;
    }
    final netbar = ref.read(currentNetbarProvider);
    final merchantId = netbar.id;
    if (merchantId == null) {
      if (mounted) {
        showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
      }
      return;
    }
    try {
      final api = ref.read(terminalApiProvider);
      await api.awakenViaWs(terminal.mac, merchantId: merchantId);
      ref.read(operationLogApiProvider).add(
            event: 'terminal.awaken',
            description: '唤醒: ${terminal.name}',
          );
      if (mounted) {
        showTopNotice(context, '唤醒指令已下发', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
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
              () => _handleWebRTCButtonTap(terminal),
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
          () => _handleWebRTCButtonTap(terminal),
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
    final readOnly = await _showRemoteReadOnlyDialog(title: 'VNC 远程桌面');
    if (readOnly == null) return; // 用户取消
    await _openVncRemote(terminal, type: readOnly ? 'view' : 'control');
  }

  /// 点击"笨鸟远程"按钮：先弹出"是否以只读方式打开"的选择框，再根据结果打开
  Future<void> _handleWebRTCButtonTap(Terminal terminal) async {
    final readOnly = await _showRemoteReadOnlyDialog(title: '笨鸟远程');
    if (readOnly == null) return; // 用户取消
    await _openWebRTCRemote(terminal, viewOnly: readOnly);
  }

  /// 询问用户是否以只读方式打开远程。
  /// 返回：true=只读，false=控制模式，null=取消
  Future<bool?> _showRemoteReadOnlyDialog({required String title}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Expanded(child: Text(title)),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () => Navigator.of(ctx).pop(null),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          content: const Text('是否以"只读"模式打开？\n只读模式下仅能观看画面，无法操作鼠标键盘。'),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('控制模式'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.iosBlue),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('只读模式'),
            ),
          ],
        );
      },
    );
  }

  /// 打开 WebRTC 远程桌面
  /// viewOnly: true=只读模式，false=控制模式
  Future<void> _openWebRTCRemote(Terminal terminal, {bool viewOnly = false}) async {
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
        final wsUrl = 'wss://webrtc.03kan.com:443/ws?Peer=$peerId&type=Client&viewonly=$viewOnly';
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
                  // RemoteScreen 默认 viewOnly=true（只读）。必须把用户在
                  // _showRemoteReadOnlyDialog 选的结果显式透传，否则即使
                  // 用户选"控制模式"也会以只读启动。wsUrl 里的 viewonly query
                  // 是历史保留，新版包按此 viewOnly 参数为准。
                  viewOnly: viewOnly,
                  // 锁定/解锁鉴权参数（webrtc_remote ≥ feature/optimization）。
                  // 任一为 null 时锁定按钮无效，但不影响连接/画面/键鼠。
                  // 包内部会自动给 token 加 "Bearer " 前缀，此处传原始字符串。
                  accessToken: TokenStore.getToken(),
                  merchantId: _ownerNetbarId?.toString(),
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
      final netbar = ref.read(currentNetbarProvider);
      final terminalName = _liveTerminal?.name ?? seatId;
      if (action == 'wakeup') {
        // wakeOnLan 仍走 frp HTTP（见 terminal_api.dart 同方法 TODO 注释）
        final domain = netbar.subdomainFull ?? '';
        await api.wakeOnLan(seatId, domain: domain);
        // 唤醒成功上报操作日志（fire-and-forget）
        ref.read(operationLogApiProvider).add(
              event: 'remote.awaken',
              description: '唤醒: $terminalName',
            );
      } else {
        // 电源控制（controlPc）走 WebSocket
        final merchantId = netbar.id;
        if (merchantId == null) {
          if (mounted) {
            showTopNotice(context, '当前网吧 id 为空', level: NoticeLevel.error);
          }
          return;
        }
        await api.controlPc(seatId, action, merchantId: merchantId);
        // 电源操作成功上报操作日志（fire-and-forget）
        ref.read(operationLogApiProvider).add(
              event: 'remote.controlPc',
              description: '电源[$action]: $terminalName',
            );
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

/// 终端管理按钮项（仅在 _buildTerminalManageGrid 内部使用）。
/// 与 _ServiceItem 的差异：服务管理用固定 type 字符串路由分支，
/// 终端管理直接绑定 onConfirm 闭包，更灵活（每按钮逻辑独立）。
class _ManageItem {
  final String label; // 按钮文字 / 弹窗标题
  final String confirmText; // 弹窗 content（"确定要…吗？"），skipDefaultConfirm=true 时不使用
  final IconData icon;
  final Future<void> Function() onConfirm;
  /// true：跳过 _confirmManageAction 的简单 AlertDialog，直接调 onConfirm
  /// （onConfirm 内部应自行弹自定义 dialog，如 Windows 密码场景）
  final bool skipDefaultConfirm;
  const _ManageItem({
    required this.label,
    required this.confirmText,
    required this.icon,
    required this.onConfirm,
    this.skipDefaultConfirm = false,
  });
}

/// 服务管理按钮项（仅在 _buildServiceGrid 内部使用）。
class _ServiceItem {
  final String label; // 按钮文字 / 弹窗标题（如 "重启反代服务"）
  final String name; // 服务中文名（如 "反代服务"，用于 toast / operationLog 文案）
  final String type; // WS data.type（'frpc' / 'client' / 'router' /
  // '__disconnect_remote__' 特殊值：路由到断开远程逻辑）
  final IconData icon;
  const _ServiceItem({
    required this.label,
    required this.name,
    required this.type,
    this.icon = LucideIcons.refreshCw,
  });
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

/// 备注编辑全屏对话框（占满当前 Navigator 可视区域）。
/// initialHtml → HtmlToDelta → QuillController；保存时 Delta → HTML → onSave 回调。
/// 取消/X 直接 Navigator.pop(null)；保存成功 Navigator.pop(html)。
class _RemarkEditDialog extends StatefulWidget {
  final String terminalName;
  final String initialHtml;
  final Future<void> Function(String html) onSave;
  const _RemarkEditDialog({
    required this.terminalName,
    required this.initialHtml,
    required this.onSave,
  });

  @override
  State<_RemarkEditDialog> createState() => _RemarkEditDialogState();
}

class _RemarkEditDialogState extends State<_RemarkEditDialog> {
  late quill.QuillController _controller;
  final FocusNode _focusNode = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = quill.QuillController.basic();
    if (widget.initialHtml.isNotEmpty) {
      try {
        // 预处理：给无 style 的 <p> 注入 text-align:left
        // 原因：flutter_quill_delta_from_html 1.5.3 的 paragraphToOp 仅在
        // blockAttributes(align/direction/indent) 非空时才插段末 \n（见 default_html_to_ops.dart:75-78），
        // 否则相邻 <p>...</p><p>...</p> 会拼成一行。给 <p> 加 align 强制触发分段。
        final preprocessed = _ensureParagraphAlign(widget.initialHtml);
        final delta = HtmlToDelta().convert(preprocessed);
        _controller = quill.QuillController(
          document: quill.Document.fromDelta(delta),
          selection: const TextSelection.collapsed(offset: 0),
        );
      } catch (e) {
        debugPrint('[RemarkEdit] HtmlToDelta failed: $e — fallback to empty doc');
      }
    }
  }

  /// 给所有无 style/align/dir 属性的 `<p>` 注入 `style="text-align:left;"`。
  /// 兜底 flutter_quill_delta_from_html 段落分隔符丢失的 bug；
  /// 已有样式属性的段落保持不变，避免覆盖用户原有 align。
  String _ensureParagraphAlign(String html) {
    return html.replaceAllMapped(
      RegExp(r'<p(\s+[^>]*)?>'),
      (m) {
        final attrs = m.group(1) ?? '';
        if (attrs.contains('style=') ||
            attrs.contains('align=') ||
            attrs.contains('dir=')) {
          return m.group(0)!;
        }
        return '<p$attrs style="text-align:left;">';
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final deltaJson = _controller.document.toDelta().toJson();
      // inlineStylesFlag: true → 所有样式以 inline `style="..."` 输出而非 CSS class
      // (color/background/text-align/font/size/indent 全部受益)。
      // 否则输出 `class="ql-color-red"` 等无法被 HtmlToDelta 反向识别，导致 round-trip 丢样式。
      final converter = QuillDeltaToHtmlConverter(
        List<Map<String, dynamic>>.from(deltaJson),
        ConverterOptions(
          converterOptions: OpConverterOptions(inlineStylesFlag: true),
        ),
      );
      final html = converter.convert();
      await widget.onSave(html);
      if (!mounted) return;
      showTopNotice(context, '备注已保存', level: NoticeLevel.success);
      Navigator.of(context).pop(html);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 标题栏
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.terminalName} - 备注信息',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 18),
                  splashRadius: 18,
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          // 富文本工具栏（flutter_quill 11.x：参数 config + 类名 ...Config）
          quill.QuillSimpleToolbar(
            controller: _controller,
            config: const quill.QuillSimpleToolbarConfig(
              multiRowsDisplay: true,
              showAlignmentButtons: true,
              showBackgroundColorButton: true,
              showColorButton: true,
              showLink: true,
              showListBullets: true,
              showListNumbers: true,
              showListCheck: true,
              showQuote: true,
              showCodeBlock: true,
              showFontFamily: true,
              showFontSize: true,
              showHeaderStyle: true,
              showIndent: true,
              showStrikeThrough: false,
              showInlineCode: false,
              showSubscript: false,
              showSuperscript: false,
              showSearchButton: false,
            ),
          ),
          const Divider(height: 1),
          // 编辑区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: quill.QuillEditor.basic(
                controller: _controller,
                focusNode: _focusNode,
                config: const quill.QuillEditorConfig(
                  placeholder: '请输入备注内容...',
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _handleSave,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 联系电话 hover 气泡按钮（终端详情头部）。
/// 鼠标进入按钮 → 加载并显示 Overlay 气泡；首次加载后 State 内缓存（按钮生命周期内不再重复请求）。
/// 鼠标在 按钮 ↔ 气泡 之间切换不会消失（200ms 延迟 + 气泡内 MouseRegion 标记）；
/// 鼠标完全离开 200ms 后关闭气泡。
class _PersonnelHoverButton extends ConsumerStatefulWidget {
  final String netbarName;
  final int? merchantId;
  const _PersonnelHoverButton({required this.netbarName, required this.merchantId});

  @override
  ConsumerState<_PersonnelHoverButton> createState() =>
      _PersonnelHoverButtonState();
}

class _PersonnelHoverButtonState extends ConsumerState<_PersonnelHoverButton> {
  final GlobalKey _btnKey = GlobalKey();
  OverlayEntry? _overlay;
  Timer? _hideTimer;
  bool _hoveringPopover = false;

  // 缓存
  bool _loaded = false;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _personnel = [];
  Map<String, dynamic> _roleMap = {};

  @override
  void dispose() {
    _hideTimer?.cancel();
    _overlay?.remove();
    _overlay = null;
    super.dispose();
  }

  Future<void> _load() async {
    if (_loaded || _loading || widget.merchantId == null) return;
    _loading = true;
    _refreshOverlay();
    try {
      final api = ref.read(terminalApiProvider);
      final data = await api.getMerchantPersonnel(widget.merchantId!);
      if (!mounted) return;
      _personnel = (data['personnel'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _roleMap = data['roleMap'] is Map
          ? Map<String, dynamic>.from(data['roleMap'] as Map)
          : <String, dynamic>{};
      _loaded = true;
      _loading = false;
      _refreshOverlay();
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
      _loading = false;
      _refreshOverlay();
    }
  }

  void _refreshOverlay() {
    _overlay?.markNeedsBuild();
  }

  void _showPopover() {
    _hideTimer?.cancel();
    if (_overlay != null) return;

    final renderBox = _btnKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final btnPos = renderBox.localToGlobal(Offset.zero);
    final btnSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;
    final isPhone = context.isPhone;

    // 自适应宽度：手机端 = 屏宽 - 16；桌面端默认 420，但仍受屏宽约束
    const sidePadding = 8.0;
    const desktopMaxWidth = 420.0;
    final popoverWidth = (isPhone
            ? screenSize.width - sidePadding * 2
            : desktopMaxWidth)
        .clamp(220.0, screenSize.width - sidePadding * 2);

    // 自适应水平位置：默认与按钮左对齐；右溢出则贴屏右；左溢出贴屏左
    double popoverLeft = btnPos.dx;
    if (popoverLeft + popoverWidth + sidePadding > screenSize.width) {
      popoverLeft = screenSize.width - popoverWidth - sidePadding;
    }
    if (popoverLeft < sidePadding) popoverLeft = sidePadding;

    _overlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Barrier：仅手机端启用。桌面端 barrier 的 opaque hit test 会
          // 屏蔽按钮 MouseRegion → 鼠标在按钮位置被判"离开" → 200ms 关闭
          // → barrier 消失 → MouseRegion 重新感知 → 再开，形成弹/关循环。
          // 桌面端依赖 hover-out 自动关，无需 barrier。
          if (isPhone)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeImmediately,
                onPanDown: (_) => _closeImmediately(),
                child: const SizedBox.expand(),
              ),
            ),
          Positioned(
            left: popoverLeft,
            top: btnPos.dy + btnSize.height + 4,
            child: MouseRegion(
              onEnter: (_) {
                _hoveringPopover = true;
                _hideTimer?.cancel();
              },
              onExit: (_) {
                _hoveringPopover = false;
                _scheduleHide();
              },
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
                child: Container(
                  width: popoverWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: _buildPopoverContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlay!);
    // 首次显示时触发加载（已缓存则秒开）
    _load();
  }

  /// 立即关闭气泡（barrier 点击触发；不走延迟）。
  void _closeImmediately() {
    _hideTimer?.cancel();
    _hoveringPopover = false;
    _overlay?.remove();
    _overlay = null;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 200), () {
      if (!_hoveringPopover && _overlay != null) {
        _overlay!.remove();
        _overlay = null;
      }
    });
  }

  String _resolveAvatarUrl(String avatar) {
    if (avatar.isEmpty) return '';
    if (avatar.startsWith('http')) return avatar;
    // baseUrl=https://admin.wwls.net/api → origin=https://admin.wwls.net
    final origin = Uri.parse(AppConfig.baseUrl).origin;
    final cleaned = avatar.startsWith('/') ? avatar.substring(1) : avatar;
    return '$origin/$cleaned';
  }

  String _resolveRoleLabel(dynamic roleTag) {
    if (roleTag == null) return '未设置角色';
    final v = _roleMap[roleTag.toString()];
    return v?.toString() ?? '未设置角色';
  }

  Future<void> _copyPhone(String phone, String name) async {
    if (phone.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    showTopNotice(context, '已复制 $name 的电话: $phone',
        level: NoticeLevel.success);
  }

  /// 手机端拉起系统拨号面板（tel: URL scheme）。
  /// 桌面/Web 端不调用此方法（按钮仅在 isPhone 时显示）。
  Future<void> _dialPhone(String phone, String name) async {
    if (phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        showTopNotice(context, '无法拉起拨号面板：$phone',
            level: NoticeLevel.error);
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '拨号失败: $e', level: NoticeLevel.error);
    }
  }

  Widget _buildPopoverContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${widget.netbarName} - 联系电话',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('加载失败: $_error',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            )
          else if (_personnel.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: Text('暂无联系人',
                      style: TextStyle(color: Colors.grey, fontSize: 12))),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _personnel.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) => _buildItem(_personnel[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> p) {
    final nickname = p['nickname']?.toString() ?? '';
    final avatar = p['avatar']?.toString() ?? '';
    final phone = p['phone_number']?.toString() ?? '';
    final roleLabel = _resolveRoleLabel(p['role_tag']);
    final avatarUrl = _resolveAvatarUrl(avatar);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: avatarUrl.isEmpty
                  ? _avatarFallback(nickname)
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(nickname),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nickname,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(roleLabel,
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF2563EB))),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(phone,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: phone.isEmpty ? null : () => _copyPhone(phone, nickname),
            icon: const Icon(LucideIcons.copy,
                size: 12, color: Color(0xFF2563EB)),
            label: const Text('复制',
                style: TextStyle(fontSize: 11, color: Color(0xFF2563EB))),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(56, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              backgroundColor: const Color(0xFFEFF6FF),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
          ),
          // 手机端：额外加"拨打"按钮，调系统 tel: URL scheme 拉起拨号面板
          if (context.isPhone) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: phone.isEmpty ? null : () => _dialPhone(phone, nickname),
              icon: const Icon(LucideIcons.phone,
                  size: 12, color: Color(0xFF16A34A)),
              label: const Text('拨打',
                  style: TextStyle(fontSize: 11, color: Color(0xFF16A34A))),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(56, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                side: const BorderSide(color: Color(0xFFBBF7D0)), // green-200
                backgroundColor: const Color(0xFFF0FDF4), // green-50
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _avatarFallback(String nickname) {
    return Container(
      color: const Color(0xFFE5E7EB),
      alignment: Alignment.center,
      child: Text(
        nickname.isNotEmpty ? nickname.characters.first : '?',
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _showPopover(),
      onExit: (_) => _scheduleHide(),
      child: Tooltip(
        message: '联系电话',
        child: InkWell(
          key: _btnKey,
          onTap: _showPopover, // 触屏 / 无鼠标设备点击触发
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF), // 浅蓝底
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Icon(
              LucideIcons.phone,
              size: 14,
              color: Color(0xFF2563EB),
            ),
          ),
        ),
      ),
    );
  }
}

/// 服务端 Windows 密码对话框（仅 mode==1 终端可用）。
/// 参考 toolboxPage `ServerWindowsPasswordDialog.vue` 设计：
///   - step='set'：初始密码（≥8 位）→ update.windows_pass
///   - step='reset'：忘记密码后强口令重置（≥8+大写+小写+数字）→ update.reset_windows_pass
///   - 清除：弹二次确认 → update.clear_windows_pass
class _WindowsPasswordDialog extends ConsumerStatefulWidget {
  final String terminalName;
  final int merchantId;
  /// set step 输入框的初始值（一般是后端 server_pwd 当前密码）。
  /// reset step 切换时不沿用此值（强口令场景必须用户重新输入）。
  final String initialPassword;
  const _WindowsPasswordDialog({
    required this.terminalName,
    required this.merchantId,
    this.initialPassword = '',
  });

  @override
  ConsumerState<_WindowsPasswordDialog> createState() =>
      _WindowsPasswordDialogState();
}

class _WindowsPasswordDialogState
    extends ConsumerState<_WindowsPasswordDialog> {
  // step：'set' 设置初始密码 / 'reset' 重置（强口令）
  String _step = 'set';
  final TextEditingController _pwdCtrl = TextEditingController();
  String? _errorText;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 回填当前已设置的密码（仅 set step 默认显示；reset 切换时清空）
    _pwdCtrl.text = widget.initialPassword;
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  /// 设置场景校验：≥8 位
  String? _validateSet(String v) {
    if (v.isEmpty) return '请输入密码';
    if (v.length < 8) return '密码至少 8 位';
    return null;
  }

  /// 重置场景校验：≥8 + 大写 + 小写 + 数字（与 toolboxPage 一致）
  String? _validateReset(String v) {
    if (v.isEmpty) return '请输入密码';
    if (v.length < 8) return '密码至少 8 位';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return '密码必须包含大写字母';
    if (!RegExp(r'[a-z]').hasMatch(v)) return '密码必须包含小写字母';
    if (!RegExp(r'[0-9]').hasMatch(v)) return '密码必须包含数字';
    return null;
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    final pwd = _pwdCtrl.text;
    final err = _step == 'set' ? _validateSet(pwd) : _validateReset(pwd);
    if (err != null) {
      setState(() => _errorText = err);
      return;
    }
    setState(() {
      _errorText = null;
      _submitting = true;
    });
    try {
      // HTTP：POST /merchant/setPwd/{id}
      // - 保存（set）：body {password}
      // - 重置（reset）：body {password, reset:1}
      await netbar_api.NetbarApi().setPassword(
        widget.merchantId,
        password: pwd,
        reset: _step == 'reset',
      );
      ref.read(operationLogApiProvider).add(
            event: _step == 'set' ? 'win.pwd.set' : 'win.pwd.reset',
            description:
                '${_step == "set" ? "保存" : "重置"} Windows 密码: ${widget.terminalName}',
          );
      if (!mounted) return;
      showTopNotice(context,
          _step == 'set' ? 'Windows 密码已保存' : 'Windows 密码已重置',
          level: NoticeLevel.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _handleClear() async {
    if (_submitting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 Windows 密码'),
        content: const Text('确定要清除当前服务端 Windows 密码吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      // HTTP：POST /merchant/clearAllPwd FormData merchant_ids[]={id}
      await netbar_api.NetbarApi()
          .clearAllPasswords(merchantIds: [widget.merchantId]);
      ref.read(operationLogApiProvider).add(
            event: 'win.pwd.clear',
            description: '清除 Windows 密码: ${widget.terminalName}',
          );
      if (!mounted) return;
      showTopNotice(context, 'Windows 密码已清除',
          level: NoticeLevel.success);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _switchStep(String newStep) {
    setState(() {
      _step = newStep;
      _pwdCtrl.clear();
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isReset = _step == 'reset';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isReset ? '重置服务端windows密码' : '服务端windows密码',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18),
                    splashRadius: 18,
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 描述（仅 set step 显示）
            if (!isReset)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '设置安装服务端电脑 windows 密码，用于同步登录',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            // 输入框
            Padding(
              padding: EdgeInsets.fromLTRB(20, isReset ? 16 : 8, 20, 8),
              child: TextField(
                controller: _pwdCtrl,
                obscureText: false, // 与 toolboxPage 一致：明文显示便于复制
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: isReset ? '新密码' : null,
                  hintText: isReset ? '请输入新密码' : '请输入密码',
                  errorText: _errorText,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
            // 强口令提示（reset step）
            if (isReset)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  '密码必须大于等于 8 位（大写 + 小写 + 数字）',
                  style: TextStyle(
                      fontSize: 11, color: Colors.red.shade600),
                ),
              ),
            // 链接区
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  if (!isReset)
                    InkWell(
                      onTap: _submitting ? null : () => _switchStep('reset'),
                      child: Text(
                        '忘记密码？重置 windows 密码',
                        style: TextStyle(
                          fontSize: 12,
                          color: _submitting
                              ? Colors.grey.shade400
                              : const Color(0xFF409EFF),
                        ),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _submitting ? null : () => _switchStep('set'),
                      child: Text(
                        '返回设置密码',
                        style: TextStyle(
                          fontSize: 12,
                          color: _submitting
                              ? Colors.grey.shade400
                              : const Color(0xFF409EFF),
                        ),
                      ),
                    ),
                  const Spacer(),
                  InkWell(
                    onTap: _submitting ? null : _handleClear,
                    child: Text(
                      '清除密码',
                      style: TextStyle(
                        fontSize: 12,
                        color: _submitting
                            ? Colors.grey.shade400
                            : Colors.red.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 底部按钮
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submitting ? null : _handleSubmit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('保存'),
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
