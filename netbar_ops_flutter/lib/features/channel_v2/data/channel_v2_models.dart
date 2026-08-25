/// ChannelV2 数据模型：资源区（/file/view）与下发区（/delivery/tree）共用基座。
///
/// 字段第一天即全量预埋：后续阶段（文件操作/策略/启动项）直接挂在本模型上，
/// 避免中途改模型引发的全链路波及。
library;

/// 布尔四态 truthy 解析（对齐 web useZoneFiles.js:61 `_truthy`：
/// 后端不同接口对布尔的序列化不统一，true/1/'1'/'true' 都可能出现）
bool v2Truthy(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String _toStr(dynamic v) => v == null ? '' : v.toString();

/// V2 文件/文件夹/下发节点统一模型。
class V2File {
  /// 源文件 id（group_files.id）。下发树的合成根节点为 null。
  final int? id;
  final String name;
  final bool isFolder;
  final int? size;
  final String? hash;
  final String? updateTime;

  /// 文件自身的启动项标记（is_startup）
  final bool isStartup;
  final bool isHide;

  /// 下发节点专属：源文件已被删除（missing 红显）
  final bool missing;

  /// 下发节点专属：继承自上级 scope（如总部下发给小组），本级只读
  final bool inherited;

  /// 下发节点专属：delivery_nodes.id（删除/移动接口用；资源区文件为 null）
  final int? deliveryNodeId;

  /// 下发节点来源：'hq' | 'group' | 'merchant'（资源区文件为空串）
  final String sourceScope;
  final int? sourceId;
  final String sourceName;

  /// 资源文件归属组（下发节点对齐 web useDistributionFiles.js:155 用 source_id 充当）
  final int? groupId;
  final String groupName;

  /// 上传者昵称（资源区）/来源名（下发区），驱动 badge-nickname 蓝色徽标
  final String nickname;

  /// 派生角标类型：'headquarters' | null。
  /// 资源区按 group_id==0（对齐 useZoneFiles.js:68），
  /// 下发区按 source_scope=='hq'（对齐 useDistributionFiles.js:149）。
  final String? adminType;

  /// 下发树嵌套子节点（资源区文件恒为空列表，目录内容靠再次请求 /file/view）
  final List<V2File> children;

  /// 后处理标记：文件夹的子孙中含启动项（markFolderStartup 递归写入）。
  /// 与 isStartup 分离：isStartup 是节点自身标记，此字段是聚合展示位。
  bool folderContainsStartup;

  /// 原始 JSON（后续阶段属性弹窗/调试需要未裁剪字段）
  final Map<String, dynamic>? raw;

  V2File({
    required this.id,
    required this.name,
    required this.isFolder,
    this.size,
    this.hash,
    this.updateTime,
    this.isStartup = false,
    this.isHide = false,
    this.missing = false,
    this.inherited = false,
    this.deliveryNodeId,
    this.sourceScope = '',
    this.sourceId,
    this.sourceName = '',
    this.groupId,
    this.groupName = '',
    this.nickname = '',
    this.adminType,
    this.children = const [],
    this.folderContainsStartup = false,
    this.raw,
  });

  /// 列表/选中键。
  /// 【对 web 的刻意偏离，留痕】web 下发区用源 id（useZoneSelection 直接 file.id）
  /// 做选中键——同一文件被下发两次、或"继承+直发"并存时源 id 会撞键，
  /// 多选/高亮会串到另一个节点。这里改为 delivery_id 兜底复合键：
  /// 下发节点键 = deliveryNodeId 非空用它、否则退回源 id；前缀区分两个 id 空间。
  String get selectionKey =>
      deliveryNodeId != null ? 'd:$deliveryNodeId' : 'f:$id';

  /// 下发树路径还原用键：delivery_id ?? id（对齐 useDistributionFiles.js:42,79）
  int? get deliveryPathKey => deliveryNodeId ?? id;

  /// **源** group_files.id 的语义别名。
  ///
  /// 【命名陷阱，第一天定死】`id` 在两个 id 空间里都出现过，读代码时极易搞混：
  ///   - 资源区文件：id = group_files.id（源文件）
  ///   - 下发节点：  id = group_files.id（源文件），deliveryNodeId = delivery_nodes.id
  /// 凡是喂给 /file/* 系列（destroy/rename/extract/hide/move/attribute）的必须是本字段；
  /// 凡是喂给 /delivery/* 系列（DELETE /delivery/{id}、POST /delivery/move）的必须是
  /// [deliveryNodeId]，且**禁止 `deliveryNodeId ?? id` 兜底**——两个 id 空间会串，
  /// 把源文件 id 当下发节点 id 发出去会删掉别人的下发记录（见 v2FileActions 内的拒绝分支）。
  int? get groupFileId => id;

  String get extension {
    final idx = name.lastIndexOf('.');
    if (idx <= 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  /// 「启」角标是否显示：文件看自身 isStartup，
  /// 文件夹看自身或子孙聚合（tooltip 文案对齐 web："包含启动项"/"开机启动"）
  bool get showStartupBadge =>
      isFolder ? (isStartup || folderContainsStartup) : isStartup;

  /// /file/view 资源文件解析（对齐 useZoneFiles.js `_normalizeFile`）
  factory V2File.fromResourceJson(Map<String, dynamic> json) {
    final groupId = _toIntOrNull(json['group_id']);
    final user = json['user'];
    final nickname =
        user is Map<String, dynamic> ? _toStr(user['nickname']) : '';
    final group = json['group'];
    return V2File(
      id: _toIntOrNull(json['id']),
      name: _toStr(json['name']),
      isFolder: v2Truthy(json['is_folder']),
      size: _toIntOrNull(json['size']),
      hash: json['hash']?.toString(),
      updateTime: (json['updated_at'] ?? json['update_time'])?.toString(),
      isStartup: v2Truthy(json['is_startup']),
      isHide: v2Truthy(json['is_hide']),
      groupId: groupId,
      groupName: group is Map<String, dynamic>
          ? _toStr(group['name'])
          : _toStr(json['group_name']),
      nickname: nickname,
      // 与老代码完全一致：仅 group_id==0 设 'headquarters'；
      // 分组文件保持 null，靠 nickname 走蓝色徽标（useZoneFiles.js:66-68）
      adminType: groupId == 0 ? 'headquarters' : null,
      raw: json,
    );
  }

  /// /delivery/tree 下发节点解析（对齐 useDistributionFiles.js `_normalizeNode`，
  /// 递归带 children）
  factory V2File.fromDeliveryJson(Map<String, dynamic> json) {
    final isFolder = v2Truthy(json['is_folder']) || json['type'] == 'folder';
    final sourceScope = _toStr(json['source_scope']);
    final sourceId = _toIntOrNull(json['source_id']);
    final sourceName = _toStr(json['source_name']);
    return V2File(
      id: _toIntOrNull(json['id']),
      name: _toStr(json['name']),
      isFolder: isFolder,
      size: _toIntOrNull(json['size']),
      hash: json['hash']?.toString(),
      updateTime: (json['updated_at'] ?? json['update_time'])?.toString(),
      isStartup: v2Truthy(json['is_startup']),
      isHide: v2Truthy(json['is_hide']),
      missing: v2Truthy(json['missing']),
      inherited: v2Truthy(json['inherited']),
      deliveryNodeId: _toIntOrNull(json['delivery_node_id']),
      sourceScope: sourceScope,
      sourceId: sourceId,
      sourceName: sourceName,
      // 对齐 useDistributionFiles.js:155-157：group_id/group_name/nickname
      // 复用来源信息，让下发区与资源区共用同一套角标/权限判定
      groupId: sourceId,
      groupName: sourceName,
      nickname: sourceName,
      adminType: sourceScope == 'hq' ? 'headquarters' : null,
      children: (json['children'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(V2File.fromDeliveryJson)
              .toList() ??
          const [],
      raw: json,
    );
  }

  /// 下发树合成根节点（面包屑 path[0]；对齐 useDistributionFiles.js:56-60）
  factory V2File.deliveryRoot({required String name, required List<V2File> children}) {
    return V2File(id: null, name: name, isFolder: true, children: children);
  }
}

/// 资源区面包屑路径项：根目录用 {id: null, name: zoneLabel}
/// （对齐 useZoneFiles.js:20）
class ZonePathItem {
  final int? id;
  final String name;
  const ZonePathItem({required this.id, required this.name});
}

/// 下发区左树选中的 scope 节点。
/// 复合 key：'hq' | 'group-{gid}' | 'group-{gid}-merchant-{mid}'
/// （多组归属的网吧在每个组下各现一次，对齐 useDistributionTree.js:106-127）
class DistributionScope {
  final String key;

  /// 'hq' | 'group' | 'merchant'
  final String type;
  final String scopeType;
  final String scopeId;
  final String name;

  const DistributionScope({
    required this.key,
    required this.type,
    required this.scopeType,
    required this.scopeId,
    required this.name,
  });
}

/// 文件属性（GET /file/attribute → data.userFile）轻模型。
///
/// 【字段陷阱，留痕】隐藏标记在本接口叫 `hidden`，在列表接口 /file/view 叫
/// `is_hide`（V2File.isHide）；两者不可互相套用，否则属性弹窗的隐藏开关恒为关。
/// 对齐 web FilePropsDialog.vue:112-128。
class V2FileAttribute {
  final String name;
  final bool isFolder;

  /// 体积取 userFile.file.size（属性接口把物理文件信息挂在嵌套 file 上）
  final int? size;

  /// 上传者昵称：userFile.user.nickname
  final String uploader;
  final String createdAt;
  final String updatedAt;
  final bool hidden;
  final Map<String, dynamic> raw;

  const V2FileAttribute({
    required this.name,
    required this.isFolder,
    this.size,
    this.uploader = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.hidden = false,
    this.raw = const {},
  });

  factory V2FileAttribute.fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    final user = json['user'];
    return V2FileAttribute(
      name: _toStr(json['name']),
      isFolder: v2Truthy(json['is_folder']),
      size: file is Map<String, dynamic>
          ? _toIntOrNull(file['size'])
          : _toIntOrNull(json['size']),
      uploader: user is Map<String, dynamic> ? _toStr(user['nickname']) : '',
      createdAt: _toStr(json['created_at']),
      updatedAt: _toStr(json['updated_at']),
      hidden: v2Truthy(json['hidden']),
      raw: json,
    );
  }
}

// ===========================================================================
// 任务列表（T8d，对齐 web dialogs/TaskListDialog.vue）
// ===========================================================================

/// 后台任务（GET /task 的 paginator.data 元素）。
///
/// 目前后端只投递一种任务：type=100「文件解压缩」（/file/extract 的异步产物）。
class V2Task {
  /// 任务 id：web 列宽给到 300 且 show-overflow-tooltip，判定为长字符串（uuid 类），
  /// 因此**不解析成 int**，原样保留字符串。
  final String id;

  /// 任务类型码；未知码原样显示数字（对齐 web getTypeName 的 `map[type] || type`）
  final int? type;
  final String name;

  /// 0=等待中 1=解压中 2=成功 3=失败
  final int? status;

  /// 执行次数（后端 attempt）
  final int? attempt;

  /// 失败原因：仅 status==3 时后端才填，UI 用 tooltip 展示（web:19-30）
  final String message;
  final String createdAt;
  final String updatedAt;

  const V2Task({
    required this.id,
    this.type,
    this.name = '',
    this.status,
    this.attempt,
    this.message = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory V2Task.fromJson(Map<String, dynamic> json) => V2Task(
        id: _toStr(json['id']),
        type: _toIntOrNull(json['type']),
        name: _toStr(json['name']),
        status: _toIntOrNull(json['status']),
        attempt: _toIntOrNull(json['attempt']),
        message: _toStr(json['message']),
        createdAt: _toStr(json['created_at']),
        updatedAt: _toStr(json['updated_at']),
      );
}

/// GET /task 的分页结果壳（对齐 strategy 侧 TacticListResult 的写法）
class V2TaskPage {
  final List<V2Task> items;
  final int total;
  final int currentPage;
  final int perPage;

  const V2TaskPage({
    required this.items,
    required this.total,
    this.currentPage = 1,
    this.perPage = 20,
  });

  static const empty = V2TaskPage(items: [], total: 0);
}
