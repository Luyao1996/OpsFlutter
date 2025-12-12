import '../../../core/network/api_client.dart';

/// 终端模型
class Terminal {
  final int id;
  final String name;
  final String code;
  final int netbarId;
  final int? areaId;
  final String ip;
  final String mac;
  final String os;
  final String type; // server, client, console, cashier
  final int status; // 0: 离线, 1: 在线空闲, 2: 使用中
  final double cpuUsage;
  final double ramUsage;
  final double gpuUsage;
  final double diskUsage;
  final String uptime;
  final String? lastOnline;
  final String? lastHeartbeat;
  final String? createdAt;
  final String? updatedAt;

  Terminal({
    required this.id,
    required this.name,
    required this.code,
    required this.netbarId,
    this.areaId,
    required this.ip,
    required this.mac,
    required this.os,
    required this.type,
    required this.status,
    required this.cpuUsage,
    required this.ramUsage,
    required this.gpuUsage,
    required this.diskUsage,
    required this.uptime,
    this.lastOnline,
    this.lastHeartbeat,
    this.createdAt,
    this.updatedAt,
  });

  factory Terminal.fromJson(Map<String, dynamic> json) {
    return Terminal(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      netbarId: json['netbar_id'] ?? 0,
      areaId: json['area_id'],
      ip: json['ip'] ?? '',
      mac: json['mac'] ?? '',
      os: json['os'] ?? '',
      type: json['type'] ?? 'client',
      status: json['status'] ?? 0,
      cpuUsage: (json['cpu_usage'] ?? 0).toDouble(),
      ramUsage: (json['ram_usage'] ?? 0).toDouble(),
      gpuUsage: (json['gpu_usage'] ?? 0).toDouble(),
      diskUsage: (json['disk_usage'] ?? 0).toDouble(),
      uptime: json['uptime'] ?? '0天',
      lastOnline: json['last_online'],
      lastHeartbeat: json['last_heartbeat'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  /// 获取状态字符串
  String get statusString {
    switch (status) {
      case 0:
        return 'offline';
      case 2:
        return 'busy';
      default:
        return 'online';
    }
  }

  /// 是否为关键设备
  bool get isKeyDevice => ['server', 'console', 'cashier'].contains(type);
}

class TerminalProcess {
  final String name;
  final int pid;
  final double cpu;
  final double mem; // MB
  final String user;

  TerminalProcess({
    required this.name,
    required this.pid,
    required this.cpu,
    required this.mem,
    required this.user,
  });

  factory TerminalProcess.fromJson(Map<String, dynamic> json) {
    return TerminalProcess(
      name: json['name'] ?? '',
      pid: json['pid'] ?? 0,
      cpu: (json['cpu'] ?? 0).toDouble(),
      mem: (json['mem'] ?? 0).toDouble(),
      user: json['user'] ?? '',
    );
  }
}

class TerminalFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final String updatedAt;

  TerminalFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.updatedAt,
  });

  factory TerminalFile.fromJson(Map<String, dynamic> json) {
    return TerminalFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDirectory: json['is_directory'] ?? false,
      size: json['size'] ?? 0,
      updatedAt: json['updated_at'] ?? '',
    );
  }
}

class TerminalChatMessage {
  final String content;
  final String sender; // 'admin' or 'user'
  final String time;

  TerminalChatMessage({
    required this.content,
    required this.sender,
    required this.time,
  });

  factory TerminalChatMessage.fromJson(Map<String, dynamic> json) {
    return TerminalChatMessage(
      content: json['content'] ?? '',
      sender: json['sender'] ?? 'user',
      time: json['time'] ?? '',
    );
  }
}

class TerminalLog {
  final String level;
  final String time;
  final String source;
  final int eventId;
  final String category;
  final String message;

  TerminalLog({
    required this.level,
    required this.time,
    required this.source,
    required this.eventId,
    required this.category,
    required this.message,
  });

  factory TerminalLog.fromJson(Map<String, dynamic> json) {
    return TerminalLog(
      level: json['level'] ?? 'Info',
      time: json['time'] ?? '',
      source: json['source'] ?? '',
      eventId: json['event_id'] ?? 0,
      category: json['category'] ?? 'None',
      message: json['message'] ?? '',
    );
  }
}

/// Terminal API 服务
class TerminalApi {
  final ApiClient _client = ApiClient.instance;

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
    final response = await _client.get('/terminals/$id/processes');
    final list = response.data as List? ?? [];
    return list.map((e) => TerminalProcess.fromJson(e)).toList();
  }

  /// 结束进程
  Future<void> killProcess(int id, int pid) async {
    await _client.post('/terminals/$id/processes/$pid/kill');
  }

  /// 获取文件列表
  Future<List<TerminalFile>> getFiles(int id, String path) async {
    final response = await _client.get('/terminals/$id/files', queryParameters: {'path': path});
    final list = response.data as List? ?? [];
    return list.map((e) => TerminalFile.fromJson(e)).toList();
  }

  /// 获取硬件信息 (返回 Map，结构较灵活)
  Future<List<Map<String, dynamic>>> getHardwareInfo(int id) async {
    final response = await _client.get('/terminals/$id/hardware');
    final list = response.data as List? ?? [];
    return list.map((e) => e as Map<String, dynamic>).toList();
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
    final response = await _client.get('/terminals/$id/logs');
    final list = response.data as List? ?? [];
    return list.map((e) => TerminalLog.fromJson(e)).toList();
  }

  /// 执行终端命令
  Future<String> executeCommand(int id, String command) async {
    final response = await _client.post('/terminals/$id/command', data: {'command': command});
    return response.data['output'] ?? '';
  }

  /// 远程唤醒 (WOL)
  Future<void> wakeOnLan(List<int> terminalIds) async {
    await _client.post('/terminals/wake', data: {'ids': terminalIds});
  }
}
