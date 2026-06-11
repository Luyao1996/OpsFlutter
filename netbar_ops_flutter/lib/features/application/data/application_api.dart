import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import 'application_models.dart';

/// 应用中心 / 应用策略 API。
/// 路由与 multipart 字段名逐一对齐 toolboxPage src/api/application.js；
/// 后端 {code,message,data} 外壳已由 ApiClient 拦截器剥除，失败抛 ApiError。
class ApplicationApi {
  final ApiClient _client = ApiClient.instance;

  void _log(String level, String operType, String contextId, String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts][$level][application][$operType][$contextId] $msg');
  }

  // ===== 应用中心（分类 / 应用库 / 引用） =====

  /// 应用分类列表（应用分类固定 type=1，只取启用）
  Future<List<AppCategory>> listCategories() async {
    final res = await _client.get(
      '/application-category',
      queryParameters: {'type': '1', 'status': '1'},
    );
    return extractList(res.data, preferKeys: ['categories'])
        .map(AppCategory.fromJson)
        .toList();
  }

  /// 应用库列表（全部/按分类/搜索，分页）。
  /// 返回 (list, total)，list 为原始 JSON，由调用方结合 addedMap 构建卡片项。
  Future<(List<Map<String, dynamic>>, int)> listApplications({
    required int page,
    required int size,
    int? categoryId,
    String? keyword,
  }) async {
    final res = await _client.get('/application', queryParameters: {
      'page': page,
      'size': size,
      if (categoryId != null) 'category_id': categoryId,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
    });
    final list = extractList(res.data, preferKeys: ['applications']);
    return (list, extractTotal(res.data, list.length));
  }

  /// 已引用应用列表（某分组已添加，分页；嵌套 application）
  Future<(List<Map<String, dynamic>>, int)> listReferences({
    required int groupId,
    required int page,
    required int size,
    String? keyword,
  }) async {
    final res = await _client.get('/application-reference', queryParameters: {
      'group_id': groupId,
      'page': page,
      'size': size,
      if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
    });
    final list = extractList(res.data, preferKeys: ['references']);
    return (list, extractTotal(res.data, list.length));
  }

  /// 添加引用：把应用加到分组（multipart）。返回新引用记录 id（取不到为 null）。
  Future<int?> addReference({
    required int groupId,
    required int applicationId,
  }) async {
    _log('INFO', 'addReference', 'group:$groupId', 'application_id=$applicationId');
    final fd = FormData()
      ..fields.add(MapEntry('group_id', '$groupId'))
      ..fields.add(MapEntry('application_id', '$applicationId'));
    final res = await _client.post('/application-reference', data: fd);
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final direct = data['id'];
      if (direct is int) return direct;
      final ref = data['reference'];
      if (ref is Map && ref['id'] is int) return ref['id'] as int;
    }
    return null;
  }

  /// 取消添加（删除引用记录）
  Future<void> deleteReference(int refId) async {
    _log('INFO', 'deleteReference', 'ref:$refId', 'delete');
    await _client.delete('/application-reference/$refId');
  }

  // ===== 应用版本 =====

  /// 应用版本列表（策略弹窗版本下拉）
  Future<List<AppVersion>> listVersions(int applicationId) async {
    final res = await _client.get('/application/$applicationId/versions');
    return extractList(res.data, preferKeys: ['versions'])
        .map(AppVersion.fromJson)
        .toList();
  }

  // ===== 策略区域（生效机号） =====

  /// 网吧区域列表（某网吧+应用可选的机号区域）
  Future<List<PolicyArea>> listAreas({
    int? groupId,
    required int merchantId,
    required int applicationId,
  }) async {
    final res = await _client.get('/application-policy/areas', queryParameters: {
      if (groupId != null) 'group_id': groupId,
      'merchant_id': merchantId,
      'application_id': applicationId,
    });
    return extractList(res.data, preferKeys: ['areas'])
        .map(PolicyArea.fromJson)
        .toList();
  }

  /// 区域增改共用 multipart：area 用带索引的数组键 area[0]、area[1]
  FormData _buildAreaFormData({
    required int? groupId,
    required int merchantId,
    required int applicationId,
    required List<String> area,
  }) {
    final fd = FormData()
      ..fields.add(MapEntry('group_id', groupId == null ? '' : '$groupId'))
      ..fields.add(MapEntry('merchant_id', '$merchantId'))
      ..fields.add(MapEntry('application_id', '$applicationId'));
    for (var i = 0; i < area.length; i++) {
      if (area[i].isNotEmpty) fd.fields.add(MapEntry('area[$i]', area[i]));
    }
    return fd;
  }

  /// 新增区域。返回响应原始 data（含 area_key，调用方用于定位选中项）。
  Future<Map<String, dynamic>?> addArea({
    int? groupId,
    required int merchantId,
    required int applicationId,
    required List<String> area,
  }) async {
    _log('INFO', 'addArea', 'merchant:$merchantId', 'area=${area.join(",")}');
    final res = await _client.post(
      '/application-policy/areas',
      data: _buildAreaFormData(
        groupId: groupId,
        merchantId: merchantId,
        applicationId: applicationId,
        area: area,
      ),
    );
    return res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : null;
  }

  /// 编辑区域（POST /xxx/{id}，项目惯例）
  Future<Map<String, dynamic>?> updateArea(
    int areaId, {
    int? groupId,
    required int merchantId,
    required int applicationId,
    required List<String> area,
  }) async {
    _log('INFO', 'updateArea', 'area:$areaId', 'area=${area.join(",")}');
    final res = await _client.post(
      '/application-policy/areas/$areaId',
      data: _buildAreaFormData(
        groupId: groupId,
        merchantId: merchantId,
        applicationId: applicationId,
        area: area,
      ),
    );
    return res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : null;
  }

  /// 删除区域
  Future<void> deleteArea(int areaId) async {
    _log('INFO', 'deleteArea', 'area:$areaId', 'delete');
    await _client.delete('/application-policy/areas/$areaId');
  }

  /// 按区域取策略参数（回填右侧表单）。无策略时返回 null。
  Future<Map<String, dynamic>?> getPolicyByArea({
    int? groupId,
    required int merchantId,
    required int applicationId,
    required int areaId,
  }) async {
    final res = await _client.get('/application-policy/by-area', queryParameters: {
      if (groupId != null) 'group_id': groupId,
      'merchant_id': merchantId,
      'application_id': applicationId,
      'area_id': areaId,
    });
    final data = res.data;
    if (data is Map<String, dynamic> && data['policy'] is Map<String, dynamic>) {
      return data['policy'] as Map<String, dynamic>;
    }
    return null;
  }

  // ===== 策略新建 / 更新 =====

  /// 策略 multipart 构造，嵌套键对齐 application.js buildPolicyFormData：
  ///   strategy[mode] / period[i][start] / merchants[i][merchant_id] /
  ///   feature_config（JSON 字符串）/ area_id；布尔转 '1'/'0'；
  ///   period 为空默认全天 00:00:00~23:59:59（对齐 buildPolicyData）。
  FormData _buildPolicyFormData(PolicyPayload p) {
    final fd = FormData();
    void add(String k, String v) => fd.fields.add(MapEntry(k, v));

    if (p.groupId != null) add('group_id', '${p.groupId}');
    add('application_id', '${p.applicationId}');
    add('application_version_id', '${p.versionId}');
    if (p.parameter.isNotEmpty) add('parameter', p.parameter);
    add('strategy[mode]', '${p.strategyMode}');
    final periods = p.period.isNotEmpty
        ? p.period
        : const [PolicyPeriod(start: '00:00:00', end: '23:59:59')];
    for (var i = 0; i < periods.length; i++) {
      add('period[$i][start]', periods[i].start);
      add('period[$i][end]', periods[i].end);
    }
    add('delay', '${p.delay}');
    add('is_random_name', p.isRandomName ? '1' : '0');
    add('is_forced_on', p.isForcedOn ? '1' : '0');
    add(
      'feature_config',
      jsonEncode(p.server.isNotEmpty
          ? {'systems': p.systems, 'server': p.server}
          : {'systems': p.systems}),
    );
    add('status', '1');
    for (var i = 0; i < p.merchantIds.length; i++) {
      add('merchants[$i][merchant_id]', '${p.merchantIds[i]}');
    }
    if (p.areaId != null) add('area_id', '${p.areaId}');
    return fd;
  }

  /// 策略新增
  Future<void> createPolicy(PolicyPayload payload) async {
    _log('INFO', 'createPolicy', 'app:${payload.applicationId}',
        'merchants=${payload.merchantIds} area=${payload.areaId}');
    await _client.post('/application-policy', data: _buildPolicyFormData(payload));
  }

  /// 策略编辑（路径用 application_id，body 带 area_id 定位区域）
  Future<void> updatePolicy(PolicyPayload payload) async {
    _log('INFO', 'updatePolicy', 'app:${payload.applicationId}',
        'merchants=${payload.merchantIds} area=${payload.areaId}');
    await _client.post(
      '/application-policy/${payload.applicationId}',
      data: _buildPolicyFormData(payload),
    );
  }

  // ===== 服务端选择 =====

  /// 网吧的服务器终端（策略「服务端」选择），mode=1,2 主/副服务器。
  /// 对齐 application.js getTerminals(merchantId, '1,2')。
  Future<List<ServerTerminal>> getServerTerminals(int merchantId) async {
    final res = await _client.get('/terminals', queryParameters: {
      'merchant_id': merchantId,
      'mode': '1,2',
    });
    return extractList(res.data).map(ServerTerminal.fromJson).toList();
  }
}
