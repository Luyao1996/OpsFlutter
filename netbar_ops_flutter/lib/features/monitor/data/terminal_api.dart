import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/dio_helper.dart';
import '../../../core/network/task_ws.dart';
import '../../../core/storage/token_store.dart';
import 'terminal_mock_data.dart';
import 'terminal_models.dart';

export 'terminal_models.dart';

/// Terminal API 服务
///
/// 三类调用形态共存：
/// 1. 中央 HTTP（座位列表）：走 [_client] /terminals
/// 2. WebSocket 任务通道（remote/updateProgram 等）：走 [_ws]
/// 3. 各网吧 frp 直连 HTTP（进程/文件/WOL 等红线方法）：仍走自建 Dio + domain 参数
class TerminalApi {
  final ApiClient _client = ApiClient.instance;
  final TaskWs _ws;

  TerminalApi(this._ws);

  /// 构造网吧域名的完整 API URL
  /// domain 示例: "xxx.frps.wwls.net"
  /// path 示例: "/seatlist"
  /// 结果: "https://xxx.frps.wwls.net/api/seatlist"
  String _buildUrl(String domain, String path) {
    String d = domain.trim();
    if (!d.startsWith('http://') && !d.startsWith('https://')) {
      d = 'https://$d';
    }
    d = d.replaceAll(RegExp(r'/+$'), '');
    return '$d/api$path';
  }

  /// 创建 Dio 实例（带统一日志拦截器 + SSL 证书旁路 + 60s 超时）
  Dio _createProxiedDio() {
    final dio = createDio(BaseOptions(
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
    ));

    // 配置 SSL 证书校验（允许自签名证书）
    if (!kIsWeb) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // 不使用代理
        client.findProxy = (uri) => 'DIRECT';
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }

    return dio;
  }

  /// 向网吧域名发起 GET 请求（带 Token）
  Future<Response> _netbarGet(String domain, String path, {Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();
    final dio = _createProxiedDio();

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Host': domain.trim(),
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      return response;
    } on DioException catch (e) {
      throw _wrapDioError(e);
    } finally {
      dio.close();
    }
  }

  /// 向网吧域名发起 POST 请求（带 Token）
  Future<Response> _netbarPost(String domain, String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    final url = _buildUrl(domain, path);
    final token = TokenStore.getToken();
    final dio = _createProxiedDio();

    final headers = {
      'Content-Type': 'application/json',
      'Host': domain.trim(),
      if (token != null) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return response;
    } on DioException catch (e) {
      throw _wrapDioError(e);
    } finally {
      dio.close();
    }
  }

  /// 将 Dio 超时/连接异常转为友好的 ApiError
  Object _wrapDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return ApiError(code: e.response?.statusCode, message: '服务器繁忙，请稍后再试', raw: e);
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiError(code: e.response?.statusCode, message: '网络连接失败，请检查网络', raw: e);
    }
    return e;
  }

  /// 解包网吧后端响应 {code, msg, data}
  /// 注意：ApiClient 的拦截器可能已经解包过，此方法需要兼容两种情况
  dynamic _unwrapResponse(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('code')) {
        final code = raw['code'];
        final isValidCode = code is int ||
            (code is String && int.tryParse(code) != null);
        if (isValidCode) {
          if (code == 0 || code == '0' || code == 200) {
            return raw['data'] ?? raw;
          }
          final msg = raw['msg'] ?? raw['message'] ?? '请求失败';
          throw ApiError(code: code, message: msg.toString(), raw: raw);
        }
      }
      return raw;
    }
    return raw;
  }

  /// 判断是否应该返回空列表（而非抛出异常）
  /// 包括：404、CORS 错误、网络错误等
  bool _shouldReturnEmpty(Object e) {
    // Dio 错误
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 404 || statusCode == 405 || statusCode == 501) return true;
      // CORS 预检失败通常表现为网络错误
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown) return true;
    }
    // ApiError
    if (e is ApiError) {
      final code = e.code ?? 0;
      if (code == 404 || code == 405 || code == 501) return true;
      final msg = e.message.toLowerCase();
      if (msg.contains('not found') || msg.contains('no route')) return true;
    }
    // 其他错误
    final msg = e.toString().toLowerCase();
    return msg.contains('404') || msg.contains('not found') ||
           msg.contains('no route') || msg.contains('cors') ||
           msg.contains('xmlhttprequest');
  }

  /// 获取所有终端（座位列表）—— 走中央 HTTP `GET /terminals?merchant_id=X`。
  /// 拦截器已剥外壳，[ApiClient.get] 返回的 res.data 即后端 data 字段值。
  Future<List<Terminal>> getAll({required int merchantId}) async {
    try {
      final response = await _client.get(
        '/terminals',
        queryParameters: {'merchant_id': merchantId},
      );
      final data = response.data;

      List<Map<String, dynamic>> list = [];
      if (data is List) {
        list = data.whereType<Map<String, dynamic>>().toList();
      } else if (data is Map<String, dynamic>) {
        // 兼容对象返回：{ "PC001": {...}, "PC002": {...} }
        for (final entry in data.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            final deviceType = entry.key == 'ServerChannel' ? 'server' : 'client';
            list.add({'id': entry.key, 'type': deviceType, ...val});
          }
        }
      }

      return list.map((e) => Terminal.fromJson(e)).toList();
    } catch (e) {
      if (_shouldReturnEmpty(e)) return [];
      rethrow;
    }
  }

  /// 获取单个终端（通过座位列表查找）
  Future<Terminal> getById(int id, {required int merchantId}) async {
    final terminals = await getAll(merchantId: merchantId);
    return terminals.firstWhere(
      (t) => t.id == id,
      orElse: () {
        throw ApiError(code: 404, message: '终端不存在');
      },
    );
  }

  /// 远程操作（远程连接 / 断开）—— 走 WebSocket 任务通道。
  /// [action] = 'control' / 'view' / 'webrtc' 时建立连接（enable=true）；
  /// [action] = 'disconnect' 时断开（enable=false）。
  Future<Map<String, dynamic>> remote(
    String seatId,
    String action, {
    required int merchantId,
    Map<String, dynamic>? user,
  }) async {
    final res = await _ws.request(
      fun: 'remote',
      seat: seatId,
      merchantId: merchantId,
      data: {
        'enable': action != 'disconnect',
        // 断开时不传 type；开启时才带（与 toolboxPage useRemoteAwaken.js:183 对齐）
        if (action != 'disconnect') 'type': action,
        if (user != null) 'user': user,
      },
    );
    if (res is Map) {
      final code = res['code'];
      if (code != null && code != 0 && code != '0') {
        throw ApiError(
          code: code is int ? code : int.tryParse(code.toString()),
          message: (res['msg'] ?? res['message'] ?? '远程失败').toString(),
          raw: res,
        );
      }
      // 剥业务包装层，返回 data 字段本身（含 mark/type/...），与旧 frp 行为对齐。
      // 服务端响应：{code, msg, data:{type, mark, ...}, fun} → 调用方拿到的是 {type, mark, ...}
      final data = res['data'];
      return data is Map ? Map<String, dynamic>.from(data) : {};
    }
    return {};
  }

  /// 触发远端机器更新自身程序 —— 走 WebSocket。
  /// 参考 toolboxPage `useRemoteAwaken.js:224 updateProgram`。
  Future<void> updateProgram(String seatId, {required int merchantId}) async {
    final res = await _ws.request(
      fun: 'update',
      seat: seatId,
      merchantId: merchantId,
      data: const {},
    );
    if (res is Map) {
      final code = res['code'];
      if (code != null && code != 0 && code != '0') {
        throw ApiError(
          code: code is int ? code : int.tryParse(code.toString()),
          message: (res['msg'] ?? res['message'] ?? '更新程序失败').toString(),
          raw: res,
        );
      }
    }
  }

  /// 获取终端心跳/实时状态（通过 /terminals 获取 online 状态）
  Future<Terminal> getHeartbeat(int id, {required int merchantId}) async {
    try {
      return await getById(id, merchantId: merchantId);
    } catch (e) {
      if (_shouldReturnEmpty(e)) {
        return Terminal(
          id: id, name: '', code: '', netbarId: 0, ip: '', mac: '', os: '',
          type: 'client', status: 0, cpuUsage: 0, ramUsage: 0, gpuUsage: 0,
          diskUsage: 0, uptime: '0天',
        );
      }
      rethrow;
    }
  }

  /// 获取进程列表（平面列表，兼容旧版）—— 走 WebSocket（fun:'processTree'）。
  Future<List<TerminalProcess>> getProcesses(String seatId, {required int merchantId}) async {
    try {
      final res = await _ws.request(
        fun: 'processTree',
        seat: seatId,
        merchantId: merchantId,
        data: const {},
      );
      final data = _extractWsBusinessData(res);
      if (data == null) return [];
      // 后端返回嵌套的进程树，展平为列表
      return _flattenProcessTree(data);
    } catch (e) {
      if (_shouldReturnEmpty(e)) return TerminalMockData.processes(seatId.hashCode);
      rethrow;
    }
  }

  /// 获取进程树（保持树形结构）—— 走 WebSocket（fun:'processTree'）。
  Future<List<TerminalProcess>> getProcessTree(String seatId, {required int merchantId}) async {
    try {
      final res = await _ws.request(
        fun: 'processTree',
        seat: seatId,
        merchantId: merchantId,
        data: const {},
      );
      final data = _extractWsBusinessData(res);
      if (data == null) return [];
      return _parseProcessTree(data);
    } catch (e) {
      if (_shouldReturnEmpty(e)) return [];
      rethrow;
    }
  }

  /// 解析进程树（保持层级结构）
  List<TerminalProcess> _parseProcessTree(Map<String, dynamic> tree) {
    final result = <TerminalProcess>[];
    for (final entry in tree.entries) {
      final proc = entry.value;
      if (proc is Map<String, dynamic>) {
        result.add(TerminalProcess.fromProcessTree(proc, entry.key));
      }
    }
    // 按 PID 排序
    result.sort((a, b) => a.pid.compareTo(b.pid));
    return result;
  }

  /// 展平进程树（兼容旧版）
  List<TerminalProcess> _flattenProcessTree(Map<String, dynamic> tree) {
    final result = <TerminalProcess>[];
    for (final entry in tree.entries) {
      final proc = entry.value;
      if (proc is Map<String, dynamic>) {
        result.add(TerminalProcess(
          name: proc['name'] ?? proc['ProcessName'] ?? entry.key,
          pid: proc['ProcessId'] ?? proc['Pid'] ?? proc['pid'] ?? 0,
          cpu: (proc['cpuUsage'] ?? 0).toDouble(),
          mem: (proc['memoryUsage'] ?? 0).toDouble() / (1024 * 1024), // bytes → MB
          user: proc['user'] ?? '',
        ));
        // 递归处理子进程
        if (proc['children'] is Map<String, dynamic>) {
          result.addAll(_flattenProcessTree(proc['children']));
        }
      }
    }
    return result;
  }

  /// 结束进程 —— 走 WebSocket（fun:'processEnd'）。
  /// [killTree] 为 true 时结束整棵进程树。
  Future<void> killProcess(String seatId, int pid, {required int merchantId, String? processName, bool killTree = false}) async {
    try {
      final res = await _ws.request(
        fun: 'processEnd',
        seat: seatId,
        merchantId: merchantId,
        data: {
          'type': killTree ? 'ProcessTree' : 'ProcessId',
          'ProcessId': pid,
          if (processName != null) 'ProcessName': processName,
        },
      );
      if (res is Map) {
        final code = res['code'];
        if (code != null && code != 0 && code != '0') {
          throw ApiError(
            code: code is int ? code : int.tryParse(code.toString()),
            message: (res['msg'] ?? res['message'] ?? '结束进程失败').toString(),
            raw: res,
          );
        }
      }
    } catch (e) {
      if (_shouldReturnEmpty(e)) return;
      rethrow;
    }
  }

  /// 获取文件列表 —— 走 WebSocket（fun:'fileList'）。
  /// path 为空字符串时返回磁盘列表。
  Future<List<TerminalFile>> getFiles(String seatId, String path, {required int merchantId}) async {
    try {
      // 清理路径：移除开头的反斜杠，保持 C: 或 C:\xxx 格式
      var cleanPath = path.trim();
      while (cleanPath.startsWith('\\') || cleanPath.startsWith('/')) {
        cleanPath = cleanPath.substring(1);
      }

      final res = await _ws.request(
        fun: 'fileList',
        seat: seatId,
        merchantId: merchantId,
        data: {'path': cleanPath},
      );
      // WS 协议：成功 code=0；失败返回空列表（与旧 HTTP 行为一致）。
      // 注意 fileList 的 data 字段在某些情况下可能是 List（磁盘列表），
      // _extractWsBusinessData 仅处理 Map 类型，所以这里直接取剥外壳后的原始 data。
      dynamic data;
      if (res is Map) {
        final code = res['code'];
        if (code == null || code == 0 || code == '0') {
          data = res['data'];
        }
      }
      // 诊断日志：定位"磁盘列表渲染 0 条"问题
      debugPrint('[getFiles] cleanPath="$cleanPath" '
          'data.runtimeType=${data?.runtimeType} '
          'data isMap<String,dynamic>=${data is Map<String, dynamic>} '
          'data isMap=${data is Map} '
          'firstKey=${data is Map && (data as Map).isNotEmpty ? (data as Map).keys.first : "(empty)"}');

      // cleanPath 为空时，返回磁盘列表
      if (cleanPath.isEmpty) {
        // 兼容后端两种 key 格式：'C:' 或 'C:\'（带尾部反斜杠）
        // 统一剥掉尾部反斜杠，使下游 path 一律为 'C:' 形式（[isDriveRoot] 判断依赖此）
        final driveRegex = RegExp(r'^[A-Za-z]:\\?$');
        // 可能是数组 ['C:', 'D:', 'E:'] 或对象 {'C:': {...}, 'D:': {...}}
        if (data is List) {
          return data
              .where((d) => d is String && driveRegex.hasMatch(d))
              .map((d) {
                final normalized =
                    d.toString().replaceAll(RegExp(r'\\+$'), '');
                return TerminalFile(
                  name: normalized,
                  path: normalized,
                  isDirectory: true,
                  size: 0,
                  updatedAt: '',
                  isDrive: true,
                );
              })
              .toList();
        }
        if (data is Map<String, dynamic>) {
          return data.entries
              .where((e) => driveRegex.hasMatch(e.key))
              .map((e) {
            final info = e.value is Map<String, dynamic>
                ? e.value as Map<String, dynamic>
                : <String, dynamic>{};
            final normalized = e.key.replaceAll(RegExp(r'\\+$'), '');
            return TerminalFile(
              name: normalized,
              path: normalized,
              isDirectory: true,
              size: 0,
              updatedAt: info['lwtime'] ?? '',
              createdAt: info['ctime'] ?? '',
              isDrive: true,
            );
          }).toList();
        }
        return [];
      }

      // 普通目录
      if (data is Map<String, dynamic>) {
        // 后端返回 {filename: {isfile, size, ctime, lwtime, version}, ...}
        final list = data.entries.map((e) {
          final info = e.value is Map<String, dynamic>
              ? e.value as Map<String, dynamic>
              : <String, dynamic>{};
          // 构造完整路径
          String fullPath;
          if (RegExp(r'^[A-Za-z]:$').hasMatch(cleanPath)) {
            fullPath = '$cleanPath\\${e.key}';
          } else if (cleanPath.endsWith('\\')) {
            fullPath = '$cleanPath${e.key}';
          } else {
            fullPath = '$cleanPath\\${e.key}';
          }
          return TerminalFile(
            name: e.key,
            path: fullPath,
            isDirectory: info['isfile'] != true,
            size: info['size'] ?? 0,
            updatedAt: info['lwtime'] ?? '',
            createdAt: info['ctime'] ?? '',
            version: info['version'] ?? '',
          );
        }).toList();
        // 排序：文件夹在前，然后按名称排序
        list.sort((a, b) {
          if (a.isDirectory != b.isDirectory) {
            return a.isDirectory ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      }
      if (data is List) {
        return data.map((e) => TerminalFile.fromJson(e)).toList();
      }
      return [];
    } catch (e, stack) {
      debugPrint('[TerminalApi.getFiles] error: $e\n$stack');
      if (_shouldReturnEmpty(e)) {
        return TerminalMockData.files(seatId.hashCode, path);
      }
      rethrow;
    }
  }

  /// 下载文件
  /// 返回文件的二进制数据
  Future<List<int>> downloadFile(String seatId, String filePath, {required String domain}) async {
    final url = _buildUrl(domain, '/task');
    final token = TokenStore.getToken();
    final dio = _createProxiedDio();

    try {
      final response = await dio.post(
        url,
        queryParameters: {'seat': seatId},
        data: {
          'fun': 'fileRead',
          'data': {'path': filePath},
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/octet-stream,application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      final bytes = response.data;
      if (bytes is List<int>) {
        return bytes;
      }
      throw ApiError(code: -1, message: '文件下载失败：响应格式错误');
    } finally {
      dio.close();
    }
  }

  /// 获取硬件信息（静态 + 实时合并）—— 走 WebSocket（fun:'hwinfo' type:'info'/'realtime'）。
  /// 历史曾收到 `code:10 请使用http协议`，后端 2026-05 已放开，按文档 A9 切 WS。
  Future<List<Map<String, dynamic>>> getHardwareInfo(
    String seatId, {
    required int merchantId,
  }) async {
    if (seatId.isEmpty) return [];
    try {
      final infoRes = await _ws.request(
        fun: 'hwinfo',
        seat: seatId,
        merchantId: merchantId,
        data: const {'type': 'info'},
      );
      final infoData = _extractWsBusinessData(infoRes);

      // 尝试获取实时数据（可选，失败不影响静态信息展示）
      Map<String, dynamic> realtimeData = {};
      try {
        final rtRes = await _ws.request(
          fun: 'hwinfo',
          seat: seatId,
          merchantId: merchantId,
          data: const {'type': 'realtime'},
        );
        final rtRaw = _extractWsBusinessData(rtRes);
        if (rtRaw != null) realtimeData = rtRaw;
      } catch (_) {}

      if (infoData != null) {
        return _transformHardwareInfo(infoData, realtimeData);
      }
      return [];
    } catch (e) {
      if (_shouldReturnEmpty(e)) return [];
      rethrow;
    }
  }

  /// 获取硬件实时信息（供网络监控等周期调用）—— 走 WebSocket。
  Future<Map<String, dynamic>> getHardwareRealtime(
    String seatId, {
    required int merchantId,
  }) async {
    if (seatId.isEmpty) return {};
    try {
      final res = await _ws.request(
        fun: 'hwinfo',
        seat: seatId,
        merchantId: merchantId,
        data: const {'type': 'realtime'},
      );
      return _extractWsBusinessData(res) ?? {};
    } catch (e) {
      if (_shouldReturnEmpty(e)) return {};
      rethrow;
    }
  }

  /// 剥 WS 业务包装层 `{code, msg, data, fun}` → 返回 `data` 字段（Map）。
  /// code != 0 时返回 null。供 fileList/processTree/hwinfo 等 WS 化方法复用。
  Map<String, dynamic>? _extractWsBusinessData(dynamic res) {
    if (res is! Map) return null;
    final code = res['code'];
    if (code != null && code != 0 && code != '0') return null;
    final data = res['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// 电源控制（关机/重启/注销/锁定）—— 走 WebSocket（fun:'controlPc'）。
  Future<void> controlPc(String seatId, String type, {required int merchantId}) async {
    try {
      final res = await _ws.request(
        fun: 'controlPc',
        seat: seatId,
        merchantId: merchantId,
        data: {'type': type},
      );
      if (res is Map) {
        final code = res['code'];
        if (code != null && code != 0 && code != '0') {
          throw ApiError(
            code: code is int ? code : int.tryParse(code.toString()),
            message: (res['msg'] ?? res['message'] ?? '电源操作失败').toString(),
            raw: res,
          );
        }
      }
    } catch (e) {
      if (_shouldReturnEmpty(e)) return;
      rethrow;
    }
  }

  /// 获取聊天记录（暂保留 mock）
  Future<List<TerminalChatMessage>> getChatMessages(int id) async {
    return [];
  }

  /// 发送聊天消息（暂保留 mock）
  Future<void> sendChatMessage(int id, String content) async {
    // 暂不支持
  }

  /// 获取终端日志（暂保留 mock）
  Future<List<TerminalLog>> getLogs(int id) async {
    return TerminalMockData.logs(id);
  }

  /// 执行终端命令（后端通过 WebSocket 实现，暂保留 mock）
  Future<String> executeCommand(int id, String command) async {
    return TerminalMockData.commandOutput(id, command);
  }

  /// 重启远端服务（反代/协助/路由）—— 走 WebSocket **裸 event 帧**（非 peer 包装）。
  /// [type] = 'frpc'（反代）/ 'client'（协助）/ 'router'（路由）
  /// 协议：`{event:'sys.restart', id:<auto>, merchant_id, data:{type}}`
  /// 仅 mode==1 的 server 终端展示该入口；后端按 merchant_id 路由。
  Future<void> restartService(String type, {required int merchantId}) async {
    final res = await _ws.requestRawEvent(
      event: 'sys.restart',
      customFields: {
        'merchant_id': merchantId,
        'data': {'type': type},
      },
    );
    if (res is Map) {
      final code = res['code'];
      if (code != null && code != 0 && code != '0') {
        throw ApiError(
          code: code is int ? code : int.tryParse(code.toString()),
          message: (res['msg'] ?? res['message'] ?? '重启服务失败').toString(),
          raw: res,
        );
      }
    }
  }

  /// 获取网吧联系人列表 —— 中央 HTTP `GET /merchant/{merchantId}/personnel`
  /// 返回 raw map：`{personnel: [{id, nickname, avatar, phone_number, role_tag}], roleMap: {1:'网维',...}}`
  /// 由终端详情页"联系电话" hover 气泡使用。
  Future<Map<String, dynamic>> getMerchantPersonnel(int merchantId) async {
    final response = await _client.get('/merchant/$merchantId/personnel');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  /// 保存终端备注 —— 中央 HTTP `POST /terminals/{id}/remark`
  /// body: `{"remark": "<p>...</p>"}`，content-type: application/json
  /// remark 是 HTML 字符串（由富文本编辑器 Delta → HTML 转换得到）。
  Future<void> saveRemark(int terminalId, String htmlContent) async {
    await _client.post(
      '/terminals/$terminalId/remark',
      data: {'remark': htmlContent},
    );
  }

  /// 远程唤醒 (WOL) —— **保持 frp HTTP**，未走 WS。
  /// 历史路径：兼容旧入口 (`_remoteAction(seatId, 'wakeup')`) 不动。
  /// 新入口"终端管理 → 唤醒"使用 [awakenViaWs]（WS + 携带 mac）。
  /// 参考 toolboxPage `useRemoteAwaken.js:152` 同步保留 HTTP 兜底。
  Future<void> wakeOnLan(String seatId, {required String domain}) async {
    await _netbarGet(domain, '/awaken', queryParameters: {'seat': seatId});
  }

  /// 唤醒终端（WOL）—— 走 WebSocket **裸 event 帧**（非 peer 包装）。
  /// 协议：`{event:'awaken', id:<auto>, merchant_id, data:{mac}}`
  /// 由"终端管理 → 唤醒"按钮调用，仅离线终端显示入口。
  /// 与 [wakeOnLan] 区别：本方法走后端 peer/awaken 转发，依赖网吧内仍在线的 agent
  /// 代发魔术包；旧 [wakeOnLan] 走 frp HTTP 直接由网吧本地网关发。
  Future<void> awakenViaWs(String mac, {required int merchantId}) async {
    final res = await _ws.requestRawEvent(
      event: 'awaken',
      customFields: {
        'merchant_id': merchantId,
        'data': {'mac': mac},
      },
    );
    if (res is Map) {
      final code = res['code'];
      if (code != null && code != 0 && code != '0') {
        throw ApiError(
          code: code is int ? code : int.tryParse(code.toString()),
          message: (res['msg'] ?? res['message'] ?? '唤醒失败').toString(),
          raw: res,
        );
      }
    }
  }

  // ===== 硬件信息格式化辅助 =====

  /// 将 hwinfo API 响应转换为 UI 展示格式 [{name, details: [{label, value}]}]
  List<Map<String, dynamic>> _transformHardwareInfo(
      Map<String, dynamic> info, Map<String, dynamic> realtime) {
    final result = <Map<String, dynamic>>[];

    // --- CPU ---
    final cpuInfoList = info['cpu'] as List? ?? [];
    final cpuRtList = realtime['cpu'] as List? ?? [];
    for (var i = 0; i < cpuInfoList.length; i++) {
      final cpu = cpuInfoList[i];
      if (cpu is! Map<String, dynamic>) continue;
      final rt = _findById(cpuRtList, cpu['id']);
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': cpu['name'] ?? ''},
        {'label': '厂商', 'value': cpu['vendor'] ?? ''},
        {'label': '核心/线程', 'value': '${cpu['core_count'] ?? 0}核/${cpu['thread_count'] ?? 0}线程'},
        {'label': '基础频率', 'value': _formatFreq(cpu['base_freq'])},
        {'label': '缓存', 'value': 'L1:${_formatBytes(cpu['l1_cache'])} L2:${_formatBytes(cpu['l2_cache'])} L3:${_formatBytes(cpu['l3_cache'])}'},
      ];
      if (rt != null) {
        details.add({'label': '当前负载', 'value': '${rt['load_total'] ?? 0}%'});
        if ((rt['clock_core'] ?? 0) > 0) {
          details.add({'label': '实时频率', 'value': _formatFreq(rt['clock_core'])});
        }
        if ((rt['power'] ?? 0) > 0) {
          details.add({'label': '功耗', 'value': '${(rt['power'] as num).toStringAsFixed(1)}W'});
        }
      }
      result.add({'name': '处理器 (CPU)', 'details': details});
    }

    // --- GPU ---
    final gpuInfoList = info['gpu'] as List? ?? [];
    final gpuRtList = realtime['gpu'] as List? ?? [];
    for (var i = 0; i < gpuInfoList.length; i++) {
      final gpu = gpuInfoList[i];
      if (gpu is! Map<String, dynamic>) continue;
      final rt = _findById(gpuRtList, gpu['id']);
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': gpu['name'] ?? ''},
        {'label': '厂商', 'value': gpu['vendor'] ?? ''},
        {'label': '显存', 'value': _formatBytes(gpu['memory_total'])},
      ];
      if (rt != null) {
        details.add({'label': '温度', 'value': '核心${rt['temperature'] ?? 0}°C / 显存${rt['temperature_memory'] ?? 0}°C / 热点${rt['temperature_hotspot'] ?? 0}°C'});
        details.add({'label': 'GPU负载', 'value': '${rt['load_gpu'] ?? 0}%'});
        details.add({'label': '显存负载', 'value': '${rt['load_memory'] ?? 0}%'});
        if ((rt['clock_core'] ?? 0) > 0 || (rt['clock_memory'] ?? 0) > 0) {
          details.add({'label': '频率', 'value': '核心${_formatFreq(rt['clock_core'])} / 显存${_formatFreq(rt['clock_memory'])}'});
        }
        if ((rt['power'] ?? 0) > 0) {
          details.add({'label': '功耗', 'value': '${(rt['power'] as num).toStringAsFixed(1)}W'});
        }
      }
      result.add({'name': '显卡 (GPU)', 'details': details});
    }

    // --- 内存 (聚合所有插槽) ---
    final memInfoList = info['memory'] as List? ?? [];
    final memRt = realtime['memory'];
    if (memInfoList.isNotEmpty) {
      int totalSize = 0;
      for (final mem in memInfoList) {
        if (mem is Map<String, dynamic>) {
          totalSize += (mem['size'] as num? ?? 0).toInt();
        }
      }
      final first = memInfoList[0] as Map<String, dynamic>;
      final details = <Map<String, dynamic>>[
        {'label': '总容量', 'value': '${_formatBytes(totalSize)} (${memInfoList.length}条)'},
        {'label': '频率', 'value': '${first['speed'] ?? 0} MHz'},
        {'label': '类型', 'value': '${first['type'] ?? ''} ${first['form_factor'] ?? ''}'},
        {'label': '厂商', 'value': first['manufacturer'] ?? ''},
        {'label': '电压', 'value': '${(first['voltage'] ?? 0).toStringAsFixed(1)}V'},
        {'label': '数据位宽', 'value': '${first['data_width'] ?? 0}bit'},
      ];
      if (memRt is Map<String, dynamic>) {
        details.add({'label': '当前占用', 'value': '${memRt['load_total'] ?? 0}%'});
      }
      result.add({'name': '内存 (RAM)', 'details': details});
    }

    // --- 存储 (每块硬盘一张卡) ---
    final storageInfoList = info['storage'] as List? ?? [];
    final storageRtList = realtime['storage'] as List? ?? [];
    for (var i = 0; i < storageInfoList.length; i++) {
      final disk = storageInfoList[i];
      if (disk is! Map<String, dynamic>) continue;
      final rt = _findById(storageRtList, disk['id']);
      final rotation = (disk['rotation'] ?? 0) as num;
      final details = <Map<String, dynamic>>[
        {'label': '型号', 'value': (disk['model'] ?? '').toString().trim()},
        {'label': '容量', 'value': _formatBytes(disk['size'])},
        {'label': '类型/接口', 'value': '${disk['type'] ?? ''} ${disk['interface'] ?? ''}${rotation > 0 ? ' ${rotation}RPM' : ''}'},
        {'label': '序列号', 'value': (disk['serial'] ?? '').toString().trim()},
        {'label': '固件', 'value': disk['firmware'] ?? ''},
      ];
      if (rt != null) {
        final used = (rt['used_space'] as num? ?? 0).toDouble();
        final free = (rt['free_space'] as num? ?? 0).toDouble();
        final total = used + free;
        final pct = total > 0 ? (used / total * 100).toStringAsFixed(1) : '0';
        details.add({'label': '已用空间', 'value': '${_formatBytes(used)} / ${_formatBytes(total)} ($pct%)'});
        details.add({'label': '健康度', 'value': '${rt['health'] ?? 0}%'});
      }
      final idx = i + 1;
      result.add({'name': '存储 (磁盘$idx)', 'details': details});
    }

    // --- 网络 ---
    final netInfoList = info['network'] as List? ?? [];
    final netRtList = realtime['network'] as List? ?? [];
    for (var i = 0; i < netInfoList.length; i++) {
      final net = netInfoList[i];
      if (net is! Map<String, dynamic>) continue;
      final rt = _findById(netRtList, net['id']);
      final details = <Map<String, dynamic>>[
        {'label': '网卡', 'value': net['description'] ?? net['name'] ?? ''},
        {'label': 'IP', 'value': net['ip_address'] ?? ''},
        {'label': '网关', 'value': net['gateway'] ?? ''},
        {'label': '子网掩码', 'value': net['subnet_mask'] ?? ''},
        {'label': 'MAC', 'value': net['mac'] ?? ''},
        {'label': '速率', 'value': _formatNetSpeed(net['speed'])},
        {'label': 'DNS', 'value': net['dns'] ?? ''},
      ];
      if (rt != null) {
        details.add({'label': '上传速度', 'value': _formatBytesSpeed(rt['upload_speed'])});
        details.add({'label': '下载速度', 'value': _formatBytesSpeed(rt['download_speed'])});
      }
      result.add({'name': '网络 (Network)', 'details': details});
    }

    // --- 主板 ---
    final mbInfoList = info['motherboard'] as List? ?? [];
    for (final mb in mbInfoList) {
      if (mb is! Map<String, dynamic>) continue;
      result.add({
        'name': '主板 (Motherboard)',
        'details': [
          {'label': '厂商', 'value': mb['manufacturer'] ?? ''},
          {'label': '型号', 'value': mb['product'] ?? ''},
          {'label': '版本', 'value': mb['version'] ?? ''},
          {'label': 'BIOS', 'value': '${mb['bios_vendor'] ?? ''} ${mb['bios_version'] ?? ''}'},
          {'label': 'BIOS日期', 'value': mb['bios_date'] ?? ''},
        ],
      });
    }

    return result;
  }

  /// 根据 id 从 realtime 列表中查找对应项
  Map<String, dynamic>? _findById(List? list, dynamic id) {
    if (list == null || id == null) return null;
    for (final item in list) {
      if (item is Map<String, dynamic> && item['id'] == id) return item;
    }
    return null;
  }

  /// 格式化字节数
  String _formatBytes(dynamic bytes) {
    final b = (bytes is num) ? bytes.toDouble() : 0.0;
    if (b <= 0) return '0';
    if (b >= 1024 * 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
    if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${b.toInt()} B';
  }

  /// 格式化频率（Hz → GHz/MHz）
  String _formatFreq(dynamic freq) {
    final f = (freq is num) ? freq.toDouble() : 0.0;
    if (f <= 0) return '0';
    if (f >= 1000000000) return '${(f / 1000000000).toStringAsFixed(2)} GHz';
    if (f >= 1000000) return '${(f / 1000000).toStringAsFixed(0)} MHz';
    if (f >= 1000) return '${(f / 1000).toStringAsFixed(0)} KHz';
    return '${f.toInt()} Hz';
  }

  /// 格式化网卡速率（bps → Gbps/Mbps）
  String _formatNetSpeed(dynamic speed) {
    final s = (speed is num) ? speed.toDouble() : 0.0;
    if (s <= 0) return '0';
    if (s >= 1000000000) return '${(s / 1000000000).toStringAsFixed(0)} Gbps';
    if (s >= 1000000) return '${(s / 1000000).toStringAsFixed(0)} Mbps';
    if (s >= 1000) return '${(s / 1000).toStringAsFixed(0)} Kbps';
    return '${s.toInt()} bps';
  }

  /// 格式化字节速率（bytes/s → MB/s, KB/s）
  String _formatBytesSpeed(dynamic bytesPerSec) {
    final b = (bytesPerSec is num) ? bytesPerSec.toDouble() : 0.0;
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB/s';
    return '${b.toInt()} B/s';
  }
}
