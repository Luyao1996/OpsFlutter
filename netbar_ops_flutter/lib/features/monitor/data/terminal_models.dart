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
  final String? screenshotUrl;
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
    this.screenshotUrl,
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
      screenshotUrl: json['screenshot_url'] ?? json['screenshotUrl'],
      lastOnline: json['last_online'],
      lastHeartbeat: json['last_heartbeat'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
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

