import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'v2_file_source.dart';

/// 超过该体积的 MD5 丢给 Isolate 算，避免长时间占住 UI 线程
const int _kMd5IsolateThreshold = 8 * 1024 * 1024;

class _V2FileSourceIO implements V2FileSource {
  @override
  bool get supportsFilePick => true;

  /// 移动端不提供选文件夹：web 依赖 `<input webkitdirectory>`，
  /// Android/iOS 系统选择器无等价能力
  @override
  bool get supportsFolderPick => !(Platform.isAndroid || Platform.isIOS);

  @override
  Future<List<V2UploadEntry>> pickFiles() async {
    // withData: false —— 只取路径，绝不在选择阶段把整文件读进内存
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (res == null) return const [];
    final out = <V2UploadEntry>[];
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      out.add(V2UploadEntry(
        name: f.name,
        absolutePath: path,
        // 顶层单文件：relativePath 不含 '/' → folderPath 为空 → 不传 folder 字段
        relativePath: f.name,
        size: f.size,
      ));
    }
    return out;
  }

  @override
  Future<List<V2UploadEntry>> pickFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return const [];
    final root = Directory(dirPath);
    if (!await root.exists()) return const [];

    final rootName = p.basename(dirPath);
    final out = <V2UploadEntry>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      // statSync 只读 inode 元数据，不读文件内容
      int size;
      try {
        size = e.statSync().size;
      } catch (_) {
        continue; // 权限/占用导致 stat 失败的条目直接跳过，不阻断整次选择
      }
      final rel = p.relative(e.path, from: dirPath).replaceAll('\\', '/');
      if (rel.isEmpty) continue;
      out.add(V2UploadEntry(
        name: p.basename(e.path),
        absolutePath: e.path,
        // 与 webkitdirectory 一致：带上所选目录本身这一层
        relativePath: '$rootName/$rel',
        size: size,
      ));
    }
    return out;
  }

  @override
  Future<Uint8List> readRange(V2UploadEntry entry, int start, int end) async {
    final raf = await File(entry.absolutePath).open();
    try {
      await raf.setPosition(start);
      return await raf.read(end - start);
    } finally {
      await raf.close();
    }
  }

  @override
  Stream<List<int>> openRead(V2UploadEntry entry,
      {int chunkSize = kV2ChunkSize}) async* {
    final raf = await File(entry.absolutePath).open();
    try {
      while (true) {
        final block = await raf.read(chunkSize);
        if (block.isEmpty) break;
        yield block;
      }
    } finally {
      await raf.close();
    }
  }

  @override
  Future<String> computeMd5(V2UploadEntry entry) {
    if (entry.size > _kMd5IsolateThreshold) {
      return compute(v2Md5OfFile, entry.absolutePath);
    }
    return v2Md5OfFile(entry.absolutePath);
  }
}

/// 顶层函数（`compute` 要求可被 Isolate 入口引用）：2MB 流式增量算 MD5。
/// Isolate 内同样不整文件进内存。
Future<String> v2Md5OfFile(String path) async {
  final sink = _DigestSink();
  final input = md5.startChunkedConversion(sink);
  final raf = await File(path).open();
  try {
    while (true) {
      final block = await raf.read(kV2ChunkSize);
      if (block.isEmpty) break;
      input.add(block);
    }
  } finally {
    await raf.close();
  }
  input.close();
  // 小写十六进制，与 web SparkMD5.end() 输出一致
  return sink.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

V2FileSource getV2FileSource() => _V2FileSourceIO();
