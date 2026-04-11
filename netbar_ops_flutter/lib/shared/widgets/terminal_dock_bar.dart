import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../features/desktop/data/desktop_api.dart';
import '../../features/monitor/presentation/widgets/terminal_card.dart';
import '../providers/app_providers.dart';
import '../providers/terminal_dock_provider.dart';
import '../services/terminal_dock_actions.dart';
import '../services/terminal_window_bridge.dart';

class TerminalDockBar extends ConsumerStatefulWidget {
  const TerminalDockBar({super.key});

  @override
  ConsumerState<TerminalDockBar> createState() => _TerminalDockBarState();
}

class _TerminalDockBarState extends ConsumerState<TerminalDockBar>
    with WidgetsBindingObserver {
  Offset? _offset;
  final _dockKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    if (_offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _offset == null) return;
      final screen = MediaQuery.of(context).size;
      final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
      final dockSize = box?.size ?? const Size(200, 72);
      final clamped = Offset(
        _offset!.dx.clamp(0.0, (screen.width - dockSize.width).clamp(0.0, double.infinity)),
        _offset!.dy.clamp(0.0, (screen.height - dockSize.height).clamp(0.0, double.infinity)),
      );
      if (clamped != _offset) setState(() => _offset = clamped);
    });
  }

  Offset _clampOffset(Offset raw) {
    final screen = MediaQuery.of(context).size;
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    final dockSize = box?.size ?? const Size(200, 72);
    return Offset(
      raw.dx.clamp(0.0, (screen.width - dockSize.width).clamp(0.0, double.infinity)),
      raw.dy.clamp(0.0, (screen.height - dockSize.height).clamp(0.0, double.infinity)),
    );
  }

  void _onPanStart(DragStartDetails details) {
    if (_offset != null) return;
    final box = _dockKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    _offset = box.localToGlobal(Offset.zero);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_offset == null) return;
    setState(() {
      _offset = _clampOffset(Offset(
        _offset!.dx + details.delta.dx,
        _offset!.dy + details.delta.dy,
      ));
    });
  }

  Widget _buildDockContent(List<TerminalDockItem> items) {
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      child: Container(
        key: _dockKey,
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: AppShadows.lg,
        ),
        child: items.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.layoutDashboard,
                        size: 14, color: Colors.grey),
                    SizedBox(width: 6),
                    Text(
                      '无打开的终端',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items) ...[
                    TerminalDockIcon(item: item),
                    const SizedBox(width: 10),
                  ],
                  Container(
                      width: 1, height: 36, color: Colors.grey.shade200),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '关闭所有终端',
                    child: InkWell(
                      onTap: () async {
                        await TerminalDockActions.closeAllWithRef(ref);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              LucideIcons.xCircle,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '全部关闭',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(terminalDockProvider);
    final items = state.items.values.toList()
      ..sort((a, b) => a.terminalId.compareTo(b.terminalId));

    final dock = _buildDockContent(items);

    if (_offset == null) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: dock,
          ),
        ),
      );
    }

    return Positioned(
      left: _offset!.dx,
      top: _offset!.dy,
      child: dock,
    );
  }
}

class TerminalDockIcon extends ConsumerStatefulWidget {
  final TerminalDockItem item;

  const TerminalDockIcon({super.key, required this.item});

  @override
  ConsumerState<TerminalDockIcon> createState() => _TerminalDockIconState();
}

class _TerminalDockIconState extends ConsumerState<TerminalDockIcon> {
  OverlayEntry? _hoverEntry;
  Timer? _hideTimer;
  bool _isHovered = false;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    _refreshScreenshot();
  }

  Future<void> _refreshScreenshot() async {
    final netbar = ref.read(currentNetbarProvider);
    final domain = netbar.subdomainFull;
    if (domain == null || domain.isEmpty) return;

    final seatId = widget.item.terminal.seatId;
    if (seatId.isEmpty) return;

    try {
      final result = await ScreenshotApi().requestScreenshot(
        domain: domain,
        seatId: seatId,
      );
      Uint8List? bytes;
      if (result.type == ScreenshotResultType.bytes && result.bytes != null) {
        bytes = result.bytes;
      } else if (result.type == ScreenshotResultType.base64 && result.base64Data != null) {
        bytes = Uint8List.fromList(base64Decode(result.base64Data!));
      }
      if (bytes != null && mounted) {
        ref.read(terminalDockProvider.notifier).updateScreenshot(widget.item.uniqueKey, bytes);
      }
    } catch (_) {}
  }

  Widget _buildFallbackContent() {
    final t = widget.item.terminal;
    return Center(
      child: Text(
        t.name.isNotEmpty ? t.name.substring(0, 1).toUpperCase() : '${t.id}',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Future<void> _handleTap() async {
    final now = DateTime.now();
    final last = _lastTapAt;
    if (last != null && now.difference(last).inMilliseconds < 500) return;
    _lastTapAt = now;

    if (widget.item.isMinimized) {
      await TerminalWindowBridge.restoreFromDock(ref, widget.item);
    } else {
      await TerminalWindowBridge.focusWindow(widget.item);
    }
  }

  void _showHoverCard() {
    if (_hoverEntry != null) return;
    final overlay = Navigator.of(context, rootNavigator: true).overlay!;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.of(context).size;

    const cardSize = Size(280, 180);
    var left = offset.dx + size.width / 2 - cardSize.width / 2;
    var top = offset.dy - cardSize.height - 8;

    left = left.clamp(8.0, screen.width - cardSize.width - 8.0);
    top = top.clamp(8.0, screen.height - cardSize.height - 80.0);

    _hoverEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: MouseRegion(
          onEnter: (_) => _cancelHideTimer(),
          onExit: (_) => _scheduleHideHoverCard(),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: cardSize.width,
              height: cardSize.height,
              child: Stack(
                children: [
                  TerminalCard(
                    terminal: widget.item.terminal,
                    screenshotBytes: widget.item.screenshotBytes,
                    netbarName: widget.item.netbarName,
                    groupName: widget.item.groupName,
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: InkWell(
                      onTap: () {
                        _hideHoverCard();
                        TerminalDockActions.closeSingleWithRef(
                            ref, widget.item);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.x,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_hoverEntry!);
  }

  void _hideHoverCard() {
    _hideTimer?.cancel();
    _hoverEntry?.remove();
    _hoverEntry = null;
  }

  void _scheduleHideHoverCard() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 150), () {
      _hideHoverCard();
    });
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hideHoverCard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item.terminal;
    final isMin = widget.item.isMinimized;
    final statusColor = switch (t.status) {
      0 => Colors.grey.shade400,
      2 => AppColors.iosBlue,
      _ => AppColors.green,
    };

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _isHovered = true);
        _showHoverCard();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _scheduleHideHoverCard();
      },
      child: AnimatedScale(
        scale: _isHovered ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTap: _handleTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.6),
                      width: 2,
                    ),
                    boxShadow: AppShadows.sm,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: widget.item.screenshotBytes != null
                        ? Image.memory(
                            widget.item.screenshotBytes!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade50,
                              child: _buildFallbackContent(),
                            ),
                          )
                        : Image.network(
                            t.desktopThumbnailUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade50,
                              child: _buildFallbackContent(),
                            ),
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: Colors.grey.shade50,
                                child: _buildFallbackContent(),
                              );
                            },
                          ),
                  ),
                ),
                if (isMin)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(
                        LucideIcons.minus,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
