import 'package:flutter/foundation.dart';

bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };
}

/// 是否为移动端（Android / iOS）。Web 恒为 false。
///
/// 与 features/channel/presentation/platform_helper.dart 的 `PlatformHelper.isMobile`
/// 语义完全一致，但那份在旧 channel feature 内，新页面（channel_v2）不得反向 import，
/// 故在 shared 层再落一份。
bool get isMobilePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
