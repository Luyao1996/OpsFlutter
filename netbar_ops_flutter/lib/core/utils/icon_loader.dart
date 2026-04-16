import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../network/dio_helper.dart';
import '../storage/token_store.dart';

/// 图标加载器，支持 ICO 格式
class IconLoader {
  static final Dio _dio = createDio();

  /// 检测是否是 ICO 格式
  /// ICO 文件头: 00 00 01 00
  static bool isIcoFormat(Uint8List data) {
    if (data.length < 4) return false;
    return data[0] == 0x00 &&
        data[1] == 0x00 &&
        data[2] == 0x01 &&
        data[3] == 0x00;
  }

  /// 检测是否是 PNG 格式
  /// PNG 文件头: 89 50 4E 47
  static bool isPngFormat(Uint8List data) {
    if (data.length < 4) return false;
    return data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47;
  }

  /// 将 ICO 转换为 PNG
  static Uint8List? icoToPng(Uint8List icoData) {
    try {
      // 使用 image 包解码 ICO
      final decoder = img.IcoDecoder();
      final image = decoder.decode(icoData);
      if (image == null) return null;

      // 编码为 PNG
      final pngBytes = img.encodePng(image);
      return Uint8List.fromList(pngBytes);
    } catch (e) {
      debugPrint('ICO 转 PNG 失败: $e');
      return null;
    }
  }

  /// 加载网络图标，自动处理 ICO 格式
  static Future<Uint8List?> loadIcon(String url) async {
    try {
      final token = TokenStore.getToken();
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        ),
      );

      if (response.data == null) return null;
      final data = Uint8List.fromList(response.data!);

      // 如果是 ICO 格式，转换为 PNG
      if (isIcoFormat(data)) {
        debugPrint('检测到 ICO 格式，转换为 PNG: $url');
        return icoToPng(data);
      }

      return data;
    } catch (e) {
      debugPrint('加载图标失败: $url, 错误: $e');
      return null;
    }
  }
}

/// 支持 ICO 格式的网络图标 Widget
class NetworkIconImage extends StatefulWidget {
  final String url;
  final Map<String, String>? headers;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget? placeholder;

  const NetworkIconImage({
    super.key,
    required this.url,
    this.headers,
    this.fit = BoxFit.contain,
    this.errorBuilder,
    this.placeholder,
  });

  @override
  State<NetworkIconImage> createState() => _NetworkIconImageState();
}

class _NetworkIconImageState extends State<NetworkIconImage> {
  Uint8List? _imageData;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(NetworkIconImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await IconLoader.loadIcon(widget.url);
      if (mounted) {
        setState(() {
          _imageData = data;
          _loading = false;
          if (data == null) {
            _error = Exception('无法加载图片');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    if (_error != null || _imageData == null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error ?? Exception('未知错误'), null);
      }
      return const Icon(Icons.broken_image, color: Colors.grey);
    }

    return Image.memory(
      _imageData!,
      fit: widget.fit,
      gaplessPlayback: true,
    );
  }
}
