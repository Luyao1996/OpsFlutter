import 'package:dio/dio.dart';
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

  /// 向网吧域名发起 GET 请求（带 Token）
  Future<Response> _netbarGet(String domain, String path, {Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();
    return _client.dio.get(
      url,
      queryParameters: queryParameters,
      options: Options(
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      ),
    );
  }

  /// 向网吧域名发起 POST 请求（带 Token）
  Future<Response> _netbarPost(String domain, String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();
    return _client.dio.post(
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
  }

  /// 解包网吧后端响应 {code, msg, data}
  /// 注意：ApiClient 的拦截器可能已经解包过，此方法需要兼容两种情况
  dynamic _unwrapResponse(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      // 如果有 code 字段，说明尚未解包
      if (raw.containsKey('code')) {
        final code = raw['code'];
        if (code == 0 || code == '0' || code == 200) return raw['data'];
        final msg = raw['msg'] ?? raw['message'] ?? '请求失败';
        throw ApiError(code: code, message: msg.toString(), raw: raw);
      }
      // 没有 code 字段，说明已被 ApiClient 拦截器解包，直接返回
      return raw;
    }
    return raw;
  }

  bool _shouldUseMock(Object e) {
    if (e is ApiError) {
      final code = e.code ?? 0;
      if (code == 404 || code == 405 || code == 501) return true;
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') || msg.contains('no route')) return true;
      return false;
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('404') || msg.contains('not found') || msg.contains('no route');
  }

  /// 获取所有终端（座位列表）
  /// domain: 网吧的 subdomainFull
  Future<List<Terminal>> getAll({
    String? domain,
    String? search,
    int? netbarId,
    int? status,
    String? type,
  }) async {
    if (domain == null || domain.isEmpty) {
      return []; // 无域名则无法请求
    }

    try {
      final response = await _netbarGet(domain, '/seatlist');
      final data = _unwrapResponse(response);

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
      if (_shouldUseMock(e)) return [];
      rethrow;
    }
  }

  /// 获取单个终端（通过座位列表查找）
  Future<Terminal> getById(int id, {String? domain}) async {
    final terminals = await getAll(domain: domain);
    return terminals.firstWhere(
      (t) => t.id == id,
      orElse: () => throw ApiError(code: 404, message: '终端不存在'),
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
      if (_shouldUseMock(e)) {
        return Terminal(
          id: id, name: '', code: '', netbarId: 0, ip: '', mac: '', os: '',
          type: 'client', status: 0, cpuUsage: 0, ramUsage: 0, gpuUsage: 0,
          diskUsage: 0, uptime: '0天',
        );
      }
      rethrow;
    }
  }

  /// 获取进程列表
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
      if (_shouldUseMock(e)) return TerminalMockData.processes(seatId.hashCode);
      rethrow;
    }
  }

  /// 展平进程树
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
  Future<void> killProcess(String seatId, int pid, {required String domain, String? processName}) async {
    try {
      await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'processEnd',
          'data': {
            'type': 'ProcessId',
            'ProcessId': pid,
            if (processName != null) 'ProcessName': processName,
          },
        },
      );
    } catch (e) {
      if (_shouldUseMock(e)) return;
      rethrow;
    }
  }

  /// 获取文件列表
  Future<List<TerminalFile>> getFiles(String seatId, String path, {required String domain}) async {
    try {
      final response = await _netbarPost(
        domain,
        '/task',
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'fileList',
          'data': {'path': path},
        },
      );
      final data = _unwrapResponse(response);
      if (data is Map<String, dynamic>) {
        // 后端返回 {filename: {isfile, size, ctime, lwtime}, ...}
        return data.entries.map((e) {
          final info = e.value is Map<String, dynamic> ? e.value as Map<String, dynamic> : <String, dynamic>{};
          return TerminalFile(
            name: e.key,
            path: path.isEmpty ? e.key : '$path\\${e.key}',
            isDirectory: info['isfile'] != true,
            size: info['size'] ?? 0,
            updatedAt: info['lwtime'] ?? '',
          );
        }).toList();
      }
      if (data is List) {
        return data.map((e) => TerminalFile.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.files(seatId.hashCode, path);
      rethrow;
    }
  }

  /// 获取硬件信息
  Future<List<Map<String, dynamic>>> getHardwareInfo(int id) async {
    try {
      return TerminalMockData.hardware(id);
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.hardware(id);
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
