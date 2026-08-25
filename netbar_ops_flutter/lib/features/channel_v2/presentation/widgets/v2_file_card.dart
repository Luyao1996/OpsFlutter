import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../data/channel_v2_models.dart';

/// V2 文件卡：资源区与下发区共用（对齐 ResourceZone.vue 文件卡 + 角标区），
/// 抽成独立组件避免两区样式漂移。

/// 扩展名 → 图标底色（对照 ResourceZone.vue:825-835 file-{ext} 配色）
Color v2FileIconColor(V2File file) {
  if (file.isFolder) return const Color(0xFFFFB300);
  switch (file.extension) {
    case 'exe':
    case 'msi':
      return const Color(0xFF6C5CE7);
    case 'pdf':
      return const Color(0xFFE17055);
    case 'doc':
    case 'docx':
      return const Color(0xFF0984E3);
    case 'xls':
    case 'xlsx':
      return const Color(0xFF00B894);
    case 'ppt':
    case 'pptx':
      return const Color(0xFFFD79A8);
    case 'zip':
    case 'rar':
    case '7z':
      return const Color(0xFFA29BFE);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
      return const Color(0xFFFDCB6E);
    case 'ini':
    case 'cfg':
    case 'conf':
      return const Color(0xFF636E72);
    case 'txt':
      return const Color(0xFFFAB1A0);
    case 'mp4':
    case 'avi':
      return const Color(0xFFFF7675);
    case 'mp3':
    case 'wav':
      return const Color(0xFF74B9FF);
    default:
      return const Color(0xFF9CA3AF);
  }
}

/// 扩展名 → 图标（对照 ResourceZone.vue:543-560 fileIconByExt）
IconData v2FileIcon(V2File file) {
  if (file.isFolder) return LucideIcons.folder;
  switch (file.extension) {
    case 'exe':
    case 'msi':
      return LucideIcons.settings;
    case 'pdf':
    case 'doc':
    case 'docx':
    case 'txt':
      return LucideIcons.fileText;
    case 'xls':
    case 'xlsx':
      return LucideIcons.table;
    case 'ppt':
    case 'pptx':
      return LucideIcons.presentation;
    case 'ini':
    case 'cfg':
    case 'conf':
      return LucideIcons.fileCode;
    case 'zip':
    case 'rar':
    case '7z':
      return LucideIcons.fileArchive;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
      return LucideIcons.fileImage;
    case 'mp4':
    case 'avi':
      return LucideIcons.fileVideo;
    case 'mp3':
    case 'wav':
      return LucideIcons.fileAudio;
    default:
      return LucideIcons.file;
  }
}

String v2FormatSize(int? size) {
  if (size == null || size < 0) return '';
  if (size < 1024) return '$size B';
  final kb = size / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(1)} GB';
}

class V2FileCard extends StatelessWidget {
  final V2File file;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// 右键（桌面）— 传全局坐标供菜单定位
  final void Function(Offset globalPosition)? onSecondaryTap;

  /// 长按（触屏）— 与右键同语义
  final void Function(Offset globalPosition)? onLongPress;

  /// inline 重命名编辑器：非空时**替换**文件名文本渲染。
  /// 由 ResourceZone 传入（编辑态、焦点、提交/取消都归 ResourceZone 管），
  /// 卡片本身不持有编辑状态，避免列表重建时编辑框被丢弃。
  final Widget? nameEditor;

  const V2FileCard({
    super.key,
    required this.file,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.nameEditor,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = v2FileIconColor(file);
    final sizeText = file.isFolder ? '' : v2FormatSize(file.size);
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap!(d.globalPosition),
      onLongPressStart:
          onLongPress == null ? null : (d) => onLongPress!(d.globalPosition),
      child: Container(
        width: 92,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF007AFF).withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF007AFF).withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: file.isFolder
                            ? null
                            : iconColor.withValues(alpha: 0.14),
                        gradient: file.isFolder
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        v2FileIcon(file),
                        size: 22,
                        color: file.isFolder ? Colors.white : iconColor,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -2,
                    left: -2,
                    child: _BadgeRow(file: file),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (nameEditor != null)
              nameEditor!
            else
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  // 源文件已被删除的下发节点红显（对齐规格 missing 红显）
                  color:
                      file.missing ? const Color(0xFFDC2626) : const Color(0xFF333333),
                ),
              ),
            if (sizeText.isNotEmpty)
              Text(
                sizeText,
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }
}

/// 列表视图行（对照 ResourceZone.vue:894-960 `.view-list` 的 CSS 覆盖：
/// 同一套卡片语义换成横向单行 + 缩小角标，不是另一套数据结构）。
class V2FileRow extends StatelessWidget {
  final V2File file;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition)? onSecondaryTap;
  final void Function(Offset globalPosition)? onLongPress;
  final Widget? nameEditor;

  const V2FileRow({
    super.key,
    required this.file,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.onLongPress,
    this.nameEditor,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = v2FileIconColor(file);
    final sizeText = file.isFolder ? '' : v2FormatSize(file.size);
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: onSecondaryTap == null
          ? null
          : (d) => onSecondaryTap!(d.globalPosition),
      onLongPressStart:
          onLongPress == null ? null : (d) => onLongPress!(d.globalPosition),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF007AFF).withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? const Color(0xFF007AFF).withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color:
                          file.isFolder ? null : iconColor.withValues(alpha: 0.14),
                      gradient: file.isFolder
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                            )
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      v2FileIcon(file),
                      size: 14,
                      color: file.isFolder ? Colors.white : iconColor,
                    ),
                  ),
                  Positioned(
                    top: -3,
                    left: -3,
                    // 列表视图角标缩到 0.65（对齐 .view-list 的 transform: scale(0.65)）
                    child: Transform.scale(
                      scale: 0.65,
                      alignment: Alignment.topLeft,
                      child: _BadgeRow(file: file),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: nameEditor ??
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: file.missing
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF333333),
                    ),
                  ),
            ),
            if (sizeText.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(sizeText,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 角标区（对照 ResourceZone.vue:93-108 admin-badges-wrapper，配色同源）
class _BadgeRow extends StatelessWidget {
  final V2File file;
  const _BadgeRow({required this.file});

  @override
  Widget build(BuildContext context) {
    final badges = <Widget>[];
    if (file.adminType == 'headquarters') {
      badges.add(_badge('总', const Color(0xFF4CAF50), tooltip: '总部'));
    }
    if (file.inherited) {
      badges.add(_badge('继', const Color(0xFF607D8B),
          tooltip: '继承自${file.sourceName.isNotEmpty ? file.sourceName : '上级'}，只能查看'));
    }
    if (file.showStartupBadge) {
      badges.add(_badge('启', const Color(0xFFFF9800),
          tooltip: file.isFolder ? '包含启动项' : '开机启动'));
    }
    if (file.isHide) {
      badges.add(_badge('隐', const Color(0xFFADA8AD), tooltip: '隐藏'));
    }
    // 分组文件蓝色首字徽标（对齐 web badge-nickname：nickname 有值且非总部）
    if (file.nickname.isNotEmpty && file.adminType == null) {
      final initial =
          file.groupName.trim().isNotEmpty ? file.groupName.trim()[0] : file.nickname.trim()[0];
      badges.add(_badge(initial, const Color(0xFF1976D2), tooltip: file.nickname));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < badges.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          badges[i],
        ],
      ],
    );
  }

  Widget _badge(String text, Color color, {String? tooltip}) {
    final chip = Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip, child: chip);
  }
}
