import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../core/theme/app_theme.dart';

enum NoticeLevel { info, success, warning, error }

int _noticeToken = 0;
OverlayEntry? _noticeEntry;

Color _backgroundColor(NoticeLevel level) {
  switch (level) {
    case NoticeLevel.success:
      return const Color(0xFF16A34A);
    case NoticeLevel.warning:
      return const Color(0xFFF59E0B);
    case NoticeLevel.error:
      return const Color(0xFFDC2626);
    case NoticeLevel.info:
      return AppColors.iosBlue;
  }
}

IconData _icon(NoticeLevel level) {
  switch (level) {
    case NoticeLevel.success:
      return Icons.check_circle_outline;
    case NoticeLevel.warning:
      return Icons.warning_amber_outlined;
    case NoticeLevel.error:
      return Icons.error_outline;
    case NoticeLevel.info:
      return Icons.info_outline;
  }
}

bool _useAndroidBanner() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool _preferOverlayNotice(BuildContext context) {
  if (!_useAndroidBanner()) return true;
  final route = ModalRoute.of(context);
  // Dialog/BottomSheet 等 PopupRoute 场景下，ScaffoldMessenger 的 banner 会被遮罩层盖住；
  // 用 root overlay 插入的 notice 才能保证在最顶层显示。
  if (route is PopupRoute) return true;
  // 某些场景下可能找不到 ScaffoldMessenger，也回退到 overlay。
  return ScaffoldMessenger.maybeOf(context) == null;
}

void showTopNotice(
  BuildContext context,
  String message, {
  NoticeLevel level = NoticeLevel.info,
  Duration duration = const Duration(seconds: 2),
}) {
  showTopBanner(
    context,
    content: Text(message),
    level: level,
    duration: duration,
  );
}

void showTopBanner(
  BuildContext context, {
  required Widget content,
  NoticeLevel level = NoticeLevel.info,
  Duration? duration,
}) {
  if (_preferOverlayNotice(context)) {
    showTopBubble(
      context,
      content: content,
      level: level,
      duration: duration,
    );
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.hideCurrentSnackBar();
  messenger.clearSnackBars();
  messenger.clearMaterialBanners();
  _noticeEntry?.remove();
  _noticeEntry = null;

  final token = ++_noticeToken;

  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: _backgroundColor(level),
      leading: Icon(_icon(level), color: Colors.white),
      content: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white, fontSize: 13),
        child: content,
      ),
      actions: [
        TextButton(
          onPressed: messenger.hideCurrentMaterialBanner,
          child: const Text('关闭', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (duration == null) return;
  Future<void>.delayed(duration, () {
    if (token != _noticeToken) return;
    messenger.clearMaterialBanners();
  });
}

void showTopBubble(
  BuildContext context, {
  required Widget content,
  NoticeLevel level = NoticeLevel.info,
  Duration? duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  _noticeEntry?.remove();
  _noticeEntry = null;

  final token = ++_noticeToken;

  _noticeEntry = OverlayEntry(
    builder: (context) {
      return SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: _backgroundColor(level),
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    child: Row(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Icon(_icon(level), color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: content),
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: () {
                            _noticeEntry?.remove();
                            _noticeEntry = null;
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(_noticeEntry!);

  if (duration == null) return;
  Future<void>.delayed(duration, () {
    if (token != _noticeToken) return;
    _noticeEntry?.remove();
    _noticeEntry = null;
  });
}

void hideTopNotice(BuildContext context) {
  ScaffoldMessenger.maybeOf(context)?.clearMaterialBanners();
  _noticeEntry?.remove();
  _noticeEntry = null;
}
