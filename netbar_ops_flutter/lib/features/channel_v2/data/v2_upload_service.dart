import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'channel_v2_api.dart';
import 'v2_file_source.dart';

// 分片阈值 / 分片尺寸 kV2ChunkSize（2MB）定义在 v2_file_source.dart，
// 与流式读块尺寸共用同一个常量，避免两处各写一份漂移。

final v2UploadServiceProvider = Provider(
  (ref) => V2UploadService(api: ref.read(channelV2ApiProvider)),
);

enum V2UploadStatus { idle, uploading, done, error, canceled }

/// 队列项：服务改状态，弹窗渲染状态（对齐 UploadDialog.vue files[] 的形态）
class V2UploadItem {
  final V2UploadEntry entry;

  V2UploadStatus status = V2UploadStatus.idle;
  int progress = 0;

  /// 上传成功后的 group_files.id（自动下发 / T8c-T8d 后续动作用）
  int? uploadedId;
  String? error;

  /// 用户点了单项取消（未开始的项轮到时短路，不调任何接口）
  bool cancelled = false;

  V2UploadItem(this.entry);

  String get name => entry.name;
  int get size => entry.size;
}

/// 取消属于内部控制流，不是失败：批量层单独捕获，不计入 failed
class V2UploadCancelled implements Exception {
  const V2UploadCancelled();
}

/// 自动下发目标（"拖到下发区上传"路径才有；本批不做拖拽，签名先预留）
class V2AutoDistribute {
  final String scopeType;
  final String scopeId;
  final String scopeName;

  const V2AutoDistribute({
    required this.scopeType,
    required this.scopeId,
    required this.scopeName,
  });
}

class V2UploadBatchResult {
  final int succeeded;
  final int failed;
  final int canceled;
  final int distributedOk;
  final int distributedFail;

  const V2UploadBatchResult({
    this.succeeded = 0,
    this.failed = 0,
    this.canceled = 0,
    this.distributedOk = 0,
    this.distributedFail = 0,
  });
}

/// 透传给上传接口的归属字段（决定文件落到哪个 scope 的资源区）。
/// 保真移植 useFileUpload.js:95-104：
///   - hq           → 空（后端按账号身份定落点）
///   - group        → {group_id}
///   - distribution → 按 scope 类型给 {group_id} 或 {merchant_id}
Map<String, String> buildV2UploadExtra(
  String sourceZone, {
  String? scopeType,
  String? scopeId,
  int? groupId,
}) {
  if (sourceZone == 'group') {
    return groupId != null ? {'group_id': '$groupId'} : const {};
  }
  if (sourceZone == 'distribution') {
    if (scopeType == 'group' && scopeId != null) return {'group_id': scopeId};
    if (scopeType == 'merchant' && scopeId != null) {
      return {'merchant_id': scopeId};
    }
  }
  return const {};
}

/// V2 上传服务：MD5 → 秒传 → 分片/普通上传 三级路径 + 串行队列。
class V2UploadService {
  final ChannelV2Api api;
  final V2FileSource source;

  V2UploadService({required this.api, V2FileSource? source})
      : source = source ?? v2FileSource;

  // ==================== 串行队列 ====================

  /// 串行上传（**硬约束：禁止并发**，照抄 useFileUpload.js:44-47 的两条原因）：
  ///   1) 目录是后端按 folder 路径「查不到就建」的，并发时同一文件夹的 N 个文件
  ///      会各建各的，资源区出现 N 个重名目录（拖文件夹上传时必现）
  ///   2) /file/uploadSlice 只用 filename 做键，并发上传同名文件会互相串分片
  ///
  /// 同理不复用全局 uploadQueueProvider：它 5 路并发、无 MD5/秒传/分片/取消/extra，
  /// 且被旧两页共用，混进来会互相污染。
  Future<V2UploadBatchResult> uploadBatch({
    required List<V2UploadItem> items,
    required String folderId,
    Map<String, String> extra = const {},
    V2AutoDistribute? autoDistribute,
    VoidCallback? onChanged,
  }) async {
    final succeeded = <V2UploadItem>[];
    var failed = 0;
    var canceled = 0;

    for (final item in items) {
      // 未开始就被取消：只标记，**不调 cancelSlice**——该接口只按 filename 做键，
      // 对没开始传的文件调它会误杀同名的在传任务（对齐 UploadDialog.vue:277-280）
      if (item.cancelled) {
        item.status = V2UploadStatus.canceled;
        canceled++;
        onChanged?.call();
        continue;
      }

      item.status = V2UploadStatus.uploading;
      item.progress = 0;
      item.error = null;
      onChanged?.call();

      try {
        final id = await uploadOne(
          entry: item.entry,
          folderId: folderId,
          extra: extra,
          onProgress: (percent) {
            item.progress = percent < 0 ? 0 : (percent > 100 ? 100 : percent);
            onChanged?.call();
          },
          isCancelled: () => item.cancelled,
        );
        if (item.cancelled) {
          // 普通上传路径（③）在请求过程中没有取消检查点，请求跑完才发现被取消：
          // 与 web 一致标记为已取消、不计入成功、不参与自动下发
          // （对齐 UploadDialog.vue:318-320）
          item.status = V2UploadStatus.canceled;
          canceled++;
        } else {
          item.uploadedId = id;
          item.status = V2UploadStatus.done;
          // 单项成功后强制置 100：分片路径进度被封顶在 99，不补这一下会永远差 1%
          // （对齐 UploadDialog.vue:322-323）
          item.progress = 100;
          succeeded.add(item);
        }
      } on V2UploadCancelled {
        item.status = V2UploadStatus.canceled;
        canceled++;
      } catch (e) {
        item.status = V2UploadStatus.error;
        item.error = v2UploadErrorMessage(e);
        failed++;
      }
      onChanged?.call();
    }

    var distOk = 0;
    var distFail = 0;
    if (autoDistribute != null && succeeded.isNotEmpty) {
      // 逐个下发到当前 scope 的**根目录**（parentId=0，对齐 useFileUpload.js:73-78）。
      // web 用 Promise.allSettled 并发；这里改串行——下发接口很轻，串行不影响体感，
      // 且与上面的串行上传保持同一约束风格。
      for (final item in succeeded) {
        final id = item.uploadedId;
        if (id == null) {
          distFail++;
          continue;
        }
        try {
          await api.addDeliveryResource(
            scopeType: autoDistribute.scopeType,
            scopeId: autoDistribute.scopeId,
            parentId: 0,
            groupFileId: id,
          );
          distOk++;
        } catch (_) {
          distFail++;
        }
      }
    }

    return V2UploadBatchResult(
      succeeded: succeeded.length,
      failed: failed,
      canceled: canceled,
      distributedOk: distOk,
      distributedFail: distFail,
    );
  }

  // ==================== 单文件三级路径 ====================

  /// 上传单个文件，返回**新文件的 group_file_id**（T8c/T8d 自动下发等依赖此出口）。
  ///
  /// 三级路径对齐 fileUpload.js:58-180：
  ///   ① MD5 → 秒传探测命中即结束
  ///   ② size > 2MB → 逐片 uploadSlice + mergeSlice
  ///   ③ 否则 /file/upload 普通上传
  ///
  /// 取消时抛 [V2UploadCancelled]；其它异常表示真失败。
  Future<int?> uploadOne({
    required V2UploadEntry entry,
    required String folderId,
    Map<String, String> extra = const {},
    void Function(int percent)? onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    if (cancelled()) throw const V2UploadCancelled();

    // folder 语义见 V2UploadEntry.folderPath：空串时 api 层整个字段不传
    final folder = entry.folderPath;

    // 流式增量 MD5（大文件走 Isolate），全程不整文件进内存
    final hash = await source.computeMd5(entry);
    if (cancelled()) throw const V2UploadCancelled();

    // ---------- ① 秒传探测 ----------
    // web 靠 `res.code === 0` 判断，code!=0 是**正常控制流**（继续走分片/普通上传）；
    // Flutter 侧 code!=0 会被拦截器 reject 成 DioException(error: ApiError)，
    // 所以这里必须**单独 try/catch**，只把「业务失败」当作未命中秒传，
    // connectionError / timeout / 其它异常照样往上抛，算真失败。
    try {
      final data = await api.instantUpload(
        hash: hash,
        filename: entry.name,
        folder: folder,
        folderId: folderId,
        extra: extra,
      );
      onProgress?.call(100); // 秒传直接 100（fileUpload.js:87）
      return _extractFileId(data) ?? await _findRecentIdByName(entry.name, extra);
    } on DioException catch (e) {
      if (e.error is! ApiError) rethrow; // 网络类失败 → 真失败
      // 业务码非 0 = 未命中秒传，继续后续路径
    }

    if (cancelled()) throw const V2UploadCancelled();

    // ---------- ② 分片上传（> 2MB） ----------
    if (entry.size > kV2ChunkSize) {
      final chunks = (entry.size / kV2ChunkSize).ceil();
      for (var i = 0; i < chunks; i++) {
        // 每片前检查取消。只有「当前正在分片上传的这个文件」被取消才调
        // cancelSlice（接口按 filename 做键），对齐 fileUpload.js:98-108
        if (cancelled()) {
          await _cancelSliceQuietly(entry.name);
          throw const V2UploadCancelled();
        }

        final start = i * kV2ChunkSize;
        final end =
            (start + kV2ChunkSize) < entry.size ? start + kV2ChunkSize : entry.size;
        // 按需读该片，禁止整文件进内存
        final bytes = await source.readRange(entry, start, end);

        await api.uploadSlice(
          slice: bytes,
          index: i,
          filename: entry.name,
          onSendProgress: (sent, total) {
            if (total <= 0 || onProgress == null) return;
            final chunkProgress = (sent / total) * (100 / chunks);
            var percent = ((i / chunks) * 100 + chunkProgress).round();
            // 切片全传完但还没 merge 时封顶 99%，否则用户看到 100% 却还在等
            // （对齐 fileUpload.js:126-129）
            if (percent >= 100) percent = 99;
            onProgress(percent);
          },
        );
      }

      // 【对 web 的刻意偏离，留痕】web 只在每片**开头**判取消，若用户在最后一片
      // 传输过程中取消，循环结束后仍会 merge，文件照样落库。这里补一次 merge 前
      // 的取消检查，保证「取消后不得继续 merge」（fileUpload.js:107 的意图）。
      if (cancelled()) {
        await _cancelSliceQuietly(entry.name);
        throw const V2UploadCancelled();
      }

      final data = await api.mergeSlice(
        length: chunks,
        filename: entry.name,
        folderId: folderId,
        folder: folder,
        extra: extra,
      );
      return _extractFileId(data) ?? await _findRecentIdByName(entry.name, extra);
    }

    // ---------- ③ 普通上传（<= 2MB） ----------
    final bytes = await source.readRange(entry, 0, entry.size);
    if (cancelled()) throw const V2UploadCancelled();
    final data = await api.uploadSmallFile(
      bytes: bytes,
      filename: entry.name,
      folder: folder,
      folderId: folderId,
      extra: extra,
      onSendProgress: (sent, total) {
        if (total <= 0 || onProgress == null) return;
        onProgress(((sent / total) * 100).round());
      },
    );
    return _extractFileId(data) ?? await _findRecentIdByName(entry.name, extra);
  }

  // ==================== 内部工具 ====================

  Future<void> _cancelSliceQuietly(String filename) async {
    try {
      await api.cancelSliceUpload(filename);
    } catch (_) {
      // 取消接口失败不影响"已取消"这个结论（对齐 fileUpload.js:104-106 只 warn）
    }
  }

  /// 从上传响应里挖新文件 id（形态不统一，对齐 UploadDialog.vue:329 的取值链）
  int? _extractFileId(dynamic data) {
    if (data is! Map) return null;
    final candidates = <dynamic>[
      data['id'],
      _nested(data, 'user_file'),
      _nested(data, 'userFile'),
      _nested(data, 'group_file'),
    ];
    for (final c in candidates) {
      final v = _toInt(c);
      if (v != null) return v;
    }
    return null;
  }

  dynamic _nested(Map data, String key) {
    final v = data[key];
    return v is Map ? v['id'] : null;
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// 兜底：秒传/合并响应不带新文件 id 时，按文件名查目标 scope 根目录取 id 最大一条。
  ///
  /// 保真移植 useFileUpload.js:109-122。**已知缺陷（先照搬不改）**：同名文件多次
  /// 上传时会挑到"最新那条"，可能不是本次这条；后续要治本得让后端在秒传响应里回 id。
  Future<int?> _findRecentIdByName(
      String filename, Map<String, String> extra) async {
    try {
      final list = await api.listRootForUploadFallback(extra);
      final matches =
          list.where((f) => f.name == filename && !f.isFolder).toList();
      if (matches.isEmpty) return null;
      matches.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
      return matches.first.id;
    } catch (_) {
      return null;
    }
  }
}

/// 失败文案提取：拦截器把业务错误塞在 DioException.error 里（ApiError.message），
/// 直接 toString 会给用户一串英文 DioException
String v2UploadErrorMessage(Object e) {
  if (e is DioException) {
    final err = e.error;
    if (err is ApiError) return err.message;
    return e.message ?? '上传失败';
  }
  if (e is ApiError) return e.message;
  return e.toString();
}
