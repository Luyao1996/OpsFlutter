import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';

/// 自适应弹出：窄屏走全屏页面（fullscreenDialog），宽屏走对话框。
///
/// 弹窗 widget 自身使用 [ResponsiveDialogScaffold] 即可同时适配两种模式。
/// 调用点几乎可作为 `showDialog` 的直接替代品。
///
/// 注意：
/// - `barrierDismissible`、`barrierColor` 仅在宽屏（Dialog）模式生效；
///   窄屏（PageRoute）模式下点击外部无法关闭，需要 widget 内部提供关闭入口。
/// - 路由返回值通过 `Navigator.pop(context, value)` 传回，两种模式语义一致。
Future<T?> showAdaptive<T>(
  BuildContext context,
  WidgetBuilder builder, {
  String? routeName,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  bool useSafeArea = true,
}) {
  if (context.isNarrow) {
    return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
      MaterialPageRoute<T>(
        builder: builder,
        fullscreenDialog: true,
        settings: routeName != null ? RouteSettings(name: routeName) : null,
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    useRootNavigator: useRootNavigator,
    useSafeArea: useSafeArea,
  );
}
