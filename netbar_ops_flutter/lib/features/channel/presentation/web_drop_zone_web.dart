import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'web_drop_zone.dart';

/// 文件系统入口 JS 互操作
@JS('FileSystemFileEntry')
extension type JSFileSystemFileEntry._(JSObject _) implements JSObject {
  external void file(JSFunction callback);
}

@JS('FileSystemDirectoryEntry')
extension type JSFileSystemDirectoryEntry._(JSObject _) implements JSObject {
  external JSFileSystemDirectoryReader createReader();
  external String get name;
}

@JS('FileSystemDirectoryReader')
extension type JSFileSystemDirectoryReader._(JSObject _) implements JSObject {
  external void readEntries(JSFunction callback);
}

@JS('DataTransferItem')
extension type JSDataTransferItem._(JSObject _) implements JSObject {
  external JSObject? webkitGetAsEntry();
  external web.File? getAsFile();
  external String get kind;
}

extension on JSObject {
  external bool get isFile;
  external bool get isDirectory;
  external String get name;
}

/// Web 平台拖拽/粘贴处理实现
class _WebDropHandlerWeb implements WebDropHandler {
  JSFunction? _dragEnterHandler;
  JSFunction? _dragOverHandler;
  JSFunction? _dragLeaveHandler;
  JSFunction? _dropHandler;
  JSFunction? _pasteHandler;

  @override
  bool get supportsDirectoryDrop => true;

  @override
  void registerDropZone({
    required void Function() onDragEnter,
    required void Function() onDragLeave,
    required WebDropCallback onDrop,
  }) {
    final body = web.document.body;
    if (body == null) return;

    _dragEnterHandler = ((web.DragEvent e) {
      e.preventDefault();
      if (_hasFiles(e)) onDragEnter();
    }).toJS;

    _dragOverHandler = ((web.DragEvent e) {
      e.preventDefault();
    }).toJS;

    _dragLeaveHandler = ((web.DragEvent e) {
      final rect = body.getBoundingClientRect();
      if (e.clientX < rect.left ||
          e.clientX > rect.right ||
          e.clientY < rect.top ||
          e.clientY > rect.bottom) {
        onDragLeave();
      }
    }).toJS;

    _dropHandler = ((web.DragEvent e) {
      e.preventDefault();
      onDragLeave();
      unawaited(_handleDrop(e).then((files) {
        if (files.isNotEmpty) onDrop(files);
      }));
    }).toJS;

    body.addEventListener('dragenter', _dragEnterHandler);
    body.addEventListener('dragover', _dragOverHandler);
    body.addEventListener('dragleave', _dragLeaveHandler);
    body.addEventListener('drop', _dropHandler);
  }

  @override
  void unregisterDropZone() {
    final body = web.document.body;
    if (body == null) return;
    if (_dragEnterHandler != null) body.removeEventListener('dragenter', _dragEnterHandler);
    if (_dragOverHandler != null) body.removeEventListener('dragover', _dragOverHandler);
    if (_dragLeaveHandler != null) body.removeEventListener('dragleave', _dragLeaveHandler);
    if (_dropHandler != null) body.removeEventListener('drop', _dropHandler);
  }

  @override
  void registerPasteHandler({required WebDropCallback onPaste}) {
    _pasteHandler = ((web.ClipboardEvent e) {
      unawaited(_handlePaste(e).then((files) {
        if (files.isNotEmpty) onPaste(files);
      }));
    }).toJS;
    web.document.addEventListener('paste', _pasteHandler);
  }

  @override
  void unregisterPasteHandler() {
    if (_pasteHandler != null) {
      web.document.removeEventListener('paste', _pasteHandler);
    }
  }

  bool _hasFiles(web.DragEvent e) {
    final types = e.dataTransfer?.types;
    if (types == null) return false;
    for (var i = 0; i < types.length; i++) {
      if (types[i].toDart == 'Files') return true;
    }
    return false;
  }

  Future<List<WebDropFileInfo>> _handleDrop(web.DragEvent e) async {
    final items = e.dataTransfer?.items;
    if (items == null || items.length == 0) return [];
    final List<WebDropFileInfo> results = [];
    for (var i = 0; i < items.length; i++) {
      final item = JSDataTransferItem._(items[i] as JSObject);
      if (item.kind != 'file') continue;
      final entry = item.webkitGetAsEntry();
      if (entry == null) continue;
      if (entry.isFile) {
        final file = item.getAsFile();
        if (file != null) {
          final bytes = await _readFile(file);
          results.add(WebDropFileInfo(name: file.name, relativePath: file.name, bytes: bytes, isDirectory: false));
        }
      } else if (entry.isDirectory) {
        final subFiles = await _readDirectory(JSFileSystemDirectoryEntry._(entry), entry.name);
        results.addAll(subFiles);
      }
    }
    return results;
  }

  Future<List<WebDropFileInfo>> _readDirectory(JSFileSystemDirectoryEntry dirEntry, String path) async {
    final List<WebDropFileInfo> results = [];
    final reader = dirEntry.createReader();
    final entries = await _readEntries(reader);
    for (final entry in entries) {
      if (entry.isFile) {
        final file = await _getFileFromEntry(JSFileSystemFileEntry._(entry));
        if (file != null) {
          final bytes = await _readFile(file);
          results.add(WebDropFileInfo(name: file.name, relativePath: '$path/${file.name}', bytes: bytes, isDirectory: false));
        }
      } else if (entry.isDirectory) {
        final subFiles = await _readDirectory(JSFileSystemDirectoryEntry._(entry), '$path/${entry.name}');
        results.addAll(subFiles);
      }
    }
    return results;
  }

  Future<List<JSObject>> _readEntries(JSFileSystemDirectoryReader reader) async {
    final completer = Completer<List<JSObject>>();
    reader.readEntries(((JSArray<JSObject> entries) {
      completer.complete(entries.toDart);
    }).toJS);
    return completer.future;
  }

  Future<web.File?> _getFileFromEntry(JSFileSystemFileEntry entry) async {
    final completer = Completer<web.File?>();
    entry.file(((web.File file) {
      completer.complete(file);
    }).toJS);
    return completer.future;
  }

  Future<Uint8List> _readFile(web.File file) async {
    final completer = Completer<Uint8List>();
    final reader = web.FileReader();
    reader.onload = ((web.Event e) {
      final result = reader.result;
      if (result != null && result.isA<JSArrayBuffer>()) {
        final arrayBuffer = result as JSArrayBuffer;
        completer.complete(arrayBuffer.toDart.asUint8List());
      } else {
        completer.complete(Uint8List(0));
      }
    }).toJS;
    reader.onerror = ((web.Event e) {
      completer.complete(Uint8List(0));
    }).toJS;
    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  Future<List<WebDropFileInfo>> _handlePaste(web.ClipboardEvent e) async {
    final items = e.clipboardData?.items;
    if (items == null || items.length == 0) return [];
    final List<WebDropFileInfo> results = [];
    for (var i = 0; i < items.length; i++) {
      final item = JSDataTransferItem._(items[i] as JSObject);
      if (item.kind != 'file') continue;
      // 尝试使用 webkitGetAsEntry 支持目录（浏览器限制通常不支持粘贴目录）
      final entry = item.webkitGetAsEntry();
      if (entry != null) {
        if (entry.isFile) {
          final file = item.getAsFile();
          if (file != null) {
            final bytes = await _readFile(file);
            results.add(WebDropFileInfo(name: file.name, relativePath: file.name, bytes: bytes, isDirectory: false));
          }
        } else if (entry.isDirectory) {
          final subFiles = await _readDirectory(JSFileSystemDirectoryEntry._(entry), entry.name);
          results.addAll(subFiles);
        }
      } else {
        // 回退到普通文件
        final file = item.getAsFile();
        if (file != null) {
          final bytes = await _readFile(file);
          results.add(WebDropFileInfo(name: file.name, relativePath: file.name, bytes: bytes, isDirectory: false));
        }
      }
    }
    return results;
  }
}

WebDropHandler getWebDropHandler() => _WebDropHandlerWeb();
