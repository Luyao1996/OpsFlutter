import 'platform_helper.dart';

class PlatformHelperWeb implements PlatformHelper {
  @override
  bool get isDesktop => false;

  @override
  bool get isMobile => false;

  @override
  Future<String?> saveBytes(String name, List<int> bytes) async {
    // Web: no-op, return null to indicate not supported
    return null;
  }

  @override
  Future<String?> pickDirectory() async {
    // Web: not supported
    return null;
  }

  @override
  Future<String?> saveBytesToDirectory(String directory, String name, List<int> bytes) async {
    // Web: not supported
    return null;
  }
}

PlatformHelper getPlatformHelper() => PlatformHelperWeb();
