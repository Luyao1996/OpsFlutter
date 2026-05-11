import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/responsive/responsive.dart';

/// 自适应"业务弹窗"骨架。
///
/// - 窄屏：Scaffold + AppBar，[footer] 放 `bottomNavigationBar`（方案 X）
/// - 宽屏：Dialog + 圆角 + 限宽限高，标题栏自带"X 关闭"按钮，[footer] 紧贴底部
///
/// 调用方只需把 build 函数从手写的 `Dialog(child: Column[...])` 改为
/// 返回 `ResponsiveDialogScaffold(title: ..., body: ..., footer: ...)`。
class ResponsiveDialogScaffold extends StatelessWidget {
  /// 标题（窄屏 AppBar.title / 宽屏 Dialog 标题栏）
  final String title;

  /// 主体内容。
  /// - 若 [scrollableBody] 为 true（默认），骨架会自动外包 SingleChildScrollView + 内边距
  /// - 若 body 内部已自带滚动（如 ListView），可设 [scrollableBody] 为 false
  final Widget body;

  /// 底部按钮区（取消/确认等）。两种模式下都贴底部展示。
  final Widget? footer;

  /// 仅窄屏：AppBar 右侧的额外按钮
  final List<Widget>? appBarActions;

  /// 仅宽屏：Dialog 最大宽度
  final double maxWidth;

  /// 仅宽屏：Dialog 最大高度（默认按屏幕 0.85 倍，上限 [maxHeightCap]）
  final double? maxHeight;

  /// 仅宽屏：Dialog 高度上限
  final double maxHeightCap;

  /// 是否让骨架自动包滚动容器与 padding
  final bool scrollableBody;

  /// body 区域的内边距（默认 EdgeInsets.all(20)）
  final EdgeInsetsGeometry bodyPadding;

  const ResponsiveDialogScaffold({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.appBarActions,
    this.maxWidth = 760,
    this.maxHeight,
    this.maxHeightCap = 820,
    this.scrollableBody = true,
    this.bodyPadding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) {
      return _buildPage(context);
    }
    return _buildDialog(context);
  }

  /// 窄屏：全屏页
  Widget _buildPage(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: appBarActions,
      ),
      body: SafeArea(
        bottom: footer == null,
        child: scrollableBody
            ? SingleChildScrollView(padding: bodyPadding, child: body)
            : body,
      ),
      bottomNavigationBar: footer != null
          ? SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: footer,
              ),
            )
          : null,
    );
  }

  /// 宽屏：Dialog
  Widget _buildDialog(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final effectiveMaxHeight = maxHeight ??
        (screenSize.height * 0.85 < maxHeightCap
            ? screenSize.height * 0.85
            : maxHeightCap);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: effectiveMaxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogHeader(title: title, actions: appBarActions),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Flexible(
              child: scrollableBody
                  ? SingleChildScrollView(padding: bodyPadding, child: body)
                  : body,
            ),
            if (footer != null)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  final String title;
  final List<Widget>? actions;

  const _DialogHeader({required this.title, this.actions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actions != null) ...actions!,
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.x, size: 18, color: Colors.grey),
            splashRadius: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
