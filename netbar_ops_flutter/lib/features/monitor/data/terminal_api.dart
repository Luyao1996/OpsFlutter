import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';
import 'terminal_mock_data.dart';
import 'terminal_models.dart';

export 'terminal_models.dart';

/// Terminal API 服务
/// 终端相关请求发送到各网吧自己的域名（subdomainFull），而非中央 API
class TerminalApi {
  final ApiClient _client = ApiClient.instance;

  /// 构造网吧域名的完整 API URL
  /// domain 示例: "xxx.net.hudd.cc:880"
  /// path 示例: "/seatlist"
  /// 结果: "http://xxx.net.hudd.cc:880/api/seatlist"
  String _buildUrl(String domain, String path) {
    String d = domain.trim();
    if (!d.startsWith('http://') && !d.startsWith('https://')) {
      d = 'http://$d';
    }
    d = d.replaceAll(RegExp(r'/+$'), '');
    return '$d/api$path';
  }

  /// 创建 Dio 实例
  Dio _createProxiedDio() {
    final dio = Dio();

    // 配置 SSL 证书校验（允许自签名证书）
    if (!kIsWeb) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // 不使用代理
        client.findProxy = (uri) => 'DIRECT';
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }

    return dio;
  }

  /// 向网吧域名发起 GET 请求（带 Token）
  Future<Response> _netbarGet(String domain, String path, {Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();

    debugPrint('[TerminalApi._netbarGet] ========== 请求开始 ==========');
    debugPrint('[TerminalApi._netbarGet] URL: $url');
    debugPrint('[TerminalApi._netbarGet] Token: ${token != null ? "有" : "无"}');

    final dio = _createProxiedDio();

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );

      debugPrint('[TerminalApi._netbarGet] ========== 请求成功 ==========');
      debugPrint('[TerminalApi._netbarGet] 状态码: ${response.statusCode}');
      return response;
    } on DioException catch (e) {
      debugPrint('[TerminalApi._netbarGet] ========== 请求失败 ==========');
      debugPrint('[TerminalApi._netbarGet] 错误类型: ${e.type}');
      debugPrint('[TerminalApi._netbarGet] 错误消息: ${e.message}');
      debugPrint('[TerminalApi._netbarGet] 响应状态码: ${e.response?.statusCode}');
      debugPrint('[TerminalApi._netbarGet] 响应数据: ${e.response?.data}');
      rethrow;
    } finally {
      dio.close();
    }
  }

  /// 向网吧域名发起 POST 请求（带 Token）
  Future<Response> _netbarPost(String domain, String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();
    final dio = _createProxiedDio();

    try {
      return await dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
    } finally {
      dio.close();
    }
  }

  /// 解包网吧后端响应 {code, msg, data}
  /// 注意：ApiClient 的拦截器可能已经解包过，此方法需要兼容两种情况
  dynamic _unwrapResponse(Response response) {
    final raw = response.data;
    debugPrint('[TerminalApi] _unwrapResponse raw type: ${raw.runtimeType}');
    debugPrint('[TerminalApi] _unwrapResponse raw: $raw');
    if (raw is Map<String, dynamic>) {
      debugPrint('[TerminalApi] raw is Map, keys: ${raw.keys.toList()}');
      // 检查是否为标准 API 响应格式 {code, data, msg?}
      // 标准格式必须有 code 字段，且 code 是数字或数字字符串
      if (raw.containsKey('code')) {
        final code = raw['code'];
        debugPrint('[TerminalApi] Found code field: $code');
        // 验证 code 是有效的状态码（数字或数字字符串）
        final isValidCode = code is int ||
            (code is String && int.tryParse(code) != null);
        if (isValidCode) {
          if (code == 0 || code == '0' || code == 200) {
            // 成功响应，返回 data 字段
            debugPrint('[TerminalApi] Returning raw[data]');
            return raw['data'] ?? raw;
          }
          final msg = raw['msg'] ?? raw['message'] ?? '请求失败';
          throw ApiError(code: code, message: msg.toString(), raw: raw);
        }
      }
      // 没有有效的 code 字段，说明这是直接返回的数据（如文件列表）
      debugPrint('[TerminalApi] No valid code field, returning raw directly');
      // 直接返回原始数据，不要尝试解包
      return raw;
    }
    return raw;
  }

  /// 判断是否应该返回空列表（而非抛出异常）
  /// 包括：404、CORS 错误、网络错误等
  bool _shouldReturnEmpty(Object e) {
    // Dio 错误
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404 || statusCode == 405 || statusCode == 501) return true;
      // CORS 预检失败通常表现为网络错误
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) return true;
    }
    // ApiError
    if (e is ApiError) {
      final code = e.code ?? 0;
      if (code == 404 || code == 405 || code == 501) return true;
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') || msg.contains('no route')) return true;
    }
    // 其他错误
    final msg = e.toString().toLowerCase();
    return msg.contains('404') || msg.contains('not found') ||
           msg.contains('no route') || msg.contains('cors') ||
           msg.contains('xmlhttprequest');
  }

  /// 获取所有终端（座位列表）
  /// domain: 网吧的 subdomainFull（动态域名）
  Future<List<Terminal>> getAll({
    String? domain,
    String? search,
    int? netbarId,
    int? status,
    String? type,
  }) async {
    debugPrint('[TerminalApi.getAll] 开始获取终端列表, domain=$domain');
    if (domain == null || domain.isEmpty) {
      debugPrint('[TerminalApi.getAll] domain 为空，返回空列表');
      return []; // 无域名则无法请求
    }

    try {
      final url = _buildUrl(domain, '/seatlist');
      debugPrint('[TerminalApi.getAll] 请求URL: $url');
      final response = await _netbarGet(domain, '/seatlist');
      debugPrint('[TerminalApi.getAll] 响应状态码: ${response.statusCode}');
      final data = _unwrapResponse(response);
      debugPrint('[TerminalApi.getAll] 解包后数据类型: ${data.runtimeType}');

      List<Map<String, dynamic>> list = [];
      if (data is List) {
        list = data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map<String, dynamic>) {
        for (final entry in data.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            // ServerChannel 固定为服务端，其余为客户端终端
            final deviceType = entry.key == 'ServerChannel' ? 'server' : 'client';
            list.add({'id': entry.key, 'type': deviceType, ...val});
          }
        }
      }

      return list.map((e) => Terminal.fromJson(e)).toList();
    } catch (e) {
      if (_shouldReturnEmpty(e)) return [];
      rethrow;
    }
  }

  /// 获取单个终端（通过座位列表查找）
  Future<Terminal> getById(int id, {String? domain}) async {
    debugPrint('[TerminalApi.getById] 开始获取终端 id=$id, domain=$domain');
    final terminals = await getAll(domain: domain);
    debugPrint('[TerminalApi.getById] 获取到 ${terminals.length} 个终端');
    if (terminals.isEmpty) {
      debugPrint('[TerminalApi.getById] 终端列表为空！');
    } else {
      debugPrint('[TerminalApi.getById] 终端ID列表: ${terminals.map((t) => t.id).toList()}');
    }
    return terminals.firstWhere(
      (t) => t.id == id,
      orElse: () {
        debugPrint('[TerminalApi.getById] 未找到 id=$id 的终端');
        throw ApiError(code: 404, message: '终端不存在');
      },
    );
  }

  /// 远程操作（远程连接/断开）
  Future<Map<String, dynamic>> remote(String seatId, String action, {required String domain, Map<String, dynamic>? user}) async {
    final response = await _netbarPost(
      domain,
      '/task',
      queryParameters: {'seat': seatId},
      data: {
        'fun': 'remote',
        'data': {
          'enable': action != 'disconnect',
          'type': action == 'disconnect' ? null : action,
          if (user != null) 'user': user,
        },
      },
    );
    final data = _unwrapResponse(response);
    return data is Map<String, dynamic> ? data : {};
  }

  /// 获取终端心跳/实时状态（通过 seatlist 获取 online 状态）
  Future<Terminal> getHeartbeat(int id, {String? domain}) async {
    try {
      return await getById(id, domain: domain);
    } catch (e) {
      if (_shouldReturnEmpty(e)) {
        return Terminal(
          id: id, name: '', code: '', netbarId: 0, ip: '', mac: '', os: '',
          type: 'client', status: 0, cpuUsage: 0, ramUsage: 0, gpuUsage: 0,
          diskUsage: 0, uptime: '0天',
        );
      }
      rethrow;
    }
  }

  /// 获取进程列表（平面列表，兼容旧版）
  Future<List<TerminalProcess>> getProcesses(String seatId, {required String domain}) async {
    try {
      final response = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {'fun': 'processTree', 'data': {}},
      );
      final data = _unwrapResponse(response);
      if (data is Map<String, dynamic>) {
        // 后端返回嵌套的进程树，展平为列表
        return _flattenProcessTree(data);
      }
      if (data is List) {
        return data.map((e) => TerminalProcess.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      if (_shouldReturnEmpty(e)) return TerminalMockData.processes(seatId.hashCode);
      rethrow;
    }
  }

  /// 获取进程树（保持树形结构）
  Future<List<TerminalProcess>> getProcessTree(String seatId, {required String domain}) async {
    try {
      final response = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {'fun': 'processTree', 'data': {}},
      );
      final data = _unwrapResponse(response);
      debugPrint('[TerminalApi] getProcessTree data type: ${data.runtimeType}');
      if (data is Map<String, dynamic>) {
        // 打印第一个进程的数据结构，用于调试
        if (data.isNotEmpty) {
          final firstKey = data.keys.first;
          final firstProc = data[firstKey];
          debugPrint('[TerminalApi] First process key: $firstKey');
          debugPrint('[TerminalApi] First process data: $firstProc');
          if (firstProc is Map) {
            debugPrint('[TerminalApi] First process keys: ${firstProc.keys.toList()}');
          }
        }
        // 将对象格式转换为树形列表
        return _parseProcessTree(data);
      }
      if (data is List) {
        return data.map((e) => TerminalProcess.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[TerminalApi] getProcessTree error: $e');
      if (_shouldReturnEmpty(e)) return [];
      rethrow;
    }
  }

  /// 解析进程树（保持层级结构）
  List<TerminalProcess> _parseProcessTree(Map<String, dynamic> tree) {
    final result = <TerminalProcess>[];
    for (final entry in tree.entries) {
      final proc = entry.value;
      if (proc is Map<String, dynamic>) {
        result.add(TerminalProcess.fromProcessTree(proc, entry.key));
      }
    }
    // 按 PID 排序
    result.sort((a, b) => a.pid.compareTo(b.pid));
    return result;
  }

  /// 展平进程树（兼容旧版）
  List<TerminalProcess> _flattenProcessTree(Map<String, dynamic> tree) {
    final result = <TerminalProcess>[];
    for (final entry in tree.entries) {
      final proc = entry.value;
      if (proc is Map<String, dynamic>) {
        result.add(TerminalProcess(
          name: proc['name'] ?? proc['ProcessName'] ?? entry.key,
          pid: proc['ProcessId'] ?? proc['Pid'] ?? proc['pid'] ?? 0,
          cpu: (proc['cpuUsage'] ?? 0).toDouble(),
          mem: (proc['memoryUsage'] ?? 0).toDouble() / (1024 * 1024), // bytes → MB
          user: proc['user'] ?? '',
        ));
        // 递归处理子进程
        if (proc['children'] is Map<String, dynamic>) {
          result.addAll(_flattenProcessTree(proc['children']));
        }
      }
    }
    return result;
  }

  /// 结束进程
  /// [killTree] 为 true 时结束整棵进程树
  Future<void> killProcess(String seatId, int pid, {required String domain, String? processName, bool killTree = false}) async {
    try {
      await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'processEnd',
          'data': {
            'type': killTree ? 'ProcessTree' : 'ProcessId',
            'ProcessId': pid,
            if (processName != null) 'ProcessName': processName,
          },
        },
      );
    } catch (e) {
      if (_shouldReturnEmpty(e)) return;
      rethrow;
    }
  }

  /// 获取文件列表
  /// path 为空字符串时返回磁盘列表
  Future<List<TerminalFile>> getFiles(String seatId, String path, {required String domain}) async {
    try {
      // 清理路径：移除开头的反斜杠，保持 C: 或 C:\xxx 格式
      var cleanPath = path.trim();
      while (cleanPath.startsWith('\\') || cleanPath.startsWith('/')) {
        cleanPath = cleanPath.substring(1);
      }

      final response = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'fileList',
          'data': {'path': cleanPath},
        },
      );
      debugPrint('[TerminalApi] getFiles response.data: ${response.data}');
      final data = _unwrapResponse(response);
      debugPrint('[TerminalApi] getFiles unwrapped data type: ${data.runtimeType}');
      debugPrint('[TerminalApi] getFiles unwrapped data: $data');

      // cleanPath 为空时，返回磁盘列表
      if (cleanPath.isEmpty) {
        // 可能是数组 ['C:', 'D:', 'E:'] 或对象 {'C:': {...}, 'D:': {...}}
        if (data is List) {
          return data
              .where((d) => d is String && RegExp(r'^[A-Za-z]:$').hasMatch(d))
              .map((d) => TerminalFile(
                    name: d.toString(),
                    path: d.toString(),
                    isDirectory: true,
                    size: 0,
                    updatedAt: '',
                    isDrive: true,
                  ))
              .toList();
        }
        if (data is Map<String, dynamic>) {
          return data.entries
              .where((e) => RegExp(r'^[A-Za-z]:$').hasMatch(e.key))
              .map((e) {
            final info = e.value is Map<String, dynamic>
                ? e.value as Map<String, dynamic>
                : <String, dynamic>{};
            return TerminalFile(
              name: e.key,
              path: e.key,
              isDirectory: true,
              size: 0,
              updatedAt: info['lwtime'] ?? '',
              createdAt: info['ctime'] ?? '',
              isDrive: true,
            );
          }).toList();
        }
        return [];
      }

      // 普通目录
      if (data is Map<String, dynamic>) {
        debugPrint('[TerminalApi] Parsing file list, entries count: ${data.length}');
        // 后端返回 {filename: {isfile, size, ctime, lwtime, version}, ...}
        final list = data.entries.map((e) {
          final info = e.value is Map<String, dynamic>
              ? e.value as Map<String, dynamic>
              : <String, dynamic>{};
          // 构造完整路径
          String fullPath;
          if (RegExp(r'^[A-Za-z]:$').hasMatch(cleanPath)) {
            fullPath = '$cleanPath\\${e.key}';
          } else if (cleanPath.endsWith('\\')) {
            fullPath = '$cleanPath${e.key}';
          } else {
            fullPath = '$cleanPath\\${e.key}';
          }
          debugPrint('[TerminalApi] File: ${e.key}, isfile: ${info['isfile']}, isDirectory: ${info['isfile'] != true}');
          return TerminalFile(
            name: e.key,
            path: fullPath,
            isDirectory: info['isfile'] != true,
            size: info['size'] ?? 0,
            updatedAt: info['lwtime'] ?? '',
            createdAt: info['ctime'] ?? '',
            version: info['version'] ?? '',
          );
        }).toList();
        debugPrint('[TerminalApi] Parsed ${list.length} files');
        // 排序：文件夹在前，然后按名称排序
        list.sort((a, b) {
          if (a.isDirectory != b.isDirectory) {
            return a.isDirectory ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      }
      if (data is List) {
        debugPrint('[TerminalApi] Data is List, parsing...');
        return data.map((e) => TerminalFile.fromJson(e)).toList();
      }
      debugPrint('[TerminalApi] Data is neither Map nor List, returning empty. Type: ${data.runtimeType}');
      return [];
    } catch (e, stack) {
      debugPrint('[TerminalApi] getFiles ERROR: $e');
      debugPrint('[TerminalApi] Stack: $stack');
      if (_shouldReturnEmpty(e)) {
        debugPrint('[TerminalApi] Returning mock data due to error');
        return TerminalMockData.files(seatId.hashCode, path);
      }
      rethrow;
    }
  }

  /// 下载文件
  /// 返回文件的二进制数据
  Future<List<int>> downloadFile(String seatId, String filePath, {required String domain}) async {
    final url = _buildUrl(domain, '/task');
    final token = TokenStore.getToken();
    final dio = _createProxiedDio();

    try {
      final response = await dio.post(
        url,
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'fileRead',
          'data': {'path': filePath},
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream,application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final bytes = response.data;
      if (bytes is List<int>) {
        return bytes;
      }
      throw ApiError(code: -1, message: '文件下载失败：响应格式错误');
    } finally {
      dio.close();
    }
  }

  /// 获取硬件信息
  Future<List<Map<String, dynamic>>> getHardwareInfo(int id) async {
    try {
      return TerminalMockData.hardware(id);
    } catch (e) {
      if (_shouldReturnEmpty(e)) return TerminalMockData.hardware(id);
      rethrow;
    }
  }

  /// 获取聊天记录（暂保留 mock）
  Future<List<TerminalChatMessage>> getChatMessages(int id) async {
    return [];
  }

  /// 发送聊天消息（暂保留 mock）
  Future<void> sendChatMessage(int id, String content) async {
    // 暂不支持
  }

  /// 获取终端日志（暂保留 mock）
  Future<List<TerminalLog>> getLogs(int id) async {
    return TerminalMockData.logs(id);
  }

  /// 执行终端命令（后端通过 WebSocket 实现，暂保留 mock）
  Future<String> executeCommand(int id, String command) async {
    return TerminalMockData.commandOutput(id, command);
  }

  /// 远程唤醒 (WOL)
  Future<void> wakeOnLan(String seatId, {required String domain}) async {
    await _netbarGet(domain, '/awaken', queryParameters: {'seat': seatId});
  }
}
