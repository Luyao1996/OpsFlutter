/// 终端模型
class Terminal {
  final int id;
  final String seatId; // 座位ID（后端 seatlist 中的 id，可能是字符串）
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
  final String? screenshotUrl;
  final String? lastOnline;
  final String? lastHeartbeat;
  final String? createdAt;
  final String? updatedAt;
  final List<dynamic>? remote; // 远程连接用户列表

  Terminal({
    required this.id,
    this.seatId = '',
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
    this.screenshotUrl,
    this.lastOnline,
    this.lastHeartbeat,
    this.createdAt,
    this.updatedAt,
    this.remote,
  });

  /// 解析后端 seatlist 返回的在线状态
  static int _parseOnlineStatus(dynamic online) {
    if (online == true || online == 1 || online == 'online') return 1;
    return 0;
  }

  factory Terminal.fromJson(Map<String, dynamic> json) {
    // 兼容 seatlist 格式：{id: "PC001", name: "1号机", online: true, ip, mac, remote}
    final rawId = json['id'];
    final isSeatFormat = rawId is String || json.containsKey('online');

    final int parsedId = rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? rawId.hashCode.abs());
    final String parsedSeatId = rawId?.toString() ?? '';

    final rawName = json['name']?.toString() ?? '';

    return Terminal(
      id: parsedId,
      seatId: parsedSeatId,
      name: rawName.isNotEmpty ? rawName : parsedSeatId,
      code: json['code'] ?? parsedSeatId,
      netbarId: json['netbar_id'] ?? 0,
      areaId: json['area_id'],
      ip: json['ip'] ?? '',
      mac: json['mac'] ?? '',
      os: json['os'] ?? '',
      type: json['type'] ?? 'client',
      status: isSeatFormat ? _parseOnlineStatus(json['online']) : (json['status'] ?? 0),
      cpuUsage: (json['cpu_usage'] ?? json['cpuUsage'] ?? 0).toDouble(),
      ramUsage: (json['ram_usage'] ?? json['ramUsage'] ?? 0).toDouble(),
      gpuUsage: (json['gpu_usage'] ?? json['gpuUsage'] ?? 0).toDouble(),
      diskUsage: (json['disk_usage'] ?? json['diskUsage'] ?? 0).toDouble(),
      uptime: json['uptime'] ?? '0天',
      screenshotUrl: json['screenshot_url'] ?? json['screenshotUrl'],
      lastOnline: json['last_online'],
      lastHeartbeat: json['last_heartbeat'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      remote: json['remote'] is List ? json['remote'] : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'netbar_id': netbarId,
        'area_id': areaId,
        'ip': ip,
        'mac': mac,
        'os': os,
        'type': type,
        'status': status,
        'cpu_usage': cpuUsage,
        'ram_usage': ramUsage,
        'gpu_usage': gpuUsage,
        'disk_usage': diskUsage,
        'uptime': uptime,
        'screenshot_url': screenshotUrl,
        'last_online': lastOnline,
        'last_heartbeat': lastHeartbeat,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

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

  /// 桌面预览/缩略图 URL（有真实截图则优先使用）
  String desktopPreviewUrl({int width = 400, int height = 225}) {
    final url = screenshotUrl;
    if (url != null && url.isNotEmpty) return url;
    return 'https://picsum.photos/seed/$id/$width/$height';
  }

  String get desktopThumbnailUrl => desktopPreviewUrl();
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

