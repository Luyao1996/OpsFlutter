import 'platform_helper_io.dart' if (dart.library.html) 'platform_helper_web.dart';

abstract class PlatformHelper {
  bool get isDesktop;
  bool get isMobile;
  Future<String?> saveBytes(String name, List<int> bytes);

  /// 选择保存目录
  Future<String?> pickDirectory();

  /// 保存文件到指定目录
  Future<String?> saveBytesToDirectory(String directory, String name, List<int> bytes);
}

PlatformHelper get platformHelper => getPlatformHelper();
