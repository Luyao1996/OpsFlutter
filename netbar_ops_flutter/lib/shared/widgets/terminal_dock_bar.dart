import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../features/monitor/presentation/widgets/terminal_card.dart';
import '../providers/terminal_dock_provider.dart';
import '../services/terminal_dock_actions.dart';
import '../services/terminal_window_bridge.dart';

class TerminalDockBar extends ConsumerWidget {
  const TerminalDockBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(terminalDockProvider);
    if (state.minimized.isEmpty) return const SizedBox.shrink();

    final items = state.minimized.values.toList()
      ..sort((a, b) => a.terminalId.compareTo(b.terminalId));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: AppShadows.lg,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items) ...[
                  TerminalDockIcon(item: item),
                  const SizedBox(width: 10),
                ],
                if (items.isNotEmpty) ...[
                  Container(width: 1, height: 36, color: Colors.grey.shade200),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '关闭所有最小化终端',
                    child: InkWell(
                      onTap: () async {
                        await TerminalDockActions.closeAllMinimizedWithRef(ref);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              LucideIcons.xCircle,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '关闭',
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
              ],
            ),
          ),
        ),
      ),
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
  bool _isHovered = false;
  DateTime? _lastTapAt;

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
    await TerminalWindowBridge.restoreFromDock(ref, widget.item);
  }

  void _showHoverCard() {
    if (_hoverEntry != null) return;
    final overlay = Overlay.of(context);
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
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: cardSize.width,
            height: cardSize.height,
            child: TerminalCard(terminal: widget.item.terminal),
          ),
        ),
      ),
    );
    overlay.insert(_hoverEntry!);
  }

  void _hideHoverCard() {
    _hoverEntry?.remove();
    _hoverEntry = null;
  }

  @override
  void dispose() {
    _hideHoverCard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.item.terminal;
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
        _hideHoverCard();
      },
      child: AnimatedScale(
        scale: _isHovered ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTap: _handleTap,
          child: Container(
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
              child: Image.network(
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
        ),
      ),
    );
  }
}
