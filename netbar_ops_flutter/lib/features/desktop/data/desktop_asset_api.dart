import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';

/// 桌面资产上传（壁纸、应用图标）
/// 说明：目前直接落盘到后端 uploads/images，返回的下载 URL 仍然走 API（/resources/{id}/download）。
class DesktopAssetApi {
  final ApiClient _client = ApiClient.instance;

  /// 上传图片并返回可下载 URL（供桌面图标、壁纸使用）
  Future<String> uploadImageBytes(Uint8List bytes, String filename, {String? zone, int? netbarId}) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (zone != null) 'zone': zone,
      if (netbarId != null) 'netbar_id': netbarId,
    });

    final response = await _client.post('/resources/upload-image', data: formData);
    final data = response.data as Map<String, dynamic>;
    final id = data['id'];
    // 仅返回相对下载路径，避免将本地路径或带 token 的全路径存入配置
    return '/resources/$id/download';
  }
}
