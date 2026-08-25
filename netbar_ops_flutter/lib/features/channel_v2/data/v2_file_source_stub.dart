import 'dart:typed_data';

import 'v2_file_source.dart';

/// Web 端占位实现：无 dart:io 文件句柄，无法做「只取路径 + 按需分片读」，
/// 若要支持需另做 Blob.slice 方案。入口按 supports* 直接不渲染，
/// 读取类方法一旦被调到即抛错，避免静默上传空文件。
class _V2FileSourceStub implements V2FileSource {
  @override
  bool get supportsFilePick => false;

  @override
  bool get supportsFolderPick => false;

  @override
  Future<List<V2UploadEntry>> pickFiles() async => const [];

  @override
  Future<List<V2UploadEntry>> pickFolder() async => const [];

  @override
  Future<Uint8List> readRange(V2UploadEntry entry, int start, int end) =>
      throw UnsupportedError('Web 端暂不支持 ChannelV2 上传');

  @override
  Stream<List<int>> openRead(V2UploadEntry entry,
          {int chunkSize = kV2ChunkSize}) =>
      throw UnsupportedError('Web 端暂不支持 ChannelV2 上传');

  @override
  Future<String> computeMd5(V2UploadEntry entry) =>
      throw UnsupportedError('Web 端暂不支持 ChannelV2 上传');
}

V2FileSource getV2FileSource() => _V2FileSourceStub();
