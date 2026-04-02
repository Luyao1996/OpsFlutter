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
  /// domain 示例: "xxx.frps.wwls.net"
  /// path 示例: "/seatlist"
  /// 结果: "https://xxx.frps.wwls.net/api/seatlist"
  String _buildUrl(String domain, String path) {
    String d = domain.trim();
    if (!d.startsWith('http://') && !d.startsWith('https://')) {
      d = 'https://$d';
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
    final sw = Stopwatch()..start();

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Host': domain.trim(),
            if (token != null) 'Authorization': 'Bearer $token',
          },
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      sw.stop();

      debugPrint('[TerminalApi._netbarGet] ========== 请求成功 ==========');
      debugPrint('[TerminalApi._netbarGet] 状态码: ${response.statusCode}');
      debugPrint('[TerminalApi._netbarGet] 耗时: ${sw.elapsedMilliseconds}ms');
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

    final headers = {
      'Content-Type': 'application/json',
      'Host': domain.trim(),
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // 拼接完整 URL（含 query 参数）
    final fullUri = Uri.parse(url).replace(queryParameters: queryParameters?.map((k, v) => MapEntry(k, v.toString())));
    debugPrint('[TerminalApi._netbarPost] ========== POST 请求 ==========');
    debugPrint('[TerminalApi._netbarPost] URL: $fullUri');
    debugPrint('[TerminalApi._netbarPost] Headers: $headers');
    debugPrint('[TerminalApi._netbarPost] Body: $data');

    final sw = Stopwatch()..start();
    try {
      final response = await dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      sw.stop();
      debugPrint('[TerminalApi._netbarPost] 响应状态码: ${response.statusCode}');
      debugPrint('[TerminalApi._netbarPost] 耗时: ${sw.elapsedMilliseconds}ms');
      // 分段打印避免 logcat 截断（每段800字符）
      final resStr = response.data.toString();
      for (var i = 0; i < resStr.length; i += 800) {
        final end = (i + 800 < resStr.length) ? i + 800 : resStr.length;
        debugPrint('[TerminalApi._netbarPost] 响应[${i ~/ 800}]: ${resStr.substring(i, end)}');
      }
      return response;
    } on DioException catch (e) {
      debugPrint('[TerminalApi._netbarPost] ========== 请求失败 ==========');
      debugPrint('[TerminalApi._netbarPost] 错误类型: ${e.type}');
      debugPrint('[TerminalApi._netbarPost] 状态码: ${e.response?.statusCode}');
      debugPrint('[TerminalApi._netbarPost] 响应数据: ${e.response?.data}');
      debugPrint('[TerminalApi._netbarPost] 错误消息: ${e.message}');
      rethrow;
    } finally {
      dio.close();
    }
  }

  /// 解包网吧后端响应 {code, msg, data}
  /// 注意：ApiClient 的拦截器可能已经解包过，此方法需要兼容两种情况
  dynamic _unwrapResponse(Response response) {
    final raw = response.data;
    debugPrint('[TerminalApi] _unwrapResponse raw type: ${raw.runtimeType}');
    // 分段打印避免 logcat 截断
    final rawStr = raw.toString();
    for (var i = 0; i < rawStr.length; i += 800) {
      final end = (i + 800 < rawStr.length) ? i + 800 : rawStr.length;
      debugPrint('[TerminalApi] _unwrapResponse[${i ~/ 800}]: ${rawStr.substring(i, end)}');
    }
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

      if (list.isNotEmpty) {
        debugPrint('[TerminalApi.getAll] 第一条原始数据字段: ${list.first.keys.toList()}');
        debugPrint('[TerminalApi.getAll] 第一条原始数据: ${list.first}');
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

  /// 获取硬件信息（静态 + 实时合并）
  Future<List<Map<String, dynamic>>> getHardwareInfo(String seatId, {required String domain}) async {
    debugPrint('[TerminalApi.getHardwareInfo] ========== 开始 ==========');
    debugPrint('[TerminalApi.getHardwareInfo] seatId=$seatId, domain=$domain');
    if (domain.isEmpty) {
      debugPrint('[TerminalApi.getHardwareInfo] domain 为空，无法请求');
      return [];
    }
    if (seatId.isEmpty) {
      debugPrint('[TerminalApi.getHardwareInfo] seatId 为空，无法请求');
      return [];
    }
    try {
      final url = _buildUrl(domain, '/task');
      debugPrint('[TerminalApi.getHardwareInfo] 请求静态信息 URL: $url');
      final infoResponse = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {'fun': 'hwinfo', 'data': {'type': 'info'}},
      );
      debugPrint('[TerminalApi.getHardwareInfo] 静态信息响应状态码: ${infoResponse.statusCode}');
      final infoData = _unwrapResponse(infoResponse);
      debugPrint('[TerminalApi.getHardwareInfo] 静态信息解包类型: ${infoData.runtimeType}');

      // 尝试获取实时数据（可选，失败不影响静态信息展示）
      Map<String, dynamic> realtimeData = {};
      try {
        debugPrint('[TerminalApi.getHardwareInfo] 请求实时信息...');
        final rtResponse = await _netbarPost(
          domain,
          '/task',
          queryParameters: {'seat': seatId},
          data: {'fun': 'hwinfo', 'data': {'type': 'realtime'}},
        );
        debugPrint('[TerminalApi.getHardwareInfo] 实时信息响应状态码: ${rtResponse.statusCode}');
        final rtRaw = _unwrapResponse(rtResponse);
        if (rtRaw is Map<String, dynamic>) realtimeData = rtRaw;
      } catch (e) {
        debugPrint('[TerminalApi.getHardwareInfo] 实时信息获取失败(可忽略): $e');
      }

      if (infoData is Map<String, dynamic>) {
        final result = _transformHardwareInfo(infoData, realtimeData);
        debugPrint('[TerminalApi.getHardwareInfo] 转换完成，共 ${result.length} 个硬件分类');
        return result;
      }
      debugPrint('[TerminalApi.getHardwareInfo] infoData 不是 Map，返回空');
      return [];
    } catch (e, stack) {
      debugPrint('[TerminalApi.getHardwareInfo] ========== 失败 ==========');
      debugPrint('[TerminalApi.getHardwareInfo] 错误: $e');
      debugPrint('[TerminalApi.getHardwareInfo] Stack: $stack');
      if (_shouldReturnEmpty(e)) {
        debugPrint('[TerminalApi.getHardwareInfo] 错误被判定为可忽略，返回空列表');
        return [];
      }
      rethrow;
    }
  }

  /// 获取硬件实时信息（供网络监控等周期调用）
  Future<Map<String, dynamic>> getHardwareRealtime(String seatId, {required String domain}) async {
    if (domain.isEmpty || seatId.isEmpty) return {};
    try {
      final response = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {'fun': 'hwinfo', 'data': {'type': 'realtime'}},
      );
      final data = _unwrapResponse(response);
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (e) {
      debugPrint('[TerminalApi.getHardwareRealtime] 错误: $e');
      if (_shouldReturnEmpty(e)) return {};
      rethrow;
    }
  }

  /// 电源控制（关机/重启/注销/锁定）
  Future<void> controlPc(String seatId, String type, {required String domain}) async {
    try {
      await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {'fun': 'controlPc', 'data': {'type': type}},
      );
    } catch (e) {
      if (_shouldReturnEmpty(e)) return;
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

  // ===== 硬件信息格式化辅助 =====

  /// 将 hwinfo API 响应转换为 UI 展示格式 [{name, details: [{label, value}]}]
  List<Map<String, dynamic>> _transformHardwareInfo(
      Map<String, dynamic> info, Map<String, dynamic> realtime) {
    final result = <Map<String, dynamic>>[];

    // --- CPU ---
    final cpuInfoList = info['cpu'] as List? ?? [];
    final cpuRtList = realtime['cpu'] as List? ?? [];
    for (var i = 0; i < cpuInfoList.length; i++) {
      final cpu = cpuInfoList[i];
      if (cpu is! Map<String, dynamic>) continue;
      final rt = _findById(cpuRtList, cpu['id']);
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': cpu['name'] ?? ''},
        {'label': '厂商', 'value': cpu['vendor'] ?? ''},
        {'label': '核心/线程', 'value': '${cpu['core_count'] ?? 0}核/${cpu['thread_count'] ?? 0}线程'},
        {'label': '基础频率', 'value': _formatFreq(cpu['base_freq'])},
        {'label': '缓存', 'value': 'L1:${_formatBytes(cpu['l1_cache'])} L2:${_formatBytes(cpu['l2_cache'])} L3:${_formatBytes(cpu['l3_cache'])}'},
      ];
      if (rt != null) {
        details.add({'label': '当前负载', 'value': '${rt['load_total'] ?? 0}%'});
        if ((rt['clock_core'] ?? 0) > 0) {
          details.add({'label': '实时频率', 'value': _formatFreq(rt['clock_core'])});
        }
        if ((rt['power'] ?? 0) > 0) {
          details.add({'label': '功耗', 'value': '${(rt['power'] as num).toStringAsFixed(1)}W'});
        }
      }
      result.add({'name': '处理器 (CPU)', 'details': details});
    }

    // --- GPU ---
    final gpuInfoList = info['gpu'] as List? ?? [];
    final gpuRtList = realtime['gpu'] as List? ?? [];
    for (var i = 0; i < gpuInfoList.length; i++) {
      final gpu = gpuInfoList[i];
      if (gpu is! Map<String, dynamic>) continue;
      final rt = _findById(gpuRtList, gpu['id']);
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': gpu['name'] ?? ''},
        {'label': '厂商', 'value': gpu['vendor'] ?? ''},
        {'label': '显存', 'value': _formatBytes(gpu['memory_total'])},
      ];
      if (rt != null) {
        details.add({'label': '温度', 'value': '核心${rt['temperature'] ?? 0}°C / 显存${rt['temperature_memory'] ?? 0}°C / 热点${rt['temperature_hotspot'] ?? 0}°C'});
        details.add({'label': 'GPU负载', 'value': '${rt['load_gpu'] ?? 0}%'});
        details.add({'label': '显存负载', 'value': '${rt['load_memory'] ?? 0}%'});
        if ((rt['clock_core'] ?? 0) > 0 || (rt['clock_memory'] ?? 0) > 0) {
          details.add({'label': '频率', 'value': '核心${_formatFreq(rt['clock_core'])} / 显存${_formatFreq(rt['clock_memory'])}'});
        }
        if ((rt['power'] ?? 0) > 0) {
          details.add({'label': '功耗', 'value': '${(rt['power'] as num).toStringAsFixed(1)}W'});
        }
      }
      result.add({'name': '显卡 (GPU)', 'details': details});
    }

    // --- 内存 (聚合所有插槽) ---
    final memInfoList = info['memory'] as List? ?? [];
    final memRt = realtime['memory'];
    if (memInfoList.isNotEmpty) {
      int totalSize = 0;
      for (final mem in memInfoList) {
        if (mem is Map<String, dynamic>) {
          totalSize += (mem['size'] as num? ?? 0).toInt();
        }
      }
      final first = memInfoList[0] as Map<String, dynamic>;
      final details = <Map<String, dynamic>>[
        {'label': '总容量', 'value': '${_formatBytes(totalSize)} (${memInfoList.length}条)'},
        {'label': '频率', 'value': '${first['speed'] ?? 0} MHz'},
        {'label': '类型', 'value': '${first['type'] ?? ''} ${first['form_factor'] ?? ''}'},
        {'label': '厂商', 'value': first['manufacturer'] ?? ''},
        {'label': '电压', 'value': '${(first['voltage'] ?? 0).toStringAsFixed(1)}V'},
        {'label': '数据位宽', 'value': '${first['data_width'] ?? 0}bit'},
      ];
      if (memRt is Map<String, dynamic>) {
        details.add({'label': '当前占用', 'value': '${memRt['load_total'] ?? 0}%'});
      }
      result.add({'name': '内存 (RAM)', 'details': details});
    }

    // --- 存储 (每块硬盘一张卡) ---
    final storageInfoList = info['storage'] as List? ?? [];
    final storageRtList = realtime['storage'] as List? ?? [];
    for (var i = 0; i < storageInfoList.length; i++) {
      final disk = storageInfoList[i];
      if (disk is! Map<String, dynamic>) continue;
      final rt = _findById(storageRtList, disk['id']);
      final rotation = (disk['rotation'] ?? 0) as num;
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': (disk['model'] ?? '').toString().trim()},
        {'label': '容量', 'value': _formatBytes(disk['size'])},
        {'label': '类型/接口', 'value': '${disk['type'] ?? ''} ${disk['interface'] ?? ''}${rotation > 0 ? ' ${rotation}RPM' : ''}'},
        {'label': '序列号', 'value': (disk['serial'] ?? '').toString().trim()},
        {'label': '固件', 'value': disk['firmware'] ?? ''},
      ];
      if (rt != null) {
        final used = (rt['used_space'] as num? ?? 0).toDouble();
        final free = (rt['free_space'] as num? ?? 0).toDouble();
        final total = used + free;
        final pct = total > 0 ? (used / total * 100).toStringAsFixed(1) : '0';
        details.add({'label': '已用空间', 'value': '${_formatBytes(used)} / ${_formatBytes(total)} ($pct%)'});
        details.add({'label': '健康度', 'value': '${rt['health'] ?? 0}%'});
      }
      final idx = i + 1;
      result.add({'name': '存储 (磁盘$idx)', 'details': details});
    }

    // --- 网络 ---
    final netInfoList = info['network'] as List? ?? [];
    final netRtList = realtime['network'] as List? ?? [];
    for (var i = 0; i < netInfoList.length; i++) {
      final net = netInfoList[i];
      if (net is! Map<String, dynamic>) continue;
      final rt = _findById(netRtList, net['id']);
      final details = <Map<String, dynamic>>[
        {'label': '网卡', 'value': net['description'] ?? net['name'] ?? ''},
        {'label': 'IP', 'value': net['ip_address'] ?? ''},
        {'label': '网关', 'value': net['gateway'] ?? ''},
        {'label': '子网掩码', 'value': net['subnet_mask'] ?? ''},
        {'label': 'MAC', 'value': net['mac'] ?? ''},
        {'label': '速率', 'value': _formatNetSpeed(net['speed'])},
        {'label': 'DNS', 'value': net['dns'] ?? ''},
      ];
      if (rt != null) {
        details.add({'label': '上传速度', 'value': _formatBytesSpeed(rt['upload_speed'])});
        details.add({'label': '下载速度', 'value': _formatBytesSpeed(rt['download_speed'])});
      }
      result.add({'name': '网络 (Network)', 'details': details});
    }

    // --- 主板 ---
    final mbInfoList = info['motherboard'] as List? ?? [];
    for (final mb in mbInfoList) {
      if (mb is! Map<String, dynamic>) continue;
      result.add({
        'name': '主板 (Motherboard)',
        'details': [
          {'label': '厂商', 'value': mb['manufacturer'] ?? ''},
          {'label': '型号', 'value': mb['product'] ?? ''},
          {'label': '版本', 'value': mb['version'] ?? ''},
          {'label': 'BIOS', 'value': '${mb['bios_vendor'] ?? ''} ${mb['bios_version'] ?? ''}'},
          {'label': 'BIOS日期', 'value': mb['bios_date'] ?? ''},
        ],
      });
    }

    return result;
  }

  /// 根据 id 从 realtime 列表中查找对应项
  Map<String, dynamic>? _findById(List? list, dynamic id) {
    if (list == null || id == null) return null;
    for (final item in list) {
      if (item is Map<String, dynamic> && item['id'] == id) return item;
    }
    return null;
  }

  /// 格式化字节数
  String _formatBytes(dynamic bytes) {
    final b = (bytes is num) ? bytes.toDouble() : 0.0;
    if (b <= 0) return '0';
    if (b >= 1024 * 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
    if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toInt()} B';
  }

  /// 格式化频率（Hz → GHz/MHz）
  String _formatFreq(dynamic freq) {
    final f = (freq is num) ? freq.toDouble() : 0.0;
    if (f <= 0) return '0';
    if (f >= 1000000000) return '${(f / 1000000000).toStringAsFixed(2)} GHz';
    if (f >= 1000000) return '${(f / 1000000).toStringAsFixed(0)} MHz';
    if (f >= 1000) return '${(f / 1000).toStringAsFixed(0)} KHz';
    return '${f.toInt()} Hz';
  }

  /// 格式化网卡速率（bps → Gbps/Mbps）
  String _formatNetSpeed(dynamic speed) {
    final s = (speed is num) ? speed.toDouble() : 0.0;
    if (s <= 0) return '0';
    if (s >= 1000000000) return '${(s / 1000000000).toStringAsFixed(0)} Gbps';
    if (s >= 1000000) return '${(s / 1000000).toStringAsFixed(0)} Mbps';
    if (s >= 1000) return '${(s / 1000).toStringAsFixed(0)} Kbps';
    return '${s.toInt()} bps';
  }

  /// 格式化字节速率（bytes/s → MB/s, KB/s）
  String _formatBytesSpeed(dynamic bytesPerSec) {
    final b = (bytesPerSec is num) ? bytesPerSec.toDouble() : 0.0;
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${b.toInt()} B/s';
  }
}
