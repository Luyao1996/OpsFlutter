import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

/// 下载卡片（用于"配套软件"模块）。
///
/// 两种使用模式：
/// 1. **URL 模式**（urlProvider 非 null，customAction 为 null）：
///    - hover → 弹出二维码气泡（手机扫码下载）
///    - 点击 → 浏览器打开 URL（PC 直接下载到本机）
///
/// 2. **自定义动作模式**（customAction 非 null）：
///    - 点击 → 执行 customAction（如弹出下载对话框）
///    - hover 不显示 overlay
class DownloadCard extends StatefulWidget {
  final IconData icon;
  final String title;

  /// 副标题（可选）。为空字符串或 null 时不渲染。
  final String? subtitle;

  /// 异步获取下载 URL。提供时启用 URL 模式。
  final Future<String?> Function()? urlProvider;

  /// 自定义点击动作。提供时覆盖默认的 launchUrl 行为，且 hover 不显示 overlay。
  final Future<void> Function(BuildContext)? customAction;

  const DownloadCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.urlProvider,
    this.customAction,
  });

  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  final _portalController = OverlayPortalController();
  final _link = LayerLink();

  String? _url;
  bool _loading = true;
  bool _failed = false;
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 没有 urlProvider 时不需要预加载（自定义动作模式直接 ready）
    if (widget.urlProvider == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = false;
      });
      return;
    }
    try {
      final url = await widget.urlProvider!();
      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
        _failed = url == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _onTap() async {
    // 自定义动作优先
    if (widget.customAction != null) {
      await widget.customAction!(context);
      return;
    }
    if (_url == null) return;
    try {
      await launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  bool get _hasUrlOverlay =>
      widget.urlProvider != null && _url != null && !_failed;

  bool get _isReady {
    // 自定义动作模式：只要不在加载中就可用
    if (widget.customAction != null) {
      return !_loading;
    }
    // URL 模式：必须加载完且有有效 URL
    return !_loading && !_failed && _url != null;
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _isReady;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (_) => _buildOverlay(),
        child: MouseRegion(
          cursor: isReady
              ? SystemMouseCursors.click
              : (_loading
                  ? SystemMouseCursors.wait
                  : SystemMouseCursors.forbidden),
          onEnter: (_) {
            setState(() => _hovering = true);
            if (_hasUrlOverlay) _portalController.show();
          },
          onExit: (_) {
            setState(() => _hovering = false);
            _portalController.hide();
          },
          child: GestureDetector(
            onTap: isReady ? _onTap : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: _hovering && isReady
                    ? AppColors.iosBlue.withValues(alpha: 0.05)
                    : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovering && isReady
                      ? AppColors.iosBlue.withValues(alpha: 0.4)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 28,
                    color: isReady ? AppColors.iosBlue : Colors.grey.shade400,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isReady
                          ? const Color(0xFF111827)
                          : Colors.grey.shade500,
                    ),
                  ),
                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    if (!_hasUrlOverlay) return const SizedBox.shrink();
    return Positioned(
      width: 200,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        offset: const Offset(0, 8),
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(10),
          shadowColor: Colors.black.withValues(alpha: 0.2),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: _url!,
                  size: 160,
                  backgroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                Text(
                  '扫码或点击卡片下载',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
