import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

enum LogLevel { info, warning, error, success }
enum LogModule { auth, netbar, channel, desktop, system }

class LogUser {
  final String name;
  final String? avatar;
  final String role;

  const LogUser({required this.name, this.avatar, required this.role});
}

class LogEntry {
  final String id;
  final String timestamp;
  final LogUser user;
  final String ip;
  final LogModule module;
  final String action;
  final String description;
  final LogLevel level;
  final Map<String, dynamic>? details;

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
    final levelStr = (json['level'] ?? '').toString().toLowerCase();
    final moduleStr = (json['module'] ?? '').toString().toLowerCase();

    return LogEntry(
      id: json['id']?.toString() ?? '',
      timestamp: _formatTime(createdAt),
      user: LogUser(
        name: json['username']?.toString() ?? '未知用户',
        role: json['role']?.toString() ?? '用户',
      ),
      ip: json['ip']?.toString() ?? '-',
      module: _mapModule(moduleStr),
      action: json['action']?.toString() ?? '',
      description: json['message']?.toString() ?? '',
      level: _mapLevel(levelStr),
      details: null,
    );
  }
}

const moduleLabels = {
  LogModule.auth: '登录/安全',
  LogModule.netbar: '网吧管理',
  LogModule.channel: '通道管理',
  LogModule.desktop: '桌面管理',
  LogModule.system: '系统设置'
};

const levelConfig = {
  LogLevel.info: {'label': '信息', 'color': Colors.blue, 'bg': Color(0xFFEFF6FF)}, // bg-blue-50
  LogLevel.success: {'label': '成功', 'color': Colors.green, 'bg': Color(0xFFF0FDF4)}, // bg-green-50
  LogLevel.warning: {'label': '警告', 'color': Colors.orange, 'bg': Color(0xFFFFF7ED)}, // bg-amber-50
  LogLevel.error: {'label': '错误', 'color': Colors.red, 'bg': Color(0xFFFEF2F2)}, // bg-red-50
};

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
