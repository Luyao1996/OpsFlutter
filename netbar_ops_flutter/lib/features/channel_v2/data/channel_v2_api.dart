import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'channel_v2_models.dart';

final channelV2ApiProvider = Provider((ref) => ChannelV2Api());

/// ChannelV2 网络层。
///
/// 后端语义（对齐 web api/delivery.js 头注释）：
///   - 资源中心存 group_files（源文件），CRUD 复用老 /file/* 接口
///   - 下发区存 delivery_nodes（指向 group_file 的下发记录）
///   - 一个 group_file 可被下发多次到不同 scope（hq / group / merchant）
class ChannelV2Api {
  final ApiClient _client = ApiClient.instance;

  /// 资源区列表 → GET /file/view（对齐 web api/resource.js:21-33）。
  ///
  /// 区域语义：
  ///   - hq    → 恒传 group_id='0'（所有账号看总部公共资源）
  ///   - group → 传具体 group_id
  /// 每层目录都必须带 group_id：小组区子目录若只带 parent_id，
  /// 后端无法从父目录推断归属，会退回默认组返回错数据。
  Future<List<V2File>> listResources({
    required String zone, // 'hq' | 'group'
    int? groupId,
    int? parentId,
  }) async {
    final params = <String, dynamic>{};
    if (parentId != null) params['parent_id'] = '$parentId';
    if (zone == 'hq') {
      params['group_id'] = '0';
    } else if (zone == 'group' && groupId != null) {
      params['group_id'] = '$groupId';
    }
    final response = await _client.get('/file/view', queryParameters: params);
    return _parseResourceList(response.data);
  }

  /// 解析 /file/view 响应：data.files，paginator.data 兜底（对齐 useZoneFiles.js:45）
  List<V2File> _parseResourceList(dynamic data) {
    List<dynamic>? list;
    if (data is Map<String, dynamic>) {
      if (data['files'] is List) {
        list = data['files'] as List;
      } else if (data['paginator'] is Map &&
          (data['paginator'] as Map)['data'] is List) {
        list = (data['paginator'] as Map)['data'] as List;
      }
    }
    return (list ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(V2File.fromResourceJson)
        .toList();
  }

  /// 下发树 → GET /delivery/tree（对齐 web api/delivery.js:22-30）。
  /// 返回该 scope 下完整嵌套树（已做 markFolderStartup 后处理），
  /// 前端在树内做"进入子文件夹"的本地导航，不再额外请求。
  Future<List<V2File>> getDeliveryTree({
    required String scopeType, // 'hq' | 'group' | 'merchant'
    required String scopeId,
  }) async {
    final response = await _client.get('/delivery/tree', queryParameters: {
      'scope_type': scopeType,
      'scope_id': scopeId,
    });
    final data = response.data;
    // 响应容错：files 为后端实际字段，items/tree/children/nodes 兜底
    // （对齐 useDistributionFiles.js:91-99）
    List<dynamic>? arr;
    if (data is List) {
      arr = data;
    } else if (data is Map<String, dynamic>) {
      for (final k in const ['files', 'items', 'tree', 'children', 'nodes']) {
        if (data[k] is List) {
          arr = data[k] as List;
          break;
        }
      }
    }
    final tree = (arr ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(V2File.fromDeliveryJson)
        .toList();
    markFolderStartup(tree);
    return tree;
  }

  /// 下发资源到 scope → POST /delivery/resource
  /// （对齐 web api/delivery.js:41-48：参数全字符串化、parent_id 默认 '0'）。
  /// T8a 不接 UI，API 先落——T8b 拖拽/右键下发直接挂用。
  Future<void> addDeliveryResource({
    required String scopeType,
    required String scopeId,
    dynamic parentId = 0,
    required dynamic groupFileId,
  }) async {
    await _client.post('/delivery/resource', data: {
      'scope_type': scopeType,
      'scope_id': scopeId,
      'parent_id': '${parentId ?? 0}',
      'group_file_id': '$groupFileId',
    });
  }

  /// 移动下发节点 → POST /delivery/move（对齐 web api/delivery.js:57-62）。
  /// id 是 delivery_nodes.id，不能传源文件 id。
  Future<void> moveDeliveryNode({
    required dynamic id,
    dynamic parentId = 0,
  }) async {
    await _client.post('/delivery/move', data: {
      'id': '$id',
      'parent_id': '${parentId ?? 0}',
    });
  }

  /// 删除下发节点 → DELETE /delivery/{id}（对齐 web api/delivery.js:69-72，
  /// RESTful，id 在 path 里）
  Future<void> deleteDeliveryNode(dynamic id) async {
    await _client.delete('/delivery/$id');
  }

  // ==================== 上传链路 ====================
  //
  // 【统一走 _client.dio 原生调用，不经 ApiClient.post 包装，两条原因】
  //   1) 需要 onSendProgress 上报进度，ApiClient.post 未透出该参数；
  //   2) 秒传探测必须区分「业务 code!=0（未命中，正常控制流）」与「网络失败」。
  //      ApiClient.post 的 _handleError 把两者压成同一个 ApiError（且 code 被换成
  //      HTTP statusCode），DioExceptionType 丢失后无法判别；走 dio 原生则拦截器
  //      reject 的 DioException(error: ApiError) 原样抛出，调用方按
  //      `e.error is ApiError` 判业务失败、按 e.type 判网络失败。
  //   响应仍被拦截器解包：code==0 时 response.data 已是后端 data 字段。

  /// 秒传探测 → POST /file/instant（对齐 fileUpload.js:78-89）。
  ///
  /// 命中返回后端 data；未命中时后端返回 code!=0，本方法**抛
  /// DioException(error: ApiError)**——调用方必须单独 catch 并视为「未命中，
  /// 继续走分片/普通上传」，不得当作上传失败。
  Future<dynamic> instantUpload({
    required String hash,
    required String filename,
    String? folder,
    required String folderId,
    Map<String, String> extra = const {},
  }) async {
    final response = await _client.dio.post('/file/instant', data: {
      'hash': hash,
      'filename': filename,
      // folder 仅在文件来自子目录时才带（web fileUpload.js:69-84 同款条件：
      // webkitRelativePath 不含 '/' 时 folderPath 为空串）
      if (folder != null && folder.isNotEmpty) 'folder': folder,
      'folder_id': folderId,
      ...extra,
    });
    return response.data;
  }

  /// 上传单个分片 → POST /file/uploadSlice（FormData；对齐 fileUpload.js:114-134）。
  ///
  /// 后端只用 filename 做分片归集键 → 同名文件并发上传会互串分片，
  /// 调用方必须串行（见 v2_upload_service.dart 串行队列）。
  Future<void> uploadSlice({
    required List<int> slice,
    required int index,
    required String filename,
    ProgressCallback? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      // 【对 web 的刻意偏离，留痕】web `FormData.append('slice', Blob)` 的 part
      // 文件名恒为 "blob"；这里给真实文件名便于后端日志定位。字段名与取值键
      // （slice/index/filename）均未变，后端解析路径不受影响。
      'slice': MultipartFile.fromBytes(slice, filename: filename),
      'index': '$index',
      'filename': filename,
    });
    await _client.dio.post(
      '/file/uploadSlice',
      data: form,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  /// 合并分片 → POST /file/mergeSlice（对齐 fileUpload.js:141-151）
  Future<dynamic> mergeSlice({
    required int length,
    required String filename,
    required String folderId,
    String? folder,
    Map<String, String> extra = const {},
  }) async {
    final response = await _client.dio.post('/file/mergeSlice', data: {
      'length': length,
      'filename': filename,
      'folder_id': folderId,
      if (folder != null && folder.isNotEmpty) 'folder': folder,
      ...extra,
    });
    return response.data;
  }

  /// 取消分片上传 → POST /file/cancelSlice（对齐 api/file.js:48-50 +
  /// fileUpload.js:100-103：FormData 只带 filename）。
  ///
  /// 接口只按 filename 做键 → 只能对「当前正在分片上传的那个文件」调用一次；
  /// 未开始的队列项只做本地标记，不得调本接口（否则会误杀同名的在传任务）。
  Future<void> cancelSliceUpload(String filename) async {
    await _client.dio.post(
      '/file/cancelSlice',
      data: FormData.fromMap({'filename': filename}),
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  /// 普通上传（<=2MB 小文件）→ POST /file/upload（对齐 fileUpload.js:160-177）
  Future<dynamic> uploadSmallFile({
    required List<int> bytes,
    required String filename,
    String? folder,
    required String folderId,
    Map<String, String> extra = const {},
    ProgressCallback? onSendProgress,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
      if (folder != null && folder.isNotEmpty) 'folder': folder,
      'folder_id': folderId,
      // 【对 web 的刻意偏离，留痕】web 这条路径漏传 extra（fileUpload.js:160-167
      // 只 append file/folder/folder_id），判定为上游 bug：小组区上传的小文件会
      // 丢 group_id 落到默认组。这里补上。
      // ⚠ 待真机验证：后端 multipart 分支是否解析 group_id / merchant_id；
      //   若被参数校验拒绝（如"未知字段"），需回退为不传 extra。
      ...extra,
    });
    final response = await _client.dio.post(
      '/file/upload',
      data: form,
      onSendProgress: onSendProgress,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.data;
  }

  /// 秒传兜底查询（保真移植 useFileUpload.js:109-122）：
  /// 秒传响应不带新文件 id 时，按 extra 指定的 scope 查根目录列表再按文件名匹配。
  ///
  /// 注意查询键是 `folder_id` 而非 listResources 的 `parent_id`——与 web 一致，
  /// 不要"顺手改成 parent_id"。
  Future<List<V2File>> listRootForUploadFallback(
      Map<String, String> extra) async {
    final response = await _client.get('/file/view', queryParameters: {
      'folder_id': '0',
      ...extra,
    });
    return _parseResourceList(response.data);
  }

  // ==================== 资源文件操作（/file/*） ====================
  // 本批只落 API，UI 由 T8b-2 接。

  /// 文件属性 → GET /file/attribute（对齐 FilePropsDialog.vue:112-114）。
  /// 返回 data.userFile；缺字段/失败返回 null，由调用方用列表字段兜底。
  Future<V2FileAttribute?> getFileAttribute(dynamic groupFileId) async {
    final response = await _client.get('/file/attribute', queryParameters: {
      'group_file_id': '$groupFileId',
    });
    final data = response.data;
    if (data is Map<String, dynamic> &&
        data['userFile'] is Map<String, dynamic>) {
      return V2FileAttribute.fromJson(data['userFile'] as Map<String, dynamic>);
    }
    return null;
  }

  /// 删除资源文件 → POST /file/destroy（对齐 useFileActions.js:21-22）
  Future<void> destroyResource(dynamic groupFileId) async {
    await _client.post('/file/destroy', data: {'group_file_id': groupFileId});
  }

  /// 重命名资源文件 → POST /file/rename（对齐 useFileActions.js:17-18；
  /// 新名字的字段名是 `filename`，不是 name）
  Future<void> renameResource(dynamic groupFileId, String name) async {
    await _client.post('/file/rename', data: {
      'group_file_id': groupFileId,
      'filename': name,
    });
  }

  /// 解压压缩包 → POST /file/extract（对齐 api/file.js:6-9）
  Future<void> extractResource(dynamic groupFileId) async {
    await _client.post('/file/extract', data: {'group_file_id': groupFileId});
  }

  /// 隐藏资源 → POST /file/hide（对齐 FilePropsDialog.vue:161-165）
  Future<void> hideResource(dynamic groupFileId) async {
    await _client.post('/file/hide', data: {'group_file_id': groupFileId});
  }

  /// 取消隐藏 → POST /file/unhide
  Future<void> unhideResource(dynamic groupFileId) async {
    await _client.post('/file/unhide', data: {'group_file_id': groupFileId});
  }

  // ==================== 任务列表（T8d） ====================

  /// 后台任务分页 → GET /task（对齐 web api/task.js:3 `request.get('/task', {params})`，
  /// 参数名就是 page / per_page，见 TaskListDialog.vue:165-168）。
  ///
  /// 响应取 `data.paginator`（data/current_page/total/per_page）；
  /// ApiClient 已剥掉 {code,message,data} 外壳，故这里的 response.data 就是 data。
  /// paginator 缺失一律返回空页，不抛——任务列表是只读视图，报错弹窗价值不如空态。
  Future<V2TaskPage> listTasks({int page = 1, int perPage = 20}) async {
    final response = await _client.get('/task', queryParameters: {
      'page': page,
      'per_page': perPage,
    });
    final data = response.data;
    final paginator = (data is Map<String, dynamic>) ? data['paginator'] : null;
    if (paginator is! Map) return V2TaskPage.empty;

    int pick(String key, int fallback) {
      final v = paginator[key];
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    final list = paginator['data'];
    final items = (list is List ? list : const [])
        .whereType<Map>()
        .map((e) => V2Task.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return V2TaskPage(
      items: items,
      total: pick('total', items.length),
      currentPage: pick('current_page', page),
      perPage: pick('per_page', perPage),
    );
  }

  /// 移动资源文件 → POST /file/move，**JSON body**。
  ///
  /// 【留痕】api/file.js:53-58 的 docblock 写的是 FormData，那是过期注释：
  /// 生产调用点 MoveTargetDialog.vue:245-248 传的是 JSON 对象。以生产调用为准。
  /// dest_group_file_id 传 0 表示顶级目录。
  Future<void> moveFile({
    required dynamic groupFileId,
    required dynamic destGroupFileId,
  }) async {
    await _client.post('/file/move', data: {
      'group_file_id': groupFileId,
      'dest_group_file_id': destGroupFileId,
    });
  }
}

/// 递归给"子孙含启动项的文件夹"写聚合标记（移植 useDistributionFiles.js:111-126）。
/// 返回当前层是否含启动项（向上回报）。
bool markFolderStartup(List<V2File> nodes) {
  var hasAny = false;
  for (final n in nodes) {
    if (n.isFolder) {
      final childHas = markFolderStartup(n.children);
      if (childHas) {
        n.folderContainsStartup = true;
        hasAny = true;
      }
      // 保真移植：web 版文件夹自身的 is_startup 不向上回报（:111-126 原语义），不额外加分支
    } else if (n.isStartup) {
      hasAny = true;
    }
  }
  return hasAny;
}

/// refresh 后按 deliveryNodeId 序列在新树里还原目录路径
/// （移植 useDistributionFiles.js:75-85）。
/// 整棵树刷新会替换为新对象，不还原会把用户从子目录弹回根；
/// 中途某层已被删除/移走时，停在能到达的最深一层。
List<V2File> restorePath(V2File root, List<int?> keys) {
  final next = <V2File>[root];
  var level = root.children;
  for (final key in keys) {
    V2File? found;
    for (final n in level) {
      if (n.isFolder && n.deliveryPathKey == key) {
        found = n;
        break;
      }
    }
    if (found == null) break;
    next.add(found);
    level = found.children;
  }
  return next;
}
