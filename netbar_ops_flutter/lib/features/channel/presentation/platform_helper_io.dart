import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_helper.dart';

class PlatformHelperIo implements PlatformHelper {
  @override
  bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Future<String?> saveBytes(String name, List<int> bytes) async {
    final downloadsDir = await getDownloadsDirectory();
    final targetDir = downloadsDir ?? await getApplicationDocumentsDirectory();
    final path = p.join(targetDir.path, name);
    final outFile = File(path);
    await outFile.writeAsBytes(bytes, flush: true);
    return outFile.path;
  }

  @override
  Future<String?> pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    return result;
  }

  @override
  Future<String?> saveBytesToDirectory(String directory, String name, List<int> bytes) async {
    final path = p.join(directory, name);
    final outFile = File(path);
    await outFile.writeAsBytes(bytes, flush: true);
    return outFile.path;
  }
}

PlatformHelper getPlatformHelper() => PlatformHelperIo();
