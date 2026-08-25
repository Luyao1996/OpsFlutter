import 'dart:typed_data';

import 'v2_file_source_stub.dart'
    if (dart.library.io) 'v2_file_source_io.dart';

/// V2 上传的文件枚举 / 按需读取层（条件导入，惯例对齐
/// features/channel/presentation/widgets/upload_helper.dart）。
///
/// 【为什么不复用旧的 PlatformFileHelper】它在"选择"阶段就把整目录 readAsBytes
/// 进内存（upload_helper_io.dart:55 readDirectoryFromPath / :126 readFilesFromPaths），
/// 选一个大文件或大目录必 OOM。本层只存路径与大小，字节一律按需读。

/// 分片 / 流式读块大小：2MB。上传分片尺寸、MD5 增量块尺寸共用同一个值
/// （对齐 fileUpload.js:13 chunkSize、:92 CHUNK_SIZE）。
const int kV2ChunkSize = 2 * 1024 * 1024;

/// 待上传条目：**只存路径与大小，选择阶段绝不读字节**。
class V2UploadEntry {
  final String name;
  final String absolutePath;

  /// 相对路径，语义对齐 web File.webkitRelativePath：
  ///   - 选文件     → 就是文件名（不含 '/'）
  ///   - 选文件夹   → '{所选目录名}/…/{文件名}'
  final String relativePath;

  final int size;

  const V2UploadEntry({
    required this.name,
    required this.absolutePath,
    required this.relativePath,
    required this.size,
  });

  /// 上传接口的 `folder` 字段值 = relativePath **去掉最后一段（文件名）**，
  /// 且仅当 relativePath 含 '/' 才有值（对齐 fileUpload.js:69-75）。
  ///
  /// 为空时调用方必须**整个字段不传**（fileUpload.js:147-149、:163-165 三处
  /// 都是条件 append）。禁止把含文件名的 relativePath 直传——旧代码
  /// features/channel/data/resource_api.dart:130 就是踩了这个坑，
  /// 后端会按"路径查不到就建目录"多建一层以文件名命名的目录。
  String get folderPath {
    if (!relativePath.contains('/')) return '';
    final segs = relativePath.split('/');
    return segs.sublist(0, segs.length - 1).join('/');
  }
}

/// 平台文件源抽象。
abstract class V2FileSource {
  /// 是否提供"选择文件"入口（Web 端暂未实现 → false）
  bool get supportsFilePick;

  /// 是否提供"选择文件夹"入口。
  /// 移动端恒 false：web 端目录上传依赖 `<input webkitdirectory>`，
  /// 移动端无等价物（系统文件选择器不返回目录树），入口直接不渲染。
  bool get supportsFolderPick;

  Future<List<V2UploadEntry>> pickFiles();

  Future<List<V2UploadEntry>> pickFolder();

  /// 按需读取 [start, end) 区间字节（分片上传逐片调用），不整文件进内存。
  Future<Uint8List> readRange(V2UploadEntry entry, int start, int end);

  /// 流式读取（默认 2MB/块，与上传分片同尺寸）。
  Stream<List<int>> openRead(V2UploadEntry entry,
      {int chunkSize = kV2ChunkSize});

  /// 计算文件 MD5：内部流式增量计算，大文件走 Isolate（Isolate 内同样流式）。
  Future<String> computeMd5(V2UploadEntry entry);
}

/// 平台实例（条件导入决定实现）
V2FileSource get v2FileSource => getV2FileSource();
