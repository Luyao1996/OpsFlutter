import '../../../core/network/api_client.dart';

/// 登录请求
class LoginRequest {
  final String username;
  final String password;

  LoginRequest({required this.username, required this.password});

  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}

/// 用户模型
class User {
  final int id;
  final String username;
  final String name;
  final String role;
  final String? email;
  final String? phone;
  final int status;
  final String? createdAt;

  User({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    this.email,
    this.phone,
    required this.status,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      name: json['name'] ?? json['username'] ?? '',
      role: json['role'] ?? '',
      email: json['email'],
      phone: json['phone'],
      status: json['status'] ?? 1,
      createdAt: json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'name': name,
    'role': role,
    'email': email,
    'phone': phone,
    'status': status,
    'created_at': createdAt,
  };
}

/// 登录响应
class LoginResponse {
  final String token;
  final User user;

  LoginResponse({required this.token, required this.user});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      token: json['token'] ?? '',
      user: User.fromJson(json['user'] ?? {}),
    );
  }
}

/// QR 登录会话
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
      sessionId: json['session_id'] ?? '',
      qrData: json['qr_data'] ?? '',
      expiresAt: json['expires_at'] ?? '',
    );
  }
}

/// QR 登录状态
class QRLoginStatus {
  final String status; // pending, scanned, confirmed, expired
  final String? token;
  final User? user;

  QRLoginStatus({required this.status, this.token, this.user});

  factory QRLoginStatus.fromJson(Map<String, dynamic> json) {
    return QRLoginStatus(
      status: json['status'] ?? 'pending',
      token: json['token'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}

/// Auth API 服务
class AuthApi {
  final ApiClient _client = ApiClient.instance;

  /// 登录
  Future<LoginResponse> login(LoginRequest request) async {
    final response = await _client.post('/auth/login', data: request.toJson());
    return LoginResponse.fromJson(response.data);
  }

  /// 登出
  Future<void> logout() async {
    await _client.post('/auth/logout');
  }

  /// 获取当前用户
  Future<User> getCurrentUser() async {
    final response = await _client.get('/auth/me');
    return User.fromJson(response.data);
  }

  /// 创建 QR 会话
  Future<QRLoginSession> createQRSession() async {
    final response = await _client.post('/auth/qr/create');
    return QRLoginSession.fromJson(response.data);
  }

  /// 检查 QR 状态
  Future<QRLoginStatus> checkQRStatus(String sessionId) async {
    final response = await _client.get('/auth/qr/status/$sessionId');
    return QRLoginStatus.fromJson(response.data);
  }
}

