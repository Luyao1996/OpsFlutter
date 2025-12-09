import 'upload_helper.dart';

class _PlatformFileHelperStub implements PlatformFileHelper {
  @override
  Future<List<UploadFileItem>> pickDirectory() async {
    return [];
  }

  @override
  Future<List<UploadFileItem>> readDirectoryFromPath(String path) async {
    return [];
  }

  @override
  bool isDirectory(String path) {
    return false;
  }

  @override
  Future<List<String>> getClipboardFilePaths() async {
    return [];
  }

  @override
  Future<List<UploadFileItem>> readFilesFromPaths(List<String> paths) async {
    return [];
  }
}

PlatformFileHelper getPlatformFileHelper() => _PlatformFileHelperStub();

