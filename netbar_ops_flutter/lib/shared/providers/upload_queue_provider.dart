import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/channel/data/resource_api.dart';

enum UploadStatus { pending, uploading, success, error, cancelled }

class UploadTask {
  final String id;
  final String name;
  final int size;
  final bool isDirectory;
  final String? error;
  final String? relativePath;
  final int? parentId;
  final String? zone;
  final int? netbarId;
  final List<int>? bytes;
  final UploadStatus status;
  final int progress;
  final bool extractZip;

  UploadTask({
    required this.id,
    required this.name,
    required this.size,
    required this.isDirectory,
    this.error,
    this.relativePath,
    this.parentId,
    this.zone,
    this.netbarId,
    this.bytes,
    this.status = UploadStatus.pending,
    this.progress = 0,
    this.extractZip = false,
  });

  UploadTask copyWith({
    UploadStatus? status,
    int? progress,
    String? error,
    bool? extractZip,
  }) {
    return UploadTask(
      id: id,
      name: name,
      size: size,
      isDirectory: isDirectory,
      error: error ?? this.error,
      relativePath: relativePath,
      parentId: parentId,
      zone: zone,
      netbarId: netbarId,
      bytes: bytes,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      extractZip: extractZip ?? this.extractZip,
    );
  }

  /// 检查是否为ZIP文件
  bool get isZipFile {
    final ext = name.toLowerCase();
    return ext.endsWith('.zip');
  }
}

class UploadQueueState {
  final List<UploadTask> tasks;
  final bool isMinimized;

  const UploadQueueState({
    this.tasks = const [],
    this.isMinimized = false,
  });

  UploadQueueState copyWith({
    List<UploadTask>? tasks,
    bool? isMinimized,
  }) {
    return UploadQueueState(
      tasks: tasks ?? this.tasks,
      isMinimized: isMinimized ?? this.isMinimized,
    );
  }
}

class UploadQueueNotifier extends StateNotifier<UploadQueueState> {
  final ResourceApi _api = ResourceApi();
  bool _processing = false;
  final int _maxConcurrent = 5;

  UploadQueueNotifier() : super(const UploadQueueState());

  void enqueue(List<UploadTask> tasks) {
    state = state.copyWith(tasks: [...state.tasks, ...tasks]);
    _process();
  }

  void remove(String id) {
    state = state.copyWith(tasks: state.tasks.where((t) => t.id != id).toList());
  }

  void clearCompleted() {
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.uploading || t.status == UploadStatus.error).toList(),
    );
  }

  void clearAll() {
    state = state.copyWith(tasks: []);
  }

  void toggleMinimize() {
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    try {
      while (true) {
        final uploadingCount = state.tasks.where((t) => t.status == UploadStatus.uploading).length;
        final availableSlots = _maxConcurrent - uploadingCount;
        if (availableSlots <= 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final pending = state.tasks.where((t) => t.status == UploadStatus.pending).take(availableSlots).toList();
        if (pending.isEmpty && uploadingCount == 0) break;

        for (final task in pending) {
          _markStatus(task.id, UploadStatus.uploading, progress: 1);
          _uploadTask(task).then((_) {
            _markStatus(task.id, UploadStatus.success, progress: 100);
          }).catchError((e) {
            _markStatus(task.id, UploadStatus.error, error: e.toString());
          });
        }

        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      _processing = false;
    }
  }

  void _markStatus(String id, UploadStatus status, {int? progress, String? error}) {
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id != id) return t;
        return t.copyWith(
          status: status,
          progress: progress ?? t.progress,
          error: error,
        );
      }).toList(),
    );
  }

  void _markProgress(String id, int progress) {
    state = state.copyWith(
      tasks: state.tasks.map((t) => t.id == id ? t.copyWith(progress: progress) : t).toList(),
    );
  }

  Future<void> _uploadTask(UploadTask task) async {
    if (task.isDirectory) {
      // 目录任务标记成功，不单独调用接口（由 relative_path 自动处理）
      return;
    }
    if (task.bytes == null) throw Exception('文件数据为空');
    await _api.uploadFile(
      name: task.name,
      bytes: task.bytes!,
      zone: task.zone,
      parentId: task.parentId,
      netbarId: task.netbarId,
      relativePath: task.relativePath,
      extractZip: task.extractZip,
      onSendProgress: (sent, total) {
        if (total > 0) {
          final pct = max(1, ((sent / total) * 100).round());
          _markProgress(task.id, pct);
        }
      },
    );
  }

  /// 更新任务的 extractZip 属性
  void updateExtractZip(String id, bool extractZip) {
    state = state.copyWith(
      tasks: state.tasks.map((t) {
        if (t.id != id) return t;
        return t.copyWith(extractZip: extractZip);
      }).toList(),
    );
  }
}

final uploadQueueProvider = StateNotifierProvider<UploadQueueNotifier, UploadQueueState>((ref) {
  return UploadQueueNotifier();
});
