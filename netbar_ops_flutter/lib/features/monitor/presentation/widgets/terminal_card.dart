import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/terminal_api.dart';

/// 终端卡片组件 - 对应 Vue 的 TerminalCard.vue
/// 深色主题卡片，显示桌面截图与终端状态
class TerminalCard extends StatefulWidget {
  final Terminal terminal;
  final VoidCallback? onTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Uint8List? screenshotBytes; // 实时截图数据
  final String? netbarName; // 网吧名称（顶部信息栏）
  final String? groupName; // 网吧分组（顶部信息栏）
  final VoidCallback? onHoverStart; // 鼠标进入：父级启动截图轮询
  final VoidCallback? onHoverEnd; // 鼠标离开：父级停止轮询

  const TerminalCard({
    super.key,
    required this.terminal,
    this.onTap,
    this.onSecondaryTapDown,
    this.screenshotBytes,
    this.netbarName,
    this.groupName,
    this.onHoverStart,
    this.onHoverEnd,
  });

  @override
  State<TerminalCard> createState() => _TerminalCardState();
}

class _TerminalCardState extends State<TerminalCard> {
  bool _isHovered = false;

  Terminal get t => widget.terminal;

  /// 状态边框颜色
  Color get _statusBorderColor {
    switch (t.status) {
      case 0: return Colors.grey.shade400; // offline
      case 2: return AppColors.iosBlue;     // busy
      default: return AppColors.green;       // online
    }
  }

  /// 状态徽章
  Map<String, dynamic> get _statusBadge {
    switch (t.status) {
      case 0: return {'text': 'Offline', 'color': Colors.grey.shade500};
      case 2: return {'text': 'Busy', 'color': AppColors.iosBlue};
      default: return {'text': 'Online', 'color': AppColors.green};
    }
  }

  bool get _isOffline => t.status == 0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        widget.onHoverStart?.call();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        widget.onHoverEnd?.call();
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          transform: Matrix4.identity()
            ..scale(_isHovered ? 1.02 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF111827), // bg-gray-900
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _statusBorderColor.withValues(alpha: _isHovered ? 0.8 : 0.5),
              width: 2,
            ),
            boxShadow: _isHovered ? AppShadows.lg : AppShadows.sm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Opacity(
              opacity: _isOffline ? 0.6 : 1.0,
              child: ColorFiltered(
                colorFilter: _isOffline
                    ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                    : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                child: Column(
                  children: [
                    // 顶部信息栏（网吧名称 + 分组）
                    if (widget.netbarName != null) _buildTopInfoBar(),
                    // 屏幕图片区域 (aspect-video: 16:9)
                    Expanded(child: _buildScreenArea()),
                    // 设备名称底栏
                    _buildNameBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 屏幕图片区域
  Widget _buildScreenArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景桌面图片：优先使用实时截图
        Container(
          color: const Color(0xFF1F2937), // bg-gray-800 作为占位背景
          child: widget.screenshotBytes != null
              ? Image.memory(
                  widget.screenshotBytes!,
                  fit: BoxFit.cover,
                  // hover 每 500ms 换新帧时保留上一帧直到新帧解码完成，消除闪白
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                )
              : (t.hasScreenshot
                  ? Image.network(
                      t.screenshotUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return _buildPlaceholder();
                      },
                    )
                  // 无截图/离线：本地占位图（不再请求外部随机图）
                  : Image.asset(kScreenshotPlaceholderAsset, fit: BoxFit.cover)),
        ),
        // 右上角: 状态 & 运行时间
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _statusBadge['color'] as Color,
                  ),
                ),
                const SizedBox(width: 4),
                // 版本号（仅非空时显示）—— 略淡于 uptime，区分次要信息
                if (t.version != null && t.version!.isNotEmpty) ...[
                  Text(
                    'v${t.version}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.7),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  t.uptime.isNotEmpty ? t.uptime : '0天',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.9),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
        // 左上角：主/副服务器类型角标（终端不显示）
        if (t.isMainServer || t.isBackupServer)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (t.isMainServer ? AppColors.iosBlue : AppColors.orange)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t.deviceTypeLabel,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 占位图
  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1F2937),
      child: Center(
        child: Icon(
          Icons.desktop_windows_outlined,
          size: 32,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  /// 顶部信息栏（网吧名称 + 分组）
  Widget _buildTopInfoBar() {
    final group = widget.groupName ?? '';
    final label = group.isNotEmpty ? '${widget.netbarName} $group' : widget.netbarName ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF1F2937), // bg-gray-800
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// 设备名称底栏
  Widget _buildNameBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: const Color(0xFF1F2937), // bg-gray-800
      child: Text(
        t.name,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
