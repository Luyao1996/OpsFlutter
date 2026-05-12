import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 显示当前应用版本号（形如 "v1.0.2"）。
///
/// 数据来源：`package_info_plus`，对应 pubspec.yaml `version` 字段冒号前的部分
/// （即 Android versionName / Windows ProductVersion / iOS CFBundleShortVersionString）。
///
/// 加载完成前显示为空（避免闪烁）。
class AppVersionLabel extends StatefulWidget {
  final TextStyle? style;

  const AppVersionLabel({super.key, this.style});

  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  String? _text;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _text = 'v${info.version}';
      });
    } catch (_) {
      // 读取失败则不显示，不影响主功能
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_text == null) return const SizedBox.shrink();
    return Text(
      _text!,
      style: widget.style ??
          TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w400,
          ),
    );
  }
}
