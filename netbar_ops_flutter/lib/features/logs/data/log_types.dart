import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

enum LogLevel { info, warning, error, success }
enum LogModule { auth, netbar, channel, desktop, system, startup, remote, command, client }

class LogUser {
  final int id;
  final String name;
  final String? avatar;
  final String role;

  const LogUser({required this.id, required this.name, this.avatar, required this.role});

  factory LogUser.fromJson(Map<String, dynamic> json) {
    return LogUser(
      id: json['id'] ?? 0,
      name: json['nickname'] ?? json['name'] ?? '未知用户',
      avatar: json['avatar'],
      role: '用户',
    );
  }
}

class LogEntry {
  final String id;
  final String timestamp;
  final LogUser user;
  final String ip;
  final LogModule module;
  final String action; // 后端: event
  final String description;
  final LogLevel level;
  final Map<String, dynamic>? details; // 后端: payload

  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.user,
    required this.ip,
    required this.module,
    required this.action,
    required this.description,
    required this.level,
    this.details,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at']?.toString() ?? '';
    final event = (json['event'] ?? '').toString();
    final moduleAndLevel = _parseEvent(event);

    return LogEntry(
      id: json['id']?.toString() ?? '',
      timestamp: _formatTime(createdAt),
      user: json['user'] != null
          ? LogUser.fromJson(json['user'] as Map<String, dynamic>)
          : LogUser(id: json['user_id'] ?? 0, name: '未知用户', role: '用户'),
      ip: json['ip']?.toString() ?? '-',
      module: moduleAndLevel['module'] as LogModule,
      action: event,
      description: json['description']?.toString() ?? '',
      level: moduleAndLevel['level'] as LogLevel,
      details: json['payload'] is Map ? json['payload'] as Map<String, dynamic> : null,
    );
  }
}

/// 事件类型映射表（后端返回）
Map<String, String> eventMap = {};

/// 更新事件映射表
void updateEventMap(Map<String, dynamic> map) {
  eventMap = map.map((k, v) => MapEntry(k, v.toString()));
}

/// 获取事件显示名称
String getEventLabel(String event) {
  return eventMap[event] ?? event;
}

const moduleLabels = {
  LogModule.auth: '登录/安全',
  LogModule.netbar: '网吧管理',
  LogModule.channel: '通道管理',
  LogModule.desktop: '桌面管理',
  LogModule.system: '系统设置',
  LogModule.startup: '启动项',
  LogModule.remote: '远程操作',
  LogModule.command: '命令行',
  LogModule.client: '客户端',
};

const levelConfig = {
  LogLevel.info: {'label': '信息', 'color': Colors.blue, 'bg': Color(0xFFEFF6FF)}, // bg-blue-50
  LogLevel.success: {'label': '成功', 'color': Colors.green, 'bg': Color(0xFFF0FDF4)}, // bg-green-50
  LogLevel.warning: {'label': '警告', 'color': Colors.orange, 'bg': Color(0xFFFFF7ED)}, // bg-amber-50
  LogLevel.error: {'label': '错误', 'color': Colors.red, 'bg': Color(0xFFFEF2F2)}, // bg-red-50
};

/// 解析事件类型，返回模块和级别
Map<String, dynamic> _parseEvent(String event) {
  LogModule module = LogModule.system;
  LogLevel level = LogLevel.info;

  // 根据事件名称判断模块
  if (event.startsWith('startup_')) {
    module = LogModule.startup;
    if (event.contains('enable')) {
      level = LogLevel.success;
    } else if (event.contains('disable')) {
      level = LogLevel.warning;
    }
  } else if (event.startsWith('remote_')) {
    module = LogModule.remote;
    if (event.contains('connect')) {
      level = LogLevel.info;
    } else if (event.contains('disconnect')) {
      level = LogLevel.warning;
    } else if (event.contains('awake')) {
      level = LogLevel.success;
    }
  } else if (event.startsWith('command_')) {
    module = LogModule.command;
  } else if (event.startsWith('client_')) {
    module = LogModule.client;
    if (event.contains('kill')) {
      level = LogLevel.warning;
    }
  } else if (event.startsWith('merchant_') || event.startsWith('netbar_')) {
    module = LogModule.netbar;
  } else if (event.startsWith('channel_') || event.startsWith('file_')) {
    module = LogModule.channel;
  } else if (event.startsWith('layout_') || event.startsWith('desktop_')) {
    module = LogModule.desktop;
  } else if (event.startsWith('user_') || event.startsWith('auth_') || event.startsWith('login_')) {
    module = LogModule.auth;
  }

  return {'module': module, 'level': level};
}

LogLevel _mapLevel(String level) {
  switch (level) {
    case 'warn':
    case 'warning':
      return LogLevel.warning;
    case 'error':
    case 'fail':
      return LogLevel.error;
    case 'success':
      return LogLevel.success;
    default:
      return LogLevel.info;
  }
}

LogModule _mapModule(String module) {
  switch (module) {
    case 'auth':
      return LogModule.auth;
    case 'netbar':
      return LogModule.netbar;
    case 'channel':
      return LogModule.channel;
    case 'desktop':
      return LogModule.desktop;
    case 'startup':
      return LogModule.startup;
    case 'remote':
      return LogModule.remote;
    case 'command':
      return LogModule.command;
    case 'client':
      return LogModule.client;
    default:
      return LogModule.system;
  }
}

String _formatTime(String raw) {
  if (raw.isEmpty) return '-';
  DateTime? parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(parsed.toLocal());
}
