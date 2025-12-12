import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/desktop_model.dart';
import '../../data/desktop_asset_api.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/config/app_config.dart';

class AddIconDialog extends StatefulWidget {
  final DesktopIcon? initialIcon;

  const AddIconDialog({super.key, this.initialIcon});

  @override
  State<AddIconDialog> createState() => _AddIconDialogState();
}

Map<String, String>? _authHeaders() {
  final token = TokenStore.getToken();
  if (token == null) return null;
  return {'Authorization': 'Bearer $token'};
}

String _normalizeUrl(String url) {
  if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('data:')) return url;
  final base = AppConfig.baseUrl.endsWith('/')
      ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
      : AppConfig.baseUrl;
  return '$base$url';
}

class _AddIconDialogState extends State<AddIconDialog> {
  late TextEditingController _nameController;
  late TextEditingController _pathController;
  late TextEditingController _argsController;
  late TextEditingController _workDirController;
  String? _iconPath; // For custom icon URL
  bool _uploading = false;
  final DesktopAssetApi _assetApi = DesktopAssetApi();

  @override
  void initState() {
    super.initState();
    final config = widget.initialIcon?.config;
    _nameController = TextEditingController(text: widget.initialIcon?.name ?? '');
    _pathController = TextEditingController(text: config?.exePath ?? '');
    _argsController = TextEditingController(text: config?.args ?? '');
    _workDirController = TextEditingController(text: config?.workDir ?? '');
    _iconPath = config?.iconPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    _argsController.dispose();
    _workDirController.dispose();
    super.dispose();
  }

  Future<void> _selectIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'ico'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final url = await _assetApi.uploadImageBytes(file.bytes!, file.name);
      setState(() => _iconPath = url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传图标失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialIcon != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? '编辑桌面图标' : '添加桌面图标',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(LucideIcons.x, size: 20, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildTextField('图标名称', _nameController, hint: '例如：英雄联盟'),
                  const SizedBox(height: 16),
                  _buildTextField('执行文件', _pathController, hint: '例如：D:\\Games\\LOL\\LeagueClient.exe'),
                  const SizedBox(height: 16),
                  _buildTextField('执行参数', _argsController, hint: '可选，例如：-windowed'),
                  const SizedBox(height: 16),
                  // Icon Selection Area
                  Container(
                    margin: const EdgeInsets.only(top: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('图标', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Icon Preview
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              padding: const EdgeInsets.all(4),
                              alignment: Alignment.center,
                              child: _iconPath != null
                                  ? Image.network(
                                      _normalizeUrl(_iconPath!),
                                      fit: BoxFit.contain,
                                      headers: _authHeaders(),
                                      errorBuilder: (_, __, ___) => const Icon(LucideIcons.image, size: 20, color: Colors.grey),
                                    )
                                  : const Icon(LucideIcons.file, size: 20, color: Colors.grey),
                            ),
                            const SizedBox(width: 8),
                            // Select Button
                            InkWell(
                              onTap: _uploading ? null : _selectIcon,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: _uploading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(LucideIcons.upload, size: 20, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Hint
                            const Expanded(
                              child: Text(
                                '默认为执行文件图标',
                                style: TextStyle(fontSize: 13, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildTextField('执行目录', _workDirController, hint: '可选，默认为执行文件目录'),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      if (_nameController.text.isEmpty || _pathController.text.isEmpty) {
                        return; // Validate
                      }
                      Navigator.pop(context, DesktopIconConfig(
                        name: _nameController.text,
                        exePath: _pathController.text,
                        args: _argsController.text,
                        workDir: _workDirController.text,
                        iconPath: _iconPath,
                      ));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.iosBlue)),
          ),
        ),
      ],
    );
  }
}
