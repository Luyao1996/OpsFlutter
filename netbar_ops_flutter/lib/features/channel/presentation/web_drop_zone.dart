import 'dart:async';
import 'dart:typed_data';

import 'web_drop_zone_stub.dart'
    if (dart.library.html) 'web_drop_zone_web.dart';

/// 拖拽文件信息
class WebDropFileInfo {
  final String name;
  final String relativePath;
  final Uint8List bytes;
  final bool isDirectory;

  WebDropFileInfo({
    required this.name,
    required this.relativePath,
    required this.bytes,
    required this.isDirectory,
  });
}

/// 拖拽/粘贴回调类型
typedef WebDropCallback = FutureOr<void> Function(List<WebDropFileInfo> files);

/// Web 拖拽处理抽象接口
abstract class WebDropHandler {
  /// 是否支持目录拖拽
  bool get supportsDirectoryDrop;

  /// 注册全局拖拽监听
  void registerDropZone({
    required void Function() onDragEnter,
    required void Function() onDragLeave,
    required WebDropCallback onDrop,
  });

  /// 移除全局拖拽监听
  void unregisterDropZone();

  /// 注册全局粘贴监听
  void registerPasteHandler({
    required WebDropCallback onPaste,
  });

  /// 移除全局粘贴监听
  void unregisterPasteHandler();
}

/// 获取 WebDropHandler 实例
WebDropHandler get webDropHandler => getWebDropHandler();

