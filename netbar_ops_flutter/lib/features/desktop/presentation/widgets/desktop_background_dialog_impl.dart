import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/desktop_asset_api.dart';
import '../../data/desktop_model.dart';

class DesktopBackgroundDialog extends StatefulWidget {
  final BackgroundConfig initialConfig;

  const DesktopBackgroundDialog({super.key, required this.initialConfig});

  @override
  State<DesktopBackgroundDialog> createState() => _DesktopBackgroundDialogState();
}

class _DesktopBackgroundDialogState extends State<DesktopBackgroundDialog> {
  late TextEditingController _urlController;
  late TextEditingController _delayController;
  late String _mode;
  late bool _locked;
  bool _uploading = false;
  final DesktopAssetApi _assetApi = DesktopAssetApi();

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialConfig.url);
    _delayController =
        TextEditingController(text: widget.initialConfig.delay.toString());
    _mode = widget.initialConfig.mode;
    _locked = widget.initialConfig.locked;
  }

  void _handleSubmit() {
    final url = _urlController.text.trim();
    Navigator.pop(
      context,
      BackgroundConfig(
        url: url,
        mode: _mode,
        delay: int.tryParse(_delayController.text) ?? 10,
        locked: _locked,
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final url = await _assetApi.uploadImageBytes(file.bytes!, file.name);
      setState(() => _urlController.text = url);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '上传壁纸失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '桌面背景设置',
      maxWidth: 600,
      bodyPadding: const EdgeInsets.all(24),
      body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '壁纸链接',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: '输入图片URL或从右侧选择上传',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.iosBlue),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _uploading ? null : _pickImage,
                        icon: _uploading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(LucideIcons.upload, size: 16),
                        label: Text(_uploading ? '上传中' : '上传'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.iosBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildSelect(
                          label: '模式',
                          value: _mode,
                          items: const {
                            'center': '居中',
                            'stretch': '拉伸',
                            'tile': '平铺',
                          },
                          onChanged: (v) => setState(() => _mode = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextInput(
                          label: '轮播间隔(秒)',
                          controller: _delayController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Checkbox(
                        value: _locked,
                        onChanged: (v) => setState(() => _locked = v ?? false),
                        activeColor: AppColors.iosBlue,
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text('锁定图标'),
                    ],
                  ),
                ],
              ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消', style: TextStyle(color: Colors.grey.shade700)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSelect({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              onChanged: (v) => onChanged(v!),
              items: items.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextInput({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.iosBlue),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}

