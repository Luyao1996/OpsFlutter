import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

/// 安全转换为 int（兼容后端返回 String 或 int）
int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v) ?? 0;
  if (v is double) return v.toInt();
  return 0;
}

/// 分组简要信息
class GroupBrief {
  final int id;
  final String name;

  GroupBrief({required this.id, required this.name});

  factory GroupBrief.fromJson(Map<String, dynamic> json) {
    return GroupBrief(
      id: _toInt(json['id']),
      name: json['name'] ?? '',
    );
  }
}

/// 用户简要信息
class UserBrief {
  final int id;
  final String nickname;

  UserBrief({required this.id, required this.nickname});

  factory UserBrief.fromJson(Map<String, dynamic> json) {
    return UserBrief(
      id: _toInt(json['id']),
      nickname: json['nickname'] ?? '',
    );
  }
}

/// 网吧/商户模型 - 适配后端字段
class Netbar {
  final int id;
  final String name;
  final String token; // 后端: token
  final int terminalCount; // 后端: terminal_count
  final int terminalAvg; // 后端: terminal_avg (近7日平均)
  final bool isOnline; // 后端: is_online
  final String? subdomain;
  final String? subdomainFull;
  final String? pinyin;
  final String? pinyinFull;
  final List<GroupBrief>? groups;
  final List<UserBrief>? users;
  final String? createdAt;
  final String? updatedAt;
  final NetbarRemoteStatus? remoteStatus;
  final String? screenshotUrl;
  final NetbarServerMetrics? serverMetrics;

  // 兼容旧代码的getter
  String get code => token;
  String get status => isOnline ? 'online' : 'offline';
  String get group => groups?.isNotEmpty == true ? groups!.first.name : '默认分组';
  String get admin => users?.isNotEmpty == true ? users!.first.nickname : '-';
  String get createTime => createdAt != null
      ? DateTime.tryParse(createdAt!)?.toLocal().toString().split(' ')[0] ?? '-'
      : '-';

  Netbar({
    required this.id,
    required this.name,
    required this.token,
    required this.terminalCount,
    required this.terminalAvg,
    required this.isOnline,
    this.subdomain,
    this.subdomainFull,
    this.pinyin,
    this.pinyinFull,
    this.groups,
    this.users,
    this.createdAt,
    this.updatedAt,
    this.remoteStatus,
    this.screenshotUrl,
    this.serverMetrics,
  });

  factory Netbar.fromJson(Map<String, dynamic> json) {
    return Netbar(
      id: _toInt(json['id']),
      name: json['name'] ?? '',
      token: json['token'] ?? '',
      terminalCount: _toInt(json['terminal_count'] ?? json['terminalCount']),
      terminalAvg: _toInt(json['terminal_avg']),
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      subdomain: json['subdomain'],
      subdomainFull: json['subdomain_full'],
      pinyin: json['pinyin'],
      pinyinFull: json['pinyin_full'],
      groups: (json['groups'] as List?)?.map((e) => GroupBrief.fromJson(e as Map<String, dynamic>)).toList(),
      users: (json['users'] as List?)?.map((e) => UserBrief.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      remoteStatus: json['remote_status'] != null
          ? NetbarRemoteStatus.fromJson(json['remote_status'] as Map<String, dynamic>)
          : null,
      screenshotUrl: json['screenshot_url'],
      serverMetrics: json['server_metrics'] != null
          ? NetbarServerMetrics.fromJson(json['server_metrics'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'token': token,
    'terminal_count': terminalCount,
    'terminal_avg': terminalAvg,
    'is_online': isOnline,
    'subdomain': subdomain,
    'subdomain_full': subdomainFull,
    'pinyin': pinyin,
    'pinyin_full': pinyinFull,
    'groups': groups?.map((g) => {'id': g.id, 'name': g.name}).toList(),
    'users': users?.map((u) => {'id': u.id, 'nickname': u.nickname}).toList(),
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (screenshotUrl != null) 'screenshot_url': screenshotUrl,
  };
}

/// 商户统计摘要
class NetbarSummary {
  final int onlineCount;
  final int offlineCount;

  NetbarSummary({required this.onlineCount, required this.offlineCount});

  factory NetbarSummary.fromJson(Map<String, dynamic> json) {
    return NetbarSummary(
      onlineCount: _toInt(json['online_count']),
      offlineCount: _toInt(json['offline_count']),
    );
  }
}

/// 商户列表响应
class NetbarListResponse {
  final List<Netbar> merchants;
  final List<GroupBrief> groups;
  final NetbarSummary? summary;
  final GroupBrief? currentGroup;

  NetbarListResponse({
    required this.merchants,
    required this.groups,
    this.summary,
    this.currentGroup,
  });

  factory NetbarListResponse.fromJson(Map<String, dynamic> json) {
    return NetbarListResponse(
      merchants: (json['merchants'] as List?)?.map((e) => Netbar.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      groups: (json['groups'] as List?)?.map((e) => GroupBrief.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      summary: json['summary'] != null ? NetbarSummary.fromJson(json['summary']) : null,
      currentGroup: json['group'] != null ? GroupBrief.fromJson(json['group']) : null,
    );
  }
}

// 以下保留原有类定义以兼容旧代码
class NetbarServerMetrics {
  final int cpuUsage;
  final int ramUsage;
  final int diskUsage;
  final int networkUp;
  final int networkDown;

  NetbarServerMetrics({
    required this.cpuUsage,
    required this.ramUsage,
    required this.diskUsage,
    required this.networkUp,
    required this.networkDown,
  });

  factory NetbarServerMetrics.fromJson(Map<String, dynamic> json) {
    return NetbarServerMetrics(
      cpuUsage: _toInt(json['cpuUsage']),
      ramUsage: _toInt(json['ramUsage']),
      diskUsage: _toInt(json['diskUsage']),
      networkUp: _toInt(json['networkUp']),
      networkDown: _toInt(json['networkDown']),
    );
  }
}

class NetbarAlert {
  final String type;
  final int count;
  final String message;

  NetbarAlert({required this.type, required this.count, required this.message});

  factory NetbarAlert.fromJson(Map<String, dynamic> json) {
    return NetbarAlert(
      type: json['type'] ?? '',
      count: _toInt(json['count']),
      message: json['message'] ?? '',
    );
  }
}

class NetbarRemoteStatus {
  final bool isActive;
  final String? currentOperator;
  final NetbarLastSession? lastSession;

  NetbarRemoteStatus({required this.isActive, this.currentOperator, this.lastSession});

  factory NetbarRemoteStatus.fromJson(Map<String, dynamic> json) {
    return NetbarRemoteStatus(
      isActive: json['isActive'] ?? false,
      currentOperator: json['currentOperator'],
      lastSession: json['lastSession'] != null
          ? NetbarLastSession.fromJson(json['lastSession'])
          : null,
    );
  }
}

class NetbarLastSession {
  final String time;
  final String operator;
  final String? reason;

  NetbarLastSession({required this.time, required this.operator, this.reason});

  factory NetbarLastSession.fromJson(Map<String, dynamic> json) {
    return NetbarLastSession(
      time: json['time'] ?? '-',
      operator: json['operator'] ?? '-',
      reason: json['reason'],
    );
  }
}

/// 网吧/商户 API
class NetbarApi {
  final ApiClient _client = ApiClient.instance;

  /// 获取商户列表（完整响应）
  Future<NetbarListResponse> getListFull({
    String? keyword,
    int? groupId,
    bool? isOnline,
  }) async {
    final params = <String, dynamic>{};
    if (keyword != null && keyword.isNotEmpty) params['keyword'] = keyword;
    if (groupId != null) params['group_id'] = groupId;
    if (isOnline != null) params['is_online'] = isOnline ? '1' : '0';

    final response = await _client.get('/merchant', queryParameters: params);
    return NetbarListResponse.fromJson(response.data ?? {});
  }

  /// 获取商户列表（简化版，兼容旧代码）
  Future<List<Netbar>> getList({
    String? keyword,
    int? groupId,
    bool? isOnline,
  }) async {
    final fullResponse = await getListFull(
      keyword: keyword,
      groupId: groupId,
      isOnline: isOnline,
    );
    return fullResponse.merchants;
  }

  /// 通过 subdomain 查询商户（用于终端详情页获取所属网吧信息）
  Future<Netbar?> getBySubdomain(String subdomain) async {
    try {
      final response = await _client.get('/merchant', queryParameters: {'subdomain': subdomain});
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final merchants = data['merchants'] as List?;
        if (merchants != null && merchants.isNotEmpty) {
          return Netbar.fromJson(merchants[0] as Map<String, dynamic>);
        }
      }
    } catch (_) {}
    return null;
  }

  /// 获取商户详情
  Future<Netbar> getById(int id) async {
    final response = await _client.get('/merchant/$id');
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('merchant')) {
      return Netbar.fromJson(data['merchant']);
    }
    return Netbar.fromJson(data ?? {});
  }

  /// 创建商户
  Future<Netbar> create(Map<String, dynamic> data) async {
    final response = await _client.post('/merchant', data: data);
    return Netbar.fromJson(response.data ?? {});
  }

  /// 更新商户
  Future<Netbar> update(int id, Map<String, dynamic> data) async {
    final response = await _client.put('/merchant/$id', data: data);
    return Netbar.fromJson(response.data ?? {});
  }

  /// 删除商户
  Future<void> delete(int id) async {
    await _client.delete('/merchant/$id');
  }

  /// 设置商户登录密码
  Future<void> setPassword(int id, {required String password, bool reset = false}) async {
    await _client.post('/merchant/setPwd/$id', data: {
      'password': password,
      'reset': reset ? '1' : '0',
    });
  }

  /// 批量清除商户Windows登录密码（FormData 格式，与 Vue 端对齐）
  Future<void> clearAllPasswords({required List<int> merchantIds}) async {
    final formData = FormData();
    for (final id in merchantIds) {
      formData.fields.add(MapEntry('merchant_ids[]', id.toString()));
    }
    await _client.post('/merchant/clearAllPwd', data: formData);
  }

  /// 批量重置商户Windows登录密码（使用小组默认密码）
  Future<void> resetAllPasswords({required List<int> merchantIds}) async {
    final formData = FormData();
    for (final id in merchantIds) {
      formData.fields.add(MapEntry('merchant_ids[]', id.toString()));
    }
    formData.fields.add(const MapEntry('reset', '0'));
    await _client.post('/merchant/resetAllPwd', data: formData);
  }

  /// 批量更新程序
  Future<void> batchProgramUpdate({required List<int> merchantIds}) async {
    final formData = FormData();
    for (final id in merchantIds) {
      formData.fields.add(MapEntry('merchant_ids[]', id.toString()));
    }
    await _client.post('/socket/programBatch', data: formData);
  }

  /// 生成超级密码（TOTP）
  /// [time] 格式: "YYYY-MM-DD HH:mm:ss"
  Future<String> generateTotp({required String time}) async {
    final response = await _client.get('/merchant/totp', queryParameters: {'time': time});
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('totp')) {
      return data['totp'].toString();
    }
    return '';
  }

  /// 下载商户配置（返回下载URL）
  String getDownloadUrl(int id) {
    return '${_client.dio.options.baseUrl}/merchant/down/$id';
  }
}
