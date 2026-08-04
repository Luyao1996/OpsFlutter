import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';

/// 账号密码登录请求（生产登录接口 /alpha/passport/login，form-data 提交）
class LoginRequest {
  final String username;
  final String password;

  LoginRequest({required this.username, required this.password});

  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}

/// 角色模型
class Role {
  final int id;
  final String name;

  Role({required this.id, required this.name});

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// 用户模型 - 适配后端字段
class User {
  final int id;
  final String username;
  final String nickname; // 后端字段名
  final int? groupId;
  final bool isManager; // 后端字段名
  final bool isEnable;
  final String? phoneNumber;
  final List<Role>? roles;
  /// 细分权限列表（后端返回 [{id, name}, ...]，用于 hasDetailPermission 检查）
  final List<Role>? permissions;
  final String? createdAt;

  // 兼容旧代码的getter
  String get name => nickname;
  String get role => isManager ? 'manager' : 'user';
  int get status => isEnable ? 1 : 0;
  String? get email => null;
  String? get phone => phoneNumber;

  // 与后端一致的管理员判断逻辑（对齐 toolboxPage permissions.js isHeadquartersAdmin）
  /// 总部管理员：group_id 为空（0 或 null）且 is_manager 为 true。
  /// 总部普通成员（group_id 空但非 manager）不是管理员。
  bool get isTopManager => (groupId == null || groupId == 0) && isManager;
  /// 分部管理员：group_id > 0 且 is_manager 为 true
  bool get isSubManager => (groupId != null && groupId! > 0) && isManager;
  /// 普通用户：group_id > 0 且 is_manager 为 false
  bool get isNormalUser => (groupId != null && groupId! > 0) && !isManager;
  /// 是否有管理权限（总部管理员或分部管理员）
  bool get hasAdminAccess => isTopManager || isSubManager;

  User({
    required this.id,
    required this.username,
    required this.nickname,
    this.groupId,
    required this.isManager,
    required this.isEnable,
    this.phoneNumber,
    this.roles,
    this.permissions,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? json['username'] ?? '',
      groupId: json['group_id'],
      isManager: json['is_manager'] == true || json['is_manager'] == 1,
      isEnable: json['is_enable'] == true || json['is_enable'] == 1,
      phoneNumber: json['phone_number'],
      roles: (json['roles'] as List?)?.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList(),
      permissions: (json['permissions'] as List?)?.map((e) => Role.fromJson(e as Map<String, dynamic>)).toList(),
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'group_id': groupId,
    'is_manager': isManager,
    'is_enable': isEnable,
    'phone_number': phoneNumber,
    'roles': roles?.map((r) => r.toJson()).toList(),
    'permissions': permissions?.map((p) => p.toJson()).toList(),
    'created_at': createdAt,
  };
}

/// 登录响应 - 保留兼容
class LoginResponse {
  final String token;
  final User user;

  LoginResponse({required this.token, required this.user});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] ?? json['access_token'] ?? '',
      user: User.fromJson(json['user'] ?? {}),
    );
  }
}

/// 预登录响应 - 后端扫码登录第一步
class PreLoginResponse {
  final String pwd; // 口令，用于后续获取token
  final String qrCode; // base64二维码图片

  PreLoginResponse({required this.pwd, required this.qrCode});

  factory PreLoginResponse.fromJson(Map<String, dynamic> json) {
    return PreLoginResponse(
      pwd: json['pwd'] ?? '',
      qrCode: json['qrCode'] ?? '',
    );
  }
}

/// Token响应 - 后端扫码登录第二步
class TokenResponse {
  final String accessToken;
  final String tokenType;
  final int? createIn;
  final int? expireIn;

  TokenResponse({
    required this.accessToken,
    required this.tokenType,
    this.createIn,
    this.expireIn,
  });

  factory TokenResponse.fromJson(Map<String, dynamic> json) {
    return TokenResponse(
      accessToken: json['access_token'] ?? '',
      tokenType: json['token_type'] ?? 'Bearer',
      createIn: json['create_in'],
      expireIn: json['expire_in'],
    );
  }

  bool get isValid => accessToken.isNotEmpty;
}

/// QR 登录会话 - 保留兼容
class QRLoginSession {
  final String sessionId;
  final String qrData;
  final String expiresAt;

  QRLoginSession({
    required this.sessionId,
    required this.qrData,
    required this.expiresAt,
  });

  factory QRLoginSession.fromJson(Map<String, dynamic> json) {
    return QRLoginSession(
      sessionId: json['session_id'] ?? json['pwd'] ?? '',
      qrData: json['qr_data'] ?? json['qrCode'] ?? '',
      expiresAt: json['expires_at'] ?? '',
    );
  }
}

/// QR 登录状态 - 保留兼容
class QRLoginStatus {
  final String status; // pending, scanned, confirmed, expired
  final String? token;
  final User? user;

  QRLoginStatus({required this.status, this.token, this.user});

  factory QRLoginStatus.fromJson(Map<String, dynamic> json) {
    // 后端返回access_token表示已授权
    final accessToken = json['access_token'];
    final hasToken = accessToken != null && accessToken.toString().isNotEmpty;

    return QRLoginStatus(
      status: hasToken ? 'confirmed' : 'pending',
      token: accessToken,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

/// Auth API 服务
class AuthApi {
  final ApiClient _client = ApiClient.instance;

  /// 预登录 - 获取二维码（后端扫码登录）
  /// 返回pwd（口令）和qrCode（base64二维码）
  Future<PreLoginResponse> preLogin({String? username, String? password}) async {
    final response = await _client.get('/passport/login/qr');
    return PreLoginResponse.fromJson(response.data ?? {});
  }

  /// 获取Token - 通过pwd获取JWT令牌
  /// 需要用户扫码授权后才能获取到token
  Future<TokenResponse> getToken(String pwd) async {
    final response = await _client.get('/passport/token', queryParameters: {'pwd': pwd});
    return TokenResponse.fromJson(response.data ?? {});
  }

  /// 账号密码登录
  /// 生产登录前缀为 /alpha（其它业务接口走 /api），form-data 提交 username/password。
  /// 后端返回 {access_token, token_type, ...}（不含 user），故返回 TokenResponse，
  /// 由调用方拿 access_token 走 loginWithToken 再获取用户信息。
  Future<TokenResponse> login(LoginRequest request) async {
    final loginUrl = Uri.parse(AppConfig.baseUrl)
        .replace(path: '/alpha/passport/login')
        .toString();
    final response = await _client.post(
      loginUrl,
      data: FormData.fromMap({
        'username': request.username,
        'password': request.password,
      }),
    );
    return TokenResponse.fromJson(response.data ?? {});
  }

  /// 登出
  Future<void> logout() async {
    await _client.post('/passport/logout');
  }

  /// 获取当前用户
  Future<User> getCurrentUser() async {
    final response = await _client.get('/passport/profile');
    // 后端返回 {user: {...}}
    final data = response.data;
    if (data is Map<String, dynamic> && data.containsKey('user')) {
      return User.fromJson(data['user']);
    }
    return User.fromJson(data ?? {});
  }

  /// 编辑当前用户资料
  Future<void> updateProfile({
    String? nickname,
    String? username,
    String? password,
  }) async {
    await _client.post('/passport/profile', data: {
      if (nickname != null) 'nickname': nickname,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
    });
  }

  /// 修改当前用户密码（通过编辑资料接口）
  Future<void> changeMyPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post('/passport/profile', data: {
      'password': newPassword,
    }, options: Options(extra: {'ignoreUnauthorized': true}));
  }

  /// 获取 2FA 一次性验证码 —— GET /passport/twoFactorCode?terminal_id={id}
  /// 返回示例：`{"code":"169557","period":30,"expires_in":22}`
  /// 由"终端详情 → 服务管理 → 复制 2FA"调用；后端基于当前登录态 + 目标终端生成 TOTP 码。
  /// [terminalId] 必传：后端按终端 id 区分密钥（不同终端 TOTP 不同）。
  Future<Map<String, dynamic>> getTwoFactorCode({required int terminalId}) async {
    final response = await _client.get(
      '/passport/twoFactorCode',
      queryParameters: {'terminal_id': terminalId},
    );
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{};
  }

  /// 创建 QR 会话（适配后端接口）
  Future<QRLoginSession> createQRSession() async {
    // 后端通过 GET /passport/login/qr 返回二维码
    final response = await _client.get('/passport/login/qr');
    final data = response.data ?? {};
    return QRLoginSession(
      sessionId: data['pwd'] ?? '',
      qrData: data['qrCode'] ?? '',
      expiresAt: '', // 后端未返回过期时间
    );
  }

  /// 检查 QR 状态（适配后端接口）
  Future<QRLoginStatus> checkQRStatus(String sessionId) async {
    final response = await _client.get('/passport/token', queryParameters: {'pwd': sessionId});
    return QRLoginStatus.fromJson(response.data ?? {});
  }

  // ===== Sign in with Apple（协议以 docs/SignInWithApple前端接口文档_后端定稿.md 为准）=====
  // 后端统一信封：HTTP 200 + {code(int:0成功/1业务失败/401认证失败), message, data,
  // error_code(string 稳定错误码)}；code=0 时 ApiClient 拦截器已把 response.data
  // 解包为信封里的 data，code!=0 时拦截器 reject，原始信封挂在 response.data 上。

  /// 从 ApiError 提取后端信封 Map（{code, message, data, error_code}）
  Map? _appleEnvelope(Object e) {
    if (e is! ApiError) return null;
    final raw = e.raw;
    if (raw is DioException) {
      final data = raw.response?.data;
      if (data is Map) return data;
      final inner = raw.error;
      if (inner is ApiError && inner.raw is Map) return inner.raw as Map;
    } else if (raw is Map) {
      return raw;
    }
    return null;
  }

  /// 后端稳定错误码 → 用户可见中文文案（对齐后端定稿文档 §6，分支必须用
  /// error_code，禁止依赖 message 文本）
  String _appleErrorMessage(String errorCode, String fallback) {
    switch (errorCode) {
      case 'INVALID_APPLE_TOKEN':
        return 'Apple 授权凭证无效，请重新尝试 Apple 登录';
      case 'ACCOUNT_DISABLED':
        return '该账号已停用，请联系管理员';
      case 'INVALID_BIND_TICKET':
        return '本次 Apple 登录已超时，请重新点击"通过 Apple 登录"';
      case 'BIND_TICKET_BUSY':
        return '绑定正在处理中，请稍候重试';
      case 'APPLE_ALREADY_BOUND':
        return '该 Apple 账号已关联其他系统账号';
      case 'USER_ALREADY_BOUND_APPLE':
        return '当前系统账号已关联过其他 Apple 账号';
      case 'RECENT_LOGIN_REQUIRED':
        return '安全校验过期，请重新输入账号密码';
      case 'APPLE_SERVICE_UNAVAILABLE':
        return 'Apple 服务暂时不可用，请稍后重试';
      case 'APPLE_LOGIN_DISABLED':
        // 注意：iOS 端 Apple 入口是 App Store 4.8 强制项，不可据此隐藏入口
        return 'Apple 登录服务未启用，请联系管理员或使用其他方式登录';
      case 'TOO_MANY_ATTEMPTS':
        return '操作过于频繁，请稍后重试';
      case 'APPLE_LOGIN_FAILED':
        return 'Apple 登录失败，请稍后重试';
      case 'APPLE_BIND_FAILED':
        return 'Apple 绑定失败，请稍后重试';
      case 'APPLE_UNBIND_FAILED':
        return '解绑失败，请稍后重试';
    }
    return fallback;
  }

  /// Apple 登录（无需业务 JWT）。
  /// 成功（已绑定）返回业务 token；未绑定抛 [AppleIdNotBoundException]（携带
  /// 300 秒一次性 bind_ticket）；其余业务失败抛 [AppleAuthException]。
  /// 信封 code=401 属业务分支，带 ignoreUnauthorized 防全局踢登录。
  Future<TokenResponse> loginWithApple({
    required String identityToken,
    required String nonce,
  }) async {
    final url = Uri.parse(AppConfig.baseUrl)
        .replace(path: '/alpha/passport/login/apple')
        .toString();
    try {
      final response = await _client.post(
        url,
        data: {'identity_token': identityToken, 'nonce': nonce},
        options: Options(
          extra: {'ignoreUnauthorized': true},
          // 后端首次/缓存过期时需外呼 Apple JWKS，全局 5s 可能不够
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      return TokenResponse.fromJson(response.data ?? {});
    } catch (e) {
      final env = _appleEnvelope(e);
      final errorCode = env?['error_code']?.toString();
      if (errorCode == 'APPLE_NOT_BOUND') {
        final data = env?['data'];
        final ticket = (data is Map ? data['bind_ticket'] : null)?.toString();
        if (ticket != null && ticket.isNotEmpty) {
          throw AppleIdNotBoundException(bindTicket: ticket);
        }
        throw AppleAuthException(errorCode, 'Apple 登录失败：绑定票据缺失，请重试');
      }
      if (errorCode != null && errorCode.isNotEmpty) {
        throw AppleAuthException(
          errorCode,
          _appleErrorMessage(errorCode, e is ApiError ? e.message : '登录失败'),
        );
      }
      rethrow;
    }
  }

  /// 消费 bind_ticket 完成 Apple 绑定。
  /// 前置：必须刚用账密登录成功（600 秒近期认证窗口），拦截器自动携带该 JWT；
  /// 成功后端不换发 token，继续用当前 JWT。失败抛 [AppleAuthException]。
  Future<void> bindApple({required String bindTicket}) async {
    final url = Uri.parse(AppConfig.baseUrl)
        .replace(path: '/alpha/passport/login/apple/bind')
        .toString();
    try {
      await _client.post(
        url,
        data: {'bind_ticket': bindTicket},
        options: Options(
          extra: {'ignoreUnauthorized': true},
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      // code=0 即成功，data 为空数组无需解析
    } catch (e) {
      final env = _appleEnvelope(e);
      final errorCode = env?['error_code']?.toString();
      if (errorCode != null && errorCode.isNotEmpty) {
        throw AppleAuthException(errorCode, _appleErrorMessage(errorCode, '绑定失败'));
      }
      // code=401 无 error_code（框架层认证失败）：按后端文档提示重新登录
      if (env?['code'] == 401) {
        throw AppleAuthException(null, '登录状态校验失败，请重新尝试 Apple 登录');
      }
      rethrow;
    }
  }

  /// 解除当前用户的 Apple 绑定（幂等：未绑定时调用也返回成功）。
  /// 前置：必须刚完成账密登录（600 秒近期认证窗口），拦截器自动携带该新 JWT；
  /// 空请求体，解绑对象始终是 JWT 对应的当前用户（后端定稿文档 §5）。
  Future<void> unbindApple() async {
    final url = Uri.parse(AppConfig.baseUrl)
        .replace(path: '/alpha/passport/apple/unbind')
        .toString();
    try {
      await _client.post(
        url,
        data: const <String, dynamic>{},
        options: Options(
          extra: {'ignoreUnauthorized': true},
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      // code=0 即成功，data 为空数组无需解析
    } catch (e) {
      final env = _appleEnvelope(e);
      final errorCode = env?['error_code']?.toString();
      if (errorCode != null && errorCode.isNotEmpty) {
        throw AppleAuthException(errorCode, _appleErrorMessage(errorCode, '解绑失败'));
      }
      if (env?['code'] == 401) {
        throw AppleAuthException(null, '登录状态校验失败，请重新验证密码');
      }
      rethrow;
    }
  }
}

/// Apple 登录：该 Apple 账号尚未绑定系统账号（正常业务分支，非失败）。
/// 携带后端签发的一次性绑定票据（300 秒有效、只能消费一次）。
class AppleIdNotBoundException implements Exception {
  final String bindTicket;

  AppleIdNotBoundException({required this.bindTicket});

  @override
  String toString() => '该 Apple 账号尚未关联系统账号';
}

/// Apple 登录/绑定业务失败。[errorCode] 为后端稳定错误码（可能为 null，
/// 如信封 code=401 无 error_code 的框架层失败），[message] 为用户可见文案。
class AppleAuthException implements Exception {
  final String? errorCode;
  final String message;

  AppleAuthException(this.errorCode, this.message);

  @override
  String toString() => message;
}
