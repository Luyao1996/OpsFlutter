import 'web_drop_zone.dart';

/// Stub 实现，用于非 Web 平台
class _WebDropHandlerStub implements WebDropHandler {
  @override
  bool get supportsDirectoryDrop => false;

  @override
  void registerDropZone({
    required void Function() onDragEnter,
    required void Function() onDragLeave,
    required WebDropCallback onDrop,
  }) {}

  @override
  void unregisterDropZone() {}

  @override
  void registerPasteHandler({
    required WebDropCallback onPaste,
  }) {}

  @override
  void unregisterPasteHandler() {}
}

WebDropHandler getWebDropHandler() => _WebDropHandlerStub();

