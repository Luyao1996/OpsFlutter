import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';

/// 登录请求（保留原有，但后端不支持直接密码登录）
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

  // 与后端一致的管理员判断逻辑
  /// 总部管理员：group_id 为空（0 或 null）
  bool get isTopManager => groupId == null || groupId == 0;
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

  /// 登录（保留原有接口，但实际会走扫码流程）
  /// 这个方法会直接报错，因为后端不支持直接密码登录
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await _client.post('/passport/login', data: request.toJson());
    return LoginResponse.fromJson(response.data ?? {});
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

  /// 刷新Token（ignoreUnauthorized 防止 401 死循环）
  Future<TokenResponse> refreshToken() async {
    final response = await _client.post('/passport/refresh',
        options: Options(extra: {'ignoreUnauthorized': true}));
    return TokenResponse.fromJson(response.data ?? {});
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
}
