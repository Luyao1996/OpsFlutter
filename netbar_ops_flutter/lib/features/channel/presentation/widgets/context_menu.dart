import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';

/// 右键菜单项
class ContextMenuItem {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool divider;
  final bool disabled;

  const ContextMenuItem({
    required this.label,
    required this.icon,
    this.color,
    this.onTap,
    this.divider = false,
    this.disabled = false,
  });
}

/// 右键菜单
class ContextMenu extends StatelessWidget {
  final List<ContextMenuItem> items;
  final Offset position;
  final VoidCallback onClose;

  const ContextMenu({
    super.key,
    required this.items,
    required this.position,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 背景遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        // 菜单
        Positioned(
          left: position.dx,
          top: position.dy,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppShadows.lg,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++) ...[
                    if (items[i].divider && i > 0)
                      Divider(height: 1, color: Colors.grey.shade200),
                    _buildMenuItem(items[i]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(ContextMenuItem item) {
    return InkWell(
      onTap: item.disabled
          ? null
          : () {
              onClose();
              item.onTap?.call();
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 16,
              color: item.disabled
                  ? Colors.grey.shade300
                  : (item.color ?? Colors.grey.shade600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: item.disabled
                      ? Colors.grey.shade400
                      : (item.color ?? Colors.grey.shade700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示右键菜单
void showContextMenu({
  required BuildContext context,
  required Offset position,
  required List<ContextMenuItem> items,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  // Clamp menu position to keep it within the visible overlay bounds (mobile).
  const menuWidth = 180.0;
  const itemHeight = 44.0;
  final dividerCount = items.where((i) => i.divider).length;
  final menuHeight = (items.length * itemHeight) + (dividerCount * 1.0);
  final media = MediaQuery.of(context);
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final size = overlayBox.size;
  const margin = 8.0;
  final minX = margin;
  final maxX = (size.width - menuWidth - margin).clamp(minX, double.infinity);
  final minY = media.padding.top + margin;
  final maxY = (size.height - media.padding.bottom - menuHeight - margin).clamp(minY, double.infinity);
  final clamped = Offset(
    position.dx.clamp(minX, maxX),
    position.dy.clamp(minY, maxY),
  );

  entry = OverlayEntry(
    builder: (context) => ContextMenu(
      items: items,
      position: clamped,
      onClose: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

/// 文件操作菜单项
class FileContextMenuItems {
  static List<ContextMenuItem> forFile({
    required VoidCallback onOpen,
    required VoidCallback onEdit,
    required VoidCallback onDownload,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    required VoidCallback onAddToStartup,
    bool isTextFile = false,
    bool canEdit = true,
    bool canAddToStartup = true,
    bool canDownload = true,
  }) {
    return [
      ContextMenuItem(
        label: '打开',
        icon: LucideIcons.externalLink,
        onTap: onOpen,
      ),
      // 所有文件都可以编辑
      ContextMenuItem(label: '编辑', icon: LucideIcons.edit, onTap: onEdit),
      if (canDownload)
        ContextMenuItem(
          label: '下载',
          icon: LucideIcons.download,
          onTap: onDownload,
          divider: true,
        ),
      ContextMenuItem(
        label: '复制',
        icon: LucideIcons.copy,
        onTap: onCopy,
        divider: true,
      ),
      ContextMenuItem(
        label: '剪切',
        icon: LucideIcons.scissors,
        onTap: onCut,
        disabled: !canEdit,
      ),
      ContextMenuItem(
        label: '重命名',
        icon: LucideIcons.pencil,
        onTap: onRename,
        disabled: !canEdit,
      ),
      if (canAddToStartup)
        ContextMenuItem(
          label: '添加到启动项',
          icon: LucideIcons.zap,
          onTap: onAddToStartup,
          disabled: !canEdit,
          divider: true,
        ),
      ContextMenuItem(
        label: '删除',
        icon: LucideIcons.trash2,
        color: Colors.red,
        onTap: onDelete,
        disabled: !canEdit,
        divider: true,
      ),
    ];
  }

  static List<ContextMenuItem> forFolder({
    required VoidCallback onOpen,
    required VoidCallback onDownload,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    bool canEdit = true,
    bool canDownload = true,
  }) {
    return [
      ContextMenuItem(label: '打开', icon: LucideIcons.folderOpen, onTap: onOpen),
      if (canDownload)
        ContextMenuItem(
          label: '下载',
          icon: LucideIcons.download,
          onTap: onDownload,
          divider: true,
        ),
      ContextMenuItem(
        label: '复制',
        icon: LucideIcons.copy,
        onTap: onCopy,
        divider: !canDownload,
      ),
      ContextMenuItem(
        label: '剪切',
        icon: LucideIcons.scissors,
        onTap: onCut,
        disabled: !canEdit,
      ),
      ContextMenuItem(
        label: '重命名',
        icon: LucideIcons.pencil,
        onTap: onRename,
        disabled: !canEdit,
      ),
      ContextMenuItem(
        label: '删除',
        icon: LucideIcons.trash2,
        color: Colors.red,
        onTap: onDelete,
        disabled: !canEdit,
        divider: true,
      ),
    ];
  }

  static List<ContextMenuItem> forEmpty({
    required VoidCallback onNewFolder,
    required VoidCallback onUpload,
    required VoidCallback onPaste,
    required VoidCallback onRefresh,
    bool canPaste = false,
    bool canEdit = true,
    int clipboardCount = 0,
  }) {
    final pasteLabel = clipboardCount > 0 ? '粘贴 (已复制$clipboardCount个项)' : '粘贴';
    return [
      ContextMenuItem(
        label: '新建文件夹',
        icon: LucideIcons.folderPlus,
        onTap: onNewFolder,
        disabled: !canEdit,
      ),
      ContextMenuItem(
        label: '上传文件',
        icon: LucideIcons.upload,
        onTap: onUpload,
        disabled: !canEdit,
      ),
      ContextMenuItem(
        label: pasteLabel,
        icon: LucideIcons.clipboard,
        onTap: onPaste,
        disabled: !canPaste || !canEdit,
        divider: true,
      ),
      ContextMenuItem(
        label: '刷新',
        icon: LucideIcons.refreshCw,
        onTap: onRefresh,
        divider: true,
      ),
    ];
  }
}
