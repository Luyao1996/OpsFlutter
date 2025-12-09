import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'web_file_picker.dart';

/// 扩展 HTMLInputElement 添加 webkitdirectory 属性
extension on web.HTMLInputElement {
  external set webkitdirectory(bool value);
  external bool get webkitdirectory;
}

/// Web 平台实际实现
class _WebFilePickerWeb implements WebFilePicker {
  @override
  bool get supportsDirectory => true;

  @override
  Future<List<WebFileInfo>> pickDirectory() async {
    final completer = Completer<List<WebFileInfo>>();
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.webkitdirectory = true;
    input.multiple = true;

    input.onchange = ((web.Event event) {
      unawaited(_processDirectoryFiles(input, completer));
    }).toJS;

    input.click();
    return completer.future;
  }

  Future<void> _processDirectoryFiles(web.HTMLInputElement input, Completer<List<WebFileInfo>> completer) async {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete([]);
      return;
    }

    final List<WebFileInfo> results = [];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;

      // webkitRelativePath 包含相对路径（如 "folder/subfolder/file.txt"）
      final relativePath = file.webkitRelativePath;
      final bytes = await _readFileBytes(file);

      results.add(WebFileInfo(
        name: file.name,
        relativePath: relativePath.isNotEmpty ? relativePath : file.name,
        bytes: bytes,
        isDirectory: false,
      ));
    }
    completer.complete(results);
  }

  @override
  Future<List<WebFileInfo>> pickFiles() async {
    final completer = Completer<List<WebFileInfo>>();
    final input = web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    input.multiple = true;

    input.onchange = ((web.Event event) {
      unawaited(_processFiles(input, completer));
    }).toJS;

    input.click();
    return completer.future;
  }

  Future<void> _processFiles(web.HTMLInputElement input, Completer<List<WebFileInfo>> completer) async {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete([]);
      return;
    }

    final List<WebFileInfo> results = [];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null) continue;

      final bytes = await _readFileBytes(file);
      results.add(WebFileInfo(
        name: file.name,
        relativePath: file.name,
        bytes: bytes,
        isDirectory: false,
      ));
    }
    completer.complete(results);
  }

  Future<Uint8List> _readFileBytes(web.File file) async {
    final completer = Completer<Uint8List>();
    final reader = web.FileReader();

    reader.onload = ((web.Event event) {
      final result = reader.result;
      if (result != null && result.isA<JSArrayBuffer>()) {
        final arrayBuffer = result as JSArrayBuffer;
        completer.complete(arrayBuffer.toDart.asUint8List());
      } else {
        completer.complete(Uint8List(0));
      }
    }).toJS;

    reader.onerror = ((web.Event event) {
      completer.complete(Uint8List(0));
    }).toJS;

    reader.readAsArrayBuffer(file);
    return completer.future;
  }
}

WebFilePicker getWebFilePicker() => _WebFilePickerWeb();

