import 'dart:io';

/// 安装器接口。各平台实现下载后如何安装。
abstract class UpdateInstaller {
  /// 触发安装。Android 拉起系统安装页；Windows 调起 setup.exe 并退出主程序。
  Future<void> install(File file);
}
