import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/router_api.dart';

class RouterCard extends StatefulWidget {
  final RouterInfo router;
  final RouterApi? api;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  /// When false, traffic polling is paused (e.g. page not visible).
  final bool active;

  const RouterCard({
    super.key,
    required this.router,
    this.api,
    this.onTap,
    this.onEdit,
    this.active = true,
  });

  @override
  State<RouterCard> createState() => _RouterCardState();
}

class _RouterCardState extends State<RouterCard> {
  bool _isHovered = false;
  RouterTraffic _traffic = const RouterTraffic();
  Timer? _pollTimer;
  bool _polling = false;

  bool get _shouldPoll => widget.active && widget.router.enabled;

  @override
  void initState() {
    super.initState();
    if (_shouldPoll) _startPolling();
  }

  @override
  void didUpdateWidget(covariant RouterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPolling = oldWidget.active && oldWidget.router.enabled;
    if (wasPolling && !_shouldPoll) {
      _stopPolling();
    } else if (!wasPolling && _shouldPoll) {
      _startPolling();
    } else if (_shouldPoll && oldWidget.router.id != widget.router.id) {
      _stopPolling();
      _startPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _pollOnce();
  }

  void _stopPolling() {
    _polling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce() async {
    if (!mounted || widget.api == null || !widget.router.enabled) return;
    _polling = true;
    try {
      final interfaces = await widget.api!.getTraffic(widget.router.id);
      if (!mounted || !_polling) return;
      setState(() => _traffic = RouterTraffic.fromInterfaces(interfaces));
    } catch (_) {
      // silently ignore traffic errors
    }
    if (!mounted || !_polling) return;
    _pollTimer = Timer(const Duration(seconds: 1), _pollOnce);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.router;
    final enabled = r.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F2027), Color(0xFF203A43)],
                  )
                : null,
            color: enabled ? null : const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled
                  ? const Color(0xFF06B6D4).withValues(alpha: _isHovered ? 0.8 : 0.4)
                  : Colors.grey.shade600.withValues(alpha: 0.3),
              width: 2,
            ),
            boxShadow: _isHovered ? AppShadows.lg : AppShadows.sm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Opacity(
              opacity: enabled ? 1.0 : 0.5,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = context.isPhone || constraints.maxHeight < 180;
                  final pad = isCompact ? 10.0 : 14.0;
                  final iconSize = isCompact ? 26.0 : 32.0;
                  final iconRadius = isCompact ? 6.0 : 8.0;
                  final nameSize = isCompact ? 12.0 : 14.0;
                  final hostSize = isCompact ? 10.0 : 11.0;
                  // Mobile: always show edit button; Desktop: hover only
                  final showEdit = widget.onEdit != null && (_isHovered || isCompact);

                  return Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(pad),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Router icon + name
                            Row(
                              children: [
                                Container(
                                  width: iconSize,
                                  height: iconSize,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(iconRadius),
                                  ),
                                  child: Icon(LucideIcons.router, size: iconSize * 0.56, color: const Color(0xFF06B6D4)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.name,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: nameSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        r.host,
                                        style: TextStyle(color: Colors.grey.shade400, fontSize: hostSize),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Traffic rates: WAN + LAN (two columns)
                            if (enabled)
                              Row(
                                children: [
                                  Expanded(
                                    child: _trafficColumn(
                                      label: '外网',
                                      labelColor: const Color(0xFFF59E0B),
                                      sendRate: _traffic.wanSendRate,
                                      recvRate: _traffic.wanRecvRate,
                                      compact: isCompact,
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: isCompact ? 24 : 30,
                                    margin: EdgeInsets.symmetric(horizontal: isCompact ? 4 : 8),
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                  Expanded(
                                    child: _trafficColumn(
                                      label: '内网',
                                      labelColor: const Color(0xFF8B5CF6),
                                      sendRate: _traffic.lanSendRate,
                                      recvRate: _traffic.lanRecvRate,
                                      compact: isCompact,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                '已禁用',
                                style: TextStyle(color: Colors.grey.shade500, fontSize: isCompact ? 10 : 12),
                              ),
                          ],
                        ),
                      ),
                      // Type badge
                      if (r.type.isNotEmpty)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              r.type,
                              style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 9, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      // Edit button: mobile=always, desktop=hover
                      if (showEdit)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Material(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: widget.onEdit,
                              child: const Padding(
                                padding: EdgeInsets.all(5),
                                child: Icon(LucideIcons.pencil, size: 12, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _trafficColumn({
    required String label,
    required Color labelColor,
    required int sendRate,
    required int recvRate,
    bool compact = false,
  }) {
    final fontSize = compact ? 9.0 : 10.0;
    final iconSz = compact ? 9.0 : 10.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: labelColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: compact ? 7 : 8, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(height: compact ? 2 : 3),
        Row(
          children: [
            Icon(LucideIcons.arrowUp, size: iconSz, color: const Color(0xFF10B981)),
            const SizedBox(width: 2),
            Expanded(
              child: Text(formatRate(sendRate),
                style: TextStyle(color: Colors.white70, fontSize: fontSize, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Icon(LucideIcons.arrowDown, size: iconSz, color: const Color(0xFF3B82F6)),
            const SizedBox(width: 2),
            Expanded(
              child: Text(formatRate(recvRate),
                style: TextStyle(color: Colors.white70, fontSize: fontSize, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
