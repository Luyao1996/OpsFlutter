import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// 文件下载辅助类 - 非 Web 平台实现
/// 返回实际保存路径，用户取消时返回 null
Future<String?> downloadFile(List<int> bytes, String filename) async {
  final uint8Bytes = Uint8List.fromList(bytes);

  // 弹出"另存为"对话框
  // Android 必须传 bytes（由 FilePicker 内部写入），Desktop 返回路径后自行写入
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: '保存文件',
    fileName: filename,
    bytes: Platform.isAndroid || Platform.isIOS ? uint8Bytes : null,
  );

  if (savePath == null) return null; // 用户取消

  // Desktop 端需要自行写入文件（Android/iOS 已由 FilePicker 写入）
  if (!Platform.isAndroid && !Platform.isIOS) {
    final file = File(savePath);
    await file.writeAsBytes(uint8Bytes);
  }

  return savePath;
}
