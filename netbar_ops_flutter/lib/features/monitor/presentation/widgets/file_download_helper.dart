import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 文件下载辅助类 - 非 Web 平台实现
Future<void> downloadFile(List<int> bytes, String filename) async {
  final directory = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$filename');
  await file.writeAsBytes(bytes);
}
