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
    final data = response.data;
    // 解析 data.files，paginator.data 兜底（对齐 useZoneFiles.js:45）
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
