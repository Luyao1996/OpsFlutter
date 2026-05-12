// DNS 解析辅助函数 - 跨平台兼容
// 使用条件导入处理 web 和非 web 平台

export 'terminal_api_dns_helper_stub.dart'
    if (dart.library.io) 'terminal_api_dns_helper_io.dart';
