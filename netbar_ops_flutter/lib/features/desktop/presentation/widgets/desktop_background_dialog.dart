import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/desktop_model.dart';
import '../../data/desktop_asset_api.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

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
    _delayController = TextEditingController(text: widget.initialConfig.delay.toString());
    _mode = widget.initialConfig.mode;
    _locked = widget.initialConfig.locked;
  }

  Future<void> _handleSubmit() async {
    String url = _urlController.text.trim();
    // 如果用户输入/选择的是本地文件，尝试上传后再保存
    final isDrivePath = RegExp(r'^[A-Za-z]:[\\\\/]').hasMatch(url);
    if (!kIsWeb && (url.startsWith('/') || url.contains('\\') || isDrivePath)) {
      final file = File(url);
      if (await file.exists()) {
        setState(() => _uploading = true);
        try {
          final bytes = await file.readAsBytes();
          url = await _assetApi.uploadImageBytes(bytes, file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'background.png');
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('上传本地壁纸失败: $e'), backgroundColor: Colors.red),
            );
          }
          setState(() => _uploading = false);
          return;
        }
        if (mounted) setState(() => _uploading = false);
      }
    }

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
      setState(() {
        _urlController.text = url;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传壁纸失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 600, // Wider to fit more elements
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
                  const Text(
                    '桌面背景设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Upload Area
                  Expanded(
                    child: Column(
                      children: [
                        InkWell(
                          onTap: _uploading ? null : _pickImage,
                          borderRadius: BorderRadius.circular(8),
                          child: CustomPaint(
                            painter: _DashedRectPainter(color: Colors.grey.shade300, strokeWidth: 1.5, gap: 5.0),
                            child: Container(
                              height: 120,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_uploading)
                                    const SizedBox(
                                      width: 28,
                                      height: 28,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else ...[
                                    Icon(LucideIcons.upload, size: 32, color: Colors.grey.shade400),
                                    const SizedBox(height: 8),
                                    Text('点击图片上传', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right: Settings
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // URL
                        const Text('背景图片 URL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _urlController,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '输入图片链接...',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.iosBlue)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Delay
                        const Text('延迟设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _delayController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '10',
                            suffixText: '秒',
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.iosBlue)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Mode
                        const Text('平铺方式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _mode,
                          onChanged: (v) => setState(() => _mode = v!),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: Colors.grey.shade300)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppColors.iosBlue)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'stretch', child: Text('拉伸填充')),
                            DropdownMenuItem(value: 'center', child: Text('居中')),
                            DropdownMenuItem(value: 'tile', child: Text('平铺')),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Lock Checkbox
                        Row(
                          children: [
                            Checkbox(
                              value: _locked,
                              onChanged: (v) => setState(() => _locked = v ?? false),
                              activeColor: AppColors.iosBlue,
                            ),
                            const Text('强制锁定桌面', style: TextStyle(fontSize: 14, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
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
                    onPressed: _uploading ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('确认'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  _DashedRectPainter({this.color = Colors.grey, this.strokeWidth = 1.0, this.gap = 5.0});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final double width = size.width;
    final double height = size.height;
    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height),
      const Radius.circular(8),
    );
    
    // Simple implementation for rounded rect dashed border
    // Since Path drawing for dashed RRect is complex manually, we will approximate or use a simple path metric approach if needed.
    // For simplicity/performance in this UI mock, let's just draw the RRect solid if dashed is too complex, 
    // OR implementing a path dash.
    
    final Path path = Path()..addRRect(rrect);
    // Draw dashed path
    // Since flutter doesn't have built-in dash path in Paint, we manually draw segments.
    // However, for this UI, a solid light border or simple corners might suffice if this fails.
    // Let's implement a basic dash.
    
    Path dashPath = Path();
    double dashWidth = 5.0;
    double dashSpace = gap;
    double distance = 0.0;
    for (PathMetric pathMetric in path.computeMetrics()) {
      while (distance < pathMetric.length) {
        dashPath.addPath(
          pathMetric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }
    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
