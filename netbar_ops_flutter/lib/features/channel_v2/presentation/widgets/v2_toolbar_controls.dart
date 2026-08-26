/// 通道 V2 工具条控件三件套（搜索框 / 按钮 / 下拉），统一控件高度的**单一真源**。
///
/// 【为什么必须存在这个文件，留痕】
/// 「搜索框比按钮矮」这个视觉问题已经被用户报了三轮，每轮都是在某一个弹窗里就地补
/// 一次高度，下一个弹窗照旧。根因有两个，且方向相反，各写各的一定对不齐：
///
///   1. **按钮被全局 density 缩了**：`lib/main.dart:374` 给全局主题设了
///      `visualDensity: VisualDensity.adaptivePlatformDensity`，桌面端解析为
///      compact(-2,-2)，baseSizeAdjustment = -8 → 按钮 style 里的
///      `minimumSize: Size(0, 40)` 实际按 32 生效。**minimumSize 只是下限，
///      管不住 density**，所以「写了 minimumSize 就等高」是错的。
///   2. **输入框/下拉的边框不听 SizedBox**：TextField / DropdownButtonFormField
///      的可见边框由 InputDecorator 的 `containerHeight` 决定，而 containerHeight
///      是它**按自身内容**算出来的（`isDense: true` 时 minContainerHeight 被置 0，
///      纵向 padding 为 0 就只剩一行文字高 ≈18~20px）。外面套
///      `SizedBox(height: 40)` 只是**占位** 40px，边框仍然是那个矮盒子。
///
/// 于是同一行里渲染出「输入框≈20 / 按钮≈32」，两者都不是 40、且互不相等。
///
/// 【本文件的两条硬约束】
///   - 输入框与下拉的**边框一律由外层 Container 自绘**（TextField 用
///     `isCollapsed` + 全部 border=none + `filled:false`，让 InputDecorator 彻底
///     不画装饰、也不参与高度决策），高度恒等于 [kV2ControlHeight]；
///   - 按钮一律用 **tight 的 SizedBox 包裹**（ConstrainedBox 会把外部紧约束
///     enforce 给子节点，按钮高度必然等于给定值），并在 `styleFrom` 里写死
///     `visualDensity: VisualDensity.standard` + `tapTargetSize: shrinkWrap`，
///     **不吃全局 density**（SizedBox 哪天被去掉也还有这层兜底）。
///
/// 【后续新增工具条一律用这三个控件】不要再在各自弹窗里写 `SizedBox(height: 34)`
/// + 裸 `OutlinedButton`，那就是这三轮 bug 的复发路径。需要别的高度时传 [height]，
/// 但同一行内必须共用同一个值。
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 工具条控件统一高度（单一真源）。
const double kV2ControlHeight = 40;

/// 工具条控件默认边框色（与 Element Plus 的 --el-border-color 同色）
const Color kV2ControlBorderColor = Color(0xFFDCDFE6);

/// 工具条控件默认聚焦色
const Color kV2ControlFocusColor = Color(0xFF007AFF);

/// 工具条控件默认圆角
const double kV2ControlRadius = 8;

/// 工具条控件统一外框（输入框 / 下拉共用；按钮那边由 shape 走同一套圆角）。
BoxDecoration _controlBox({
  required bool focused,
  required Color borderColor,
  required Color focusColor,
  required double radius,
  Color? fillColor,
}) =>
    BoxDecoration(
      color: fillColor ?? Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: focused ? focusColor : borderColor,
        width: focused ? 1.5 : 1,
      ),
    );

// ===========================================================================
// 搜索 / 输入框
// ===========================================================================

/// 工具条输入框。边框自绘，高度恒为 [height]。
///
/// 聚焦高亮只能靠 FocusNode 自己监听（边框不再由 InputDecorator 画，
/// 它的 focusedBorder 已经被置 none）。外部不传 [focusNode] 时本控件自建一个。
class V2ToolbarTextField extends StatefulWidget {
  final TextEditingController controller;
  final String? hintText;

  /// 固定宽度；null = 由父级约束决定（放进 Expanded / SizedBox 里）
  final double? width;
  final double height;

  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// 外部要控制焦点时传入；否则本控件自建并自行 dispose
  final FocusNode? focusNode;

  /// 左侧图标（如放大镜）。自绘边框下不能用 InputDecoration.prefixIcon
  /// （它会把 containerHeight 顶高），这里直接排进 Row。
  final Widget? prefixIcon;

  /// 右侧挂件（如清除按钮）。同理排进 Row，并被 [height] 收紧，
  /// 不会像 InputDecoration.suffixIcon 那样被 IconButton 的 40/48 撑破。
  final Widget? suffix;

  final double fontSize;
  final double hintFontSize;
  final double radius;
  final Color borderColor;
  final Color focusColor;
  final Color? fillColor;

  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final bool enabled;

  const V2ToolbarTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.width,
    this.height = kV2ControlHeight,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.prefixIcon,
    this.suffix,
    this.fontSize = 13,
    this.hintFontSize = 12,
    this.radius = kV2ControlRadius,
    this.borderColor = kV2ControlBorderColor,
    this.focusColor = kV2ControlFocusColor,
    this.fillColor,
    this.keyboardType,
    this.textInputAction = TextInputAction.search,
    this.enabled = true,
  });

  @override
  State<V2ToolbarTextField> createState() => _V2ToolbarTextFieldState();
}

class _V2ToolbarTextFieldState extends State<V2ToolbarTextField> {
  FocusNode? _owned;

  FocusNode get _node => widget.focusNode ?? (_owned ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant V2ToolbarTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _owned)?.removeListener(_onFocusChanged);
      _node.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    // 只 dispose 自己建的那个；外部传进来的由外部负责
    _owned?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: widget.controller,
      focusNode: _node,
      enabled: widget.enabled,
      style: TextStyle(fontSize: widget.fontSize),
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      // isCollapsed + 全部边框 none + filled:false：InputDecorator 什么都不画、
      // 也不参与高度决策（全局 inputDecorationTheme 的 filled/enabledBorder/
      // focusedBorder 会被这里逐项覆盖），盒子由外层 Container 负责
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        hintText: widget.hintText,
        hintStyle: TextStyle(
            fontSize: widget.hintFontSize, color: const Color(0xFF9CA3AF)),
      ),
    );

    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: _controlBox(
        focused: _node.hasFocus,
        borderColor: widget.borderColor,
        focusColor: widget.focusColor,
        radius: widget.radius,
        fillColor: widget.fillColor,
      ),
      child: (widget.prefixIcon == null && widget.suffix == null)
          ? field
          : Row(
              children: [
                if (widget.prefixIcon != null) ...[
                  widget.prefixIcon!,
                  const SizedBox(width: 6),
                ],
                Expanded(child: field),
                if (widget.suffix != null) ...[
                  const SizedBox(width: 4),
                  widget.suffix!,
                ],
              ],
            ),
    );
  }
}

// ===========================================================================
// 按钮
// ===========================================================================

/// 工具条按钮。tight SizedBox 决定最终高度，style 里写死 density 兜底。
class V2ToolbarButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// true = 主按钮（实心 ElevatedButton）；false = 次按钮（描边 OutlinedButton）
  final bool primary;

  final double height;
  final double? width;
  final double fontSize;
  final double radius;
  final Color borderColor;

  const V2ToolbarButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.height = kV2ControlHeight,
    this.width,
    this.fontSize = 13,
    this.radius = kV2ControlRadius,
    this.borderColor = kV2ControlBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

    // minimumSize / visualDensity 只是兜底：真正定高的是下面那层 tight SizedBox。
    // 写死 visualDensity 是为了「哪天有人去掉 SizedBox」时不会被全局
    // adaptivePlatformDensity(桌面=compact) 悄悄缩回 32。
    final style = primary
        ? ElevatedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: shape,
          )
        : OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(color: borderColor),
            shape: shape,
          );

    final text = Text(label, style: TextStyle(fontSize: fontSize));

    final Widget button;
    if (icon != null) {
      button = primary
          ? ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 14),
              label: text)
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 14),
              label: text);
    } else {
      button = primary
          ? ElevatedButton(onPressed: onPressed, style: style, child: text)
          : OutlinedButton(onPressed: onPressed, style: style, child: text);
    }

    return SizedBox(height: height, width: width, child: button);
  }
}

// ===========================================================================
// 下拉
// ===========================================================================

/// 工具条下拉项
typedef V2DropdownOption<T> = ({T value, String label});

/// 工具条下拉。边框自绘（同 [V2ToolbarTextField] 的理由），高度恒为 [height]。
class V2ToolbarDropdown<T> extends StatelessWidget {
  final T value;
  final List<V2DropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  final double width;
  final double height;
  final double fontSize;
  final double radius;
  final Color borderColor;

  const V2ToolbarDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width = 130,
    this.height = kV2ControlHeight,
    this.fontSize = 13,
    this.radius = kV2ControlRadius,
    this.borderColor = kV2ControlBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: _controlBox(
        focused: false,
        borderColor: borderColor,
        focusColor: kV2ControlFocusColor,
        radius: radius,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          // isExpanded：DropdownButton 默认按**最宽 item 的固有宽度**撑开自己，
          // 文案一长就会顶破固定宽度并硬溢出；配 ellipsis 后最坏只是截断
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown,
              size: 14, color: Color(0xFF9CA3AF)),
          style: TextStyle(fontSize: fontSize, color: const Color(0xFF1F2937)),
          items: [
            for (final o in options)
              DropdownMenuItem<T>(
                value: o.value,
                child:
                    Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}
