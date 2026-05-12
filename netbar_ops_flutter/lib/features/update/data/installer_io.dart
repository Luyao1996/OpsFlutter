import 'dart:io';

import 'package:open_filex/open_filex.dart';

import '../../../core/logging/webrtc_crash_logger.dart';
import 'installer.dart';

/// Android：通过系统"打开方式"拉起包安装器。
/// open_filex 内部自带 FileProvider（authority = ${applicationId}.fileProvider），
/// 无需额外配置。
class AndroidInstaller implements UpdateInstaller {
  @override
  Future<void> install(File file) async {
    WebRtcCrashLogger.I.log(
      'INFO',
      'update',
      'install.android',
      '-',
      'open path=${file.path}',
    );
    final result = await OpenFilex.open(file.path);
    WebRtcCrashLogger.I.log(
      result.type == ResultType.done ? 'INFO' : 'ERROR',
      'update',
      'install.android',
      '-',
      'result=${result.type} message=${result.message}',
    );
    if (result.type != ResultType.done) {
      throw Exception('调起安装失败: ${result.message}');
    }
  }
}

/// Windows：启动 setup.exe（静默升级模式），主程序立即退出。
class WindowsInstaller implements UpdateInstaller {
  @override
  Future<void> install(File file) async {
    WebRtcCrashLogger.I.log(
      'INFO',
      'update',
      'install.windows',
      '-',
      'path=${file.path}',
    );
    await Process.start(
      file.path,
      const [
        '/SILENT',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
        '/NORESTART',
      ],
      mode: ProcessStartMode.detached,
    );
    // 给系统一点时间起进程
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}

/// 其他桌面 / 移动平台暂未实现。
class UnsupportedInstaller implements UpdateInstaller {
  @override
  Future<void> install(File file) async {
    WebRtcCrashLogger.I.log(
      'WARN',
      'update',
      'install',
      '-',
      'platform=${Platform.operatingSystem} not supported, file=${file.path}',
    );
  }
}

UpdateInstaller createInstaller() {
  if (Platform.isAndroid) return AndroidInstaller();
  if (Platform.isWindows) return WindowsInstaller();
  return UnsupportedInstaller();
}
