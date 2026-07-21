import 'dart:math' as math;

import 'terminal_models.dart';

class TerminalMockData {
  static math.Random _rng(int terminalId, String salt) {
    var hash = 0;
    final input = '$terminalId:$salt';
    for (final unit in input.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= (hash >> 6);
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= (hash >> 11);
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return math.Random(hash);
  }

  static List<TerminalProcess> processes(int terminalId) {
    final rng = _rng(terminalId, 'processes');
    const names = [
      'LeagueClientUx.exe',
      'explorer.exe',
      'svchost.exe',
      'chrome.exe',
      'WeGame.exe',
      'QQ.exe',
      'steam.exe',
      'RuntimeBroker.exe',
      'SearchApp.exe',
      'dwm.exe',
      'audiodg.exe',
      'csrss.exe',
      'winlogon.exe',
      'NetBarAgent.exe',
    ];

    final count = 18 + rng.nextInt(10);
    final list = <TerminalProcess>[];
    for (var i = 0; i < count; i++) {
      final name = names[rng.nextInt(names.length)];
      final pid = 800 + rng.nextInt(40000);
      final cpu = (rng.nextDouble() * 18).clamp(0, 99).toDouble();
      final mem = (20 + rng.nextDouble() * 900).toDouble();
      final user = rng.nextBool() ? 'Administrator' : 'SYSTEM';
      list.add(
        TerminalProcess(
          name: name,
          pid: pid,
          cpu: double.parse(cpu.toStringAsFixed(1)),
          mem: double.parse(mem.toStringAsFixed(1)),
          user: user,
        ),
      );
    }
    list.sort((a, b) => b.cpu.compareTo(a.cpu));
    return list;
  }

  static List<TerminalFile> files(int terminalId, String path) {
    final normalized = path.replaceAll('/', '\\').trim();
    final rng = _rng(terminalId, 'files:$normalized');

    String join(String base, String name) {
      if (base.endsWith('\\')) return '$base$name';
      return '$base\\$name';
    }

    final segments = normalized.split('\\').where((s) => s.isNotEmpty).toList();
    final isRoot = normalized.endsWith('\\') && segments.length <= 1;

    final folders = <String>[];
    final files = <Map<String, dynamic>>[];

    if (isRoot) {
      folders.addAll(['Users', 'Program Files', 'Windows', 'NetBar', 'Temp']);
      files.addAll([
        {'name': 'ReadMe.txt', 'size': 2048},
        {'name': 'netbar_config.json', 'size': 74231},
      ]);
    } else if (normalized.toLowerCase().contains('users')) {
      final depth = segments.length;
      if (depth == 2) {
        folders.addAll(['Administrator', 'Public', 'Default']);
      } else {
        folders.addAll(['Desktop', 'Downloads', 'Documents', 'AppData']);
        files.addAll([
          {'name': 'notes.txt', 'size': 12450},
          {'name': 'hosts_backup', 'size': 1024},
        ]);
      }
    } else if (normalized.toLowerCase().contains('netbar')) {
      folders.addAll(['apps', 'assets', 'logs', 'tools']);
      files.addAll([
        {'name': 'agent.log', 'size': 482123},
        {'name': 'update.bat', 'size': 4012},
      ]);
    } else {
      folders.addAll(['FolderA', 'FolderB', 'FolderC']);
      files.addAll([
        {'name': 'file_${rng.nextInt(9999)}.txt', 'size': 8192},
        {'name': 'setup_${rng.nextInt(99)}.exe', 'size': 120 * 1024 * 1024},
        {'name': 'report_${rng.nextInt(99)}.xlsx', 'size': 2 * 1024 * 1024},
      ]);
    }

    final now = DateTime.now();
    String ts(int minutesAgo) {
      final t = now.subtract(Duration(minutes: minutesAgo));
      final mm = t.month.toString().padLeft(2, '0');
      final dd = t.day.toString().padLeft(2, '0');
      final hh = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      return '${t.year}-$mm-$dd $hh:$mi';
    }

    final list = <TerminalFile>[];
    for (final folder in folders) {
      list.add(
        TerminalFile(
          name: folder,
          path: join(normalized, folder),
          isDirectory: true,
          size: 0,
          updatedAt: ts(10 + rng.nextInt(6000)),
        ),
      );
    }

    for (final f in files) {
      final size = (f['size'] as int?) ?? (rng.nextInt(50) * 1024);
      list.add(
        TerminalFile(
          name: f['name'] as String,
          path: join(normalized, f['name'] as String),
          isDirectory: false,
          size: size,
          updatedAt: ts(10 + rng.nextInt(6000)),
        ),
      );
    }

    list.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return list;
  }

  static List<TerminalLog> logs(int terminalId) {
    final rng = _rng(terminalId, 'logs');
    final now = DateTime.now();
    String ts(int minutesAgo) {
      final t = now.subtract(Duration(minutes: minutesAgo));
      final mm = t.month.toString().padLeft(2, '0');
      final dd = t.day.toString().padLeft(2, '0');
      final hh = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      final ss = t.second.toString().padLeft(2, '0');
      return '${t.year}-$mm-$dd $hh:$mi:$ss';
    }

    final categories = [
      'System',
      'Network',
      'Security',
      'Game',
      'Update',
      'Agent',
    ];
    final sources = [
      'NetBarAgent',
      'WindowsEventLog',
      'GameLauncher',
      'AntiCheat',
      'Updater',
    ];
    final levels = ['Info', 'Warning', 'Error'];
    final messages = [
      'Heartbeat received.',
      'Process started successfully.',
      'Failed to resolve DNS, retrying.',
      'Disk space low warning.',
      'Game session initialized.',
      'Update check completed.',
      'Security policy applied.',
      'Network latency spike detected.',
      'Service restarted.',
    ];

    final count = 60 + rng.nextInt(40);
    final list = <TerminalLog>[];
    for (var i = 0; i < count; i++) {
      final level = levels[rng.nextInt(levels.length)];
      final category = categories[rng.nextInt(categories.length)];
      final source = sources[rng.nextInt(sources.length)];
      final eventId = 1000 + rng.nextInt(9000);
      final message = messages[rng.nextInt(messages.length)];
      list.add(
        TerminalLog(
          level: level,
          time: ts(i * (1 + rng.nextInt(3))),
          source: source,
          eventId: eventId,
          category: category,
          message: message,
        ),
      );
    }
    return list;
  }

  static String commandOutput(int terminalId, String command) {
    final cmd = command.trim();
    if (cmd.isEmpty) return '';
    final lower = cmd.toLowerCase();
    if (lower == 'dir') {
      return '''
 Volume in drive C is System
 Directory of C:\\

12/16/2025  16:30    <DIR>          Users
12/16/2025  16:30    <DIR>          Windows
12/16/2025  16:30    <DIR>          NetBar
               0 File(s)              0 bytes
               3 Dir(s)  123,456,789,012 bytes free
''';
    }
    if (lower.startsWith('ping ')) {
      return 'Reply from 192.168.1.1: bytes=32 time=3ms TTL=64';
    }
    return 'Mock: executed "$cmd" successfully.';
  }
}
