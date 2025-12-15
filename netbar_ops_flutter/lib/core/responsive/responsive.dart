import 'package:flutter/widgets.dart';

import 'app_breakpoints.dart';

extension ResponsiveContext on BuildContext {
  Size get screenSize => MediaQuery.sizeOf(this);

  bool get isNarrow => screenSize.width < AppBreakpoints.narrow;

  bool get isPhone => screenSize.shortestSide < AppBreakpoints.phone;
}

