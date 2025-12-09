import 'web_file_picker.dart';

/// Stub 实现，用于非 Web 平台
class _WebFilePickerStub implements WebFilePicker {
  @override
  bool get supportsDirectory => false;

  @override
  Future<List<WebFileInfo>> pickDirectory() async => [];

  @override
  Future<List<WebFileInfo>> pickFiles() async => [];
}

WebFilePicker getWebFilePicker() => _WebFilePickerStub();

