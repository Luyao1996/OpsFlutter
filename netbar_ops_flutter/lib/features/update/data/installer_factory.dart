// 条件导入：Web 用 stub，其它走 dart:io 实现。
export 'installer_stub.dart'
    if (dart.library.io) 'installer_io.dart';
