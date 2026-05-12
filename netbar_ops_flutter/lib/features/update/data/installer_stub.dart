import 'dart:io';

import '../../../core/logging/webrtc_crash_logger.dart';
import 'installer.dart';

/// Web / 不支持平台的兜底实现。
class StubInstaller implements UpdateInstaller {
  @override
  Future<void> install(File file) async {
    WebRtcCrashLogger.I.log(
      'WARN',
      'update',
      'install',
      '-',
      'current platform is not supported, file=${file.path}',
    );
  }
}

UpdateInstaller createInstaller() => StubInstaller();
