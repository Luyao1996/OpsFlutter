import '../../../core/network/api_client.dart';
import 'terminal_mock_data.dart';
import 'terminal_models.dart';

export 'terminal_models.dart';

/// Terminal API 服务
class TerminalApi {
  final ApiClient _client = ApiClient.instance;

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

  /// 获取所有终端
  Future<List<Terminal>> getAll({
    String? search,
    int? netbarId,
    int? status,
    String? type,
  }) async {
    final params = <String, dynamic>{};
    if (search != null) params['search'] = search;
    if (netbarId != null) params['netbar_id'] = netbarId;
    if (status != null) params['status'] = status;
    if (type != null) params['type'] = type;

    final response = await _client.get('/terminals', queryParameters: params);
    final list = response.data as List? ?? [];
    return list.map((e) => Terminal.fromJson(e)).toList();
  }

  /// 获取单个终端
  Future<Terminal> getById(int id) async {
    final response = await _client.get('/terminals/$id');
    return Terminal.fromJson(response.data);
  }

  /// 远程操作
  Future<void> remote(int id, String action) async {
    await _client.post('/terminals/$id/remote', data: {'action': action});
  }

  /// 获取终端心跳/实时状态
  Future<Terminal> getHeartbeat(int id) async {
    final res = await _client.get('/terminals/$id/heartbeat');
    final data = res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : <String, dynamic>{};
    // 将心跳数据合并到 Terminal 结构
    final merged = {
      'id': id,
      ...data,
    };
    return Terminal.fromJson(merged);
  }

  /// 获取进程列表
  Future<List<TerminalProcess>> getProcesses(int id) async {
    try {
      final response = await _client.get('/terminals/$id/processes');
      final list = response.data as List? ?? [];
      return list.map((e) => TerminalProcess.fromJson(e)).toList();
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.processes(id);
      rethrow;
    }
  }

  /// 结束进程
  Future<void> killProcess(int id, int pid) async {
    try {
      await _client.post('/terminals/$id/processes/$pid/kill');
    } catch (e) {
      if (_shouldUseMock(e)) return;
      rethrow;
    }
  }

  /// 获取文件列表
  Future<List<TerminalFile>> getFiles(int id, String path) async {
    try {
      final response = await _client.get(
        '/terminals/$id/files',
        queryParameters: {'path': path},
      );
      final list = response.data as List? ?? [];
      return list.map((e) => TerminalFile.fromJson(e)).toList();
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.files(id, path);
      rethrow;
    }
  }

  /// 获取硬件信息 (返回 Map，结构较灵活)
  Future<List<Map<String, dynamic>>> getHardwareInfo(int id) async {
    try {
      final response = await _client.get('/terminals/$id/hardware');
      final list = response.data as List? ?? [];
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.hardware(id);
      rethrow;
    }
  }

  /// 获取聊天记录
  Future<List<TerminalChatMessage>> getChatMessages(int id) async {
    final response = await _client.get('/terminals/$id/chat');
    final list = response.data as List? ?? [];
    return list.map((e) => TerminalChatMessage.fromJson(e)).toList();
  }

  /// 发送聊天消息
  Future<void> sendChatMessage(int id, String content) async {
    await _client.post('/terminals/$id/chat', data: {'content': content});
  }

  /// 获取终端日志
  Future<List<TerminalLog>> getLogs(int id) async {
    try {
      final response = await _client.get('/terminals/$id/logs');
      final list = response.data as List? ?? [];
      return list.map((e) => TerminalLog.fromJson(e)).toList();
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.logs(id);
      rethrow;
    }
  }

  /// 执行终端命令
  Future<String> executeCommand(int id, String command) async {
    try {
      final response =
          await _client.post('/terminals/$id/command', data: {'command': command});
      return response.data['output'] ?? '';
    } catch (e) {
      if (_shouldUseMock(e)) return TerminalMockData.commandOutput(id, command);
      rethrow;
    }
  }

  /// 远程唤醒 (WOL)
  Future<void> wakeOnLan(List<int> terminalIds) async {
    await _client.post('/terminals/wake', data: {'ids': terminalIds});
  }
}
