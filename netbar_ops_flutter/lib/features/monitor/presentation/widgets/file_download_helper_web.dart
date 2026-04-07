// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// 文件下载辅助类 - Web 平台实现
/// Web 端无法获取保存路径，返回文件名表示已触发下载
Future<String?> downloadFile(List<int> bytes, String filename) async {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  // 延迟撤销 URL，给浏览器建立下载连接的时间
  await Future.delayed(const Duration(milliseconds: 500));
  html.Url.revokeObjectUrl(url);
  return filename;
}
