/// 终端截图占位图（无截图/离线时使用，内嵌 asset，不联网）。
const String kScreenshotPlaceholderAsset = 'assets/images/screenshot_placeholder.png';

/// 终端模型
class Terminal {
  final int id;
  final String seatId; // 座位ID（后端 seatlist 中的 id，可能是字符串）
  final String name;
  // 纯别名（后端 name 字段原值，可为空）。[name] 在别名为空时回退机号，
  // 「编辑名称」必须回显此字段，否则会把机号误当别名提交（对标 EditNameDialog.vue 只回显 alias）
  final String alias;
  final String code;
  final int netbarId;
  final int? areaId;
  final String ip;
  final String mac;
  final String os;
  final String type; // server, client, console, cashier
  final int status; // 0: 离线, 1: 在线
  final String uptime;
  final String? screenshotUrl;
  final String? lastOnline;
  final String? lastHeartbeat;
  final String? createdAt;
  final String? updatedAt;
  final List<dynamic>? remote; // 远程连接用户列表
  final int? mode; // 中央 HTTP 字段：0=client, 1=server。旧 /seatlist 格式留 null
  final String? version; // 终端程序版本号（中央 HTTP 字段：version）。旧格式留 null
  final String? remark; // 终端备注（HTML 字符串，如 "<p>...</p>"）
  final bool lockScreenEnabled; // 2FA 锁屏是否启用（中央 HTTP 字段 lock_screen_enabled）

  Terminal({
    required this.id,
    this.seatId = '',
    required this.name,
    this.alias = '',
    required this.code,
    required this.netbarId,
    this.areaId,
    required this.ip,
    required this.mac,
    required this.os,
    required this.type,
    required this.status,
    required this.uptime,
    this.screenshotUrl,
    this.lastOnline,
    this.lastHeartbeat,
    this.createdAt,
    this.updatedAt,
    this.remote,
    this.mode,
    this.version,
    this.remark,
    this.lockScreenEnabled = false,
  });

  Terminal copyWith({
    int? id,
    String? seatId,
    String? name,
    String? alias,
    String? code,
    int? netbarId,
    int? areaId,
    String? ip,
    String? mac,
    String? os,
    String? type,
    int? status,
    String? uptime,
    String? screenshotUrl,
    String? lastOnline,
    String? lastHeartbeat,
    String? createdAt,
    String? updatedAt,
    List<dynamic>? remote,
    int? mode,
    String? version,
    String? remark,
    bool? lockScreenEnabled,
  }) {
    return Terminal(
      id: id ?? this.id,
      seatId: seatId ?? this.seatId,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      code: code ?? this.code,
      netbarId: netbarId ?? this.netbarId,
      areaId: areaId ?? this.areaId,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      os: os ?? this.os,
      type: type ?? this.type,
      status: status ?? this.status,
      uptime: uptime ?? this.uptime,
      screenshotUrl: screenshotUrl ?? this.screenshotUrl,
      lastOnline: lastOnline ?? this.lastOnline,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      remote: remote ?? this.remote,
      mode: mode ?? this.mode,
      version: version ?? this.version,
      remark: remark ?? this.remark,
      lockScreenEnabled: lockScreenEnabled ?? this.lockScreenEnabled,
    );
  }

  /// 解析后端 seatlist 返回的在线状态
  static int _parseOnlineStatus(dynamic online) {
    if (online == true || online == 1 || online == 'online') return 1;
    return 0;
  }

  factory Terminal.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];

    // 检测响应格式：
    //   - 中央 HTTP /terminals: 顶层有 'seat' / 'is_online' / 'merchant_id'，id 是整型主键
    //   - 旧 frp /seatlist: id 直接是座位号字符串，状态字段叫 'online'
    final bool isCentralFormat = json.containsKey('seat') ||
        json.containsKey('is_online') ||
        json.containsKey('merchant_id');

    final String parsedSeatId;
    final int parsedId;
    if (isCentralFormat) {
      parsedSeatId = json['seat']?.toString() ?? '';
      parsedId = rawId is int
          ? rawId
          : (int.tryParse(rawId?.toString() ?? '') ?? 0);
    } else {
      // 旧格式：id 即座位号
      parsedId = rawId is int
          ? rawId
          : (int.tryParse(rawId?.toString() ?? '') ?? rawId.hashCode.abs());
      parsedSeatId = rawId?.toString() ?? '';
    }

    final rawName = json['name']?.toString() ?? '';

    // 远程中用户列表：兼容 remoting_users（新）/ remote（旧）
    final List<dynamic>? remoteList = json['remoting_users'] is List
        ? List<dynamic>.from(json['remoting_users'] as List)
        : (json['remote'] is List
            ? List<dynamic>.from(json['remote'] as List)
            : null);

    // 状态三态：
    //   离线 → 0
    //   在线 + 有人远程中 → 2 (busy)
    //   在线 + 无人远程   → 1 (online idle)
    final int status;
    if (isCentralFormat) {
      final online = json['is_online'] == true;
      if (!online) {
        status = 0;
      } else {
        status = (remoteList != null && remoteList.isNotEmpty) ? 2 : 1;
      }
    } else if (json.containsKey('online')) {
      // 旧 /seatlist 格式：online 字段。busy 状态在旧协议下也通过 remote 列表推导
      final online = _parseOnlineStatus(json['online']);
      if (online == 0) {
        status = 0;
      } else {
        status = (remoteList != null && remoteList.isNotEmpty) ? 2 : 1;
      }
    } else {
      status = json['status'] ?? 0;
    }

    // 设备类型：中央 HTTP 按 mode 字段判定。
    // mode: 0=终端(client) / 1=主服务器 / 2=副服务器 —— 1、2 均为服务器(关键设备)。
    // 旧 /seatlist 格式无 mode，回退用 json['type']（已无活跃调用方，仅保留兼容）。
    final String type;
    if (isCentralFormat) {
      final mode = json['mode'];
      type = (mode == 1 || mode == 2) ? 'server' : 'client';
    } else {
      type = (json['type']?.toString().isNotEmpty == true)
          ? json['type'].toString()
          : 'client';
    }

    return Terminal(
      id: parsedId,
      seatId: parsedSeatId,
      name: rawName.isNotEmpty ? rawName : parsedSeatId,
      // 后端响应无 alias 字段 → 取 rawName（纯别名）；
      // toJson 快照回灌（子窗口/dock 恢复）时 json['name'] 已是合成显示名，只能信 json['alias']
      alias: json['alias']?.toString() ?? rawName,
      code: json['code'] ?? parsedSeatId,
      // merchant_id（新）/ netbar_id（旧）兼容
      netbarId: (json['merchant_id'] ?? json['netbar_id'] ?? 0) as int,
      areaId: json['area_id'],
      ip: json['ip'] ?? '',
      mac: json['mac'] ?? '',
      os: json['os'] ?? '',
      type: type,
      status: status,
      uptime: json['uptime'] ?? '0天',
      screenshotUrl: json['screenshot_url'] ?? json['screenshotUrl'],
      // 中央 HTTP 用 online_at/offline_at 表达上下线时刻
      lastOnline: json['last_online'] ?? json['online_at'],
      lastHeartbeat: json['last_heartbeat'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      remote: remoteList,
      // 仅中央 HTTP 透传 mode；旧 /seatlist 格式不带此字段，留 null
      mode: isCentralFormat ? (json['mode'] is int ? json['mode'] as int : null) : null,
      // version 中央 HTTP 直接带；旧 /seatlist 格式不带，留 null
      version: json['version']?.toString(),
      // remark：HTML 字符串
      remark: json['remark']?.toString(),
      // 2FA 锁屏：中央 HTTP lock_screen_enabled（兼容 bool / 1）；缺失即关闭
      lockScreenEnabled:
          json['lock_screen_enabled'] == true || json['lock_screen_enabled'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'alias': alias,
        'code': code,
        'netbar_id': netbarId,
        'area_id': areaId,
        'ip': ip,
        'mac': mac,
        'os': os,
        'type': type,
        'status': status,
        'uptime': uptime,
        'screenshot_url': screenshotUrl,
        'last_online': lastOnline,
        'last_heartbeat': lastHeartbeat,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'mode': mode,
        'version': version,
        'remark': remark,
        'lock_screen_enabled': lockScreenEnabled,
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

  /// 是否为关键设备（服务器）
  /// 中央 HTTP：mode 0=终端 / 1=主服务器 / 2=副服务器，mode ∈ {1,2} 即关键设备。
  /// 旧 /seatlist 格式无 mode（null），回退按 type 判定以保持兼容。
  bool get isKeyDevice => mode != null
      ? (mode == 1 || mode == 2)
      : ['server', 'console', 'cashier'].contains(type);

  /// 是否为主服务器
  bool get isMainServer => mode == 1;

  /// 是否为副服务器
  bool get isBackupServer => mode == 2;

  /// 设备类型显示名："主服务器" / "副服务器" / "终端"
  String get deviceTypeLabel {
    if (mode == 1) return '主服务器';
    if (mode == 2) return '副服务器';
    if (mode == 0) return '终端';
    return ['server', 'console', 'cashier'].contains(type) ? '服务器' : '终端';
  }

  /// 是否有可用的真实截图 URL。
  /// false（无截图/离线）时，UI 改用 [kScreenshotPlaceholderAsset] 本地占位图，
  /// 不再请求任何外部公开接口（旧实现会回退到 picsum 随机图，已移除）。
  bool get hasScreenshot => screenshotUrl != null && screenshotUrl!.isNotEmpty;
}

class TerminalProcess {
  final String name;
  final int pid;
  final double cpu;
  final double mem; // MB
  final String user;
  final int threadCount;
  final String path;
  final int memoryKB;
  final List<TerminalProcess> children;

  TerminalProcess({
    required this.name,
    required this.pid,
    required this.cpu,
    required this.mem,
    required this.user,
    this.threadCount = 0,
    this.path = '',
    this.memoryKB = 0,
    List<TerminalProcess>? children,
  }) : children = children ?? [];

  /// 是否有子进程
  bool get hasChildren => children.isNotEmpty;

  factory TerminalProcess.fromJson(Map<String, dynamic> json) {
    return TerminalProcess(
      name: json['name'] ?? '',
      pid: json['pid'] ?? 0,
      cpu: (json['cpu'] ?? 0).toDouble(),
      mem: (json['mem'] ?? 0).toDouble(),
      user: json['user'] ?? '',
      threadCount: json['threadCount'] ?? json['ThreadCount'] ?? 0,
      path: json['path'] ?? '',
      memoryKB: json['memoryKB'] ?? 0,
    );
  }

  /// 从后端进程树数据解析（递归）
  factory TerminalProcess.fromProcessTree(Map<String, dynamic> data, [String? key]) {
    final pid = data['ProcessId'] ?? data['Pid'] ?? data['pid'] ?? 0;
    final name = data['name'] ?? data['ProcessName'] ?? key ?? '';

    // 兼容多种字段名格式
    final memoryUsage = (data['memoryUsage'] ?? data['MemoryUsage'] ?? data['memory_usage'] ?? data['Memory'] ?? 0).toDouble();
    final cpuUsage = (data['cpuUsage'] ?? data['CpuUsage'] ?? data['cpu_usage'] ?? data['CPU'] ?? data['cpu'] ?? 0).toDouble();

    final memoryKB = memoryUsage > 0 ? (memoryUsage / 1024).round() : 0;
    final memoryMB = memoryUsage > 0 ? memoryUsage / (1024 * 1024) : 0.0;

    // 解析子进程
    List<TerminalProcess> children = [];
    final childrenData = data['children'] ?? data['Children'];
    if (childrenData is Map<String, dynamic>) {
      children = childrenData.entries.map((e) {
        final childData = e.value is Map<String, dynamic> ? e.value as Map<String, dynamic> : <String, dynamic>{};
        return TerminalProcess.fromProcessTree(childData, e.key);
      }).toList();
      // 按 PID 排序
      children.sort((a, b) => a.pid.compareTo(b.pid));
    }

    return TerminalProcess(
      name: name,
      pid: pid,
      cpu: cpuUsage,
      mem: memoryMB,
      user: data['user'] ?? data['User'] ?? '',
      threadCount: data['ThreadCount'] ?? data['threadCount'] ?? data['thread_count'] ?? 0,
      path: data['path'] ?? data['Path'] ?? '',
      memoryKB: memoryKB,
      children: children,
    );
  }
}

class TerminalFile {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final String updatedAt;
  final String createdAt;
  final String version;
  final bool isDrive; // 是否为磁盘根目录（如 C:, D:）

  TerminalFile({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.updatedAt,
    this.createdAt = '',
    this.version = '',
    this.isDrive = false,
  });

  factory TerminalFile.fromJson(Map<String, dynamic> json) {
    return TerminalFile(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDirectory: json['is_directory'] ?? json['isDirectory'] ?? false,
      size: json['size'] ?? 0,
      updatedAt: json['updated_at'] ?? json['lwtime'] ?? '',
      createdAt: json['created_at'] ?? json['ctime'] ?? '',
      version: json['version'] ?? '',
      isDrive: json['is_drive'] ?? json['isDrive'] ?? false,
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

