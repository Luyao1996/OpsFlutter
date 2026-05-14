import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Token 存储管理
class TokenStore {
  static const String _tokenKey = 'token';
  static const String _userKey = 'user';
  static const String _savedUsersKey = 'ops_pro_saved_users';
  static const String _currentNetbarKey = 'current_netbar';
  static const String _autoConnectKey = 'auto_connect_last_netbar';

  static SharedPreferences? _prefs;
  static Future<void> Function()? onBeforeClearAuth;

  /// 初始化
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取 Token
  static String? getToken() {
    return _prefs?.getString(_tokenKey);
  }

  /// 保存 Token
  static Future<bool> setToken(String token) async {
    return await _prefs?.setString(_tokenKey, token) ?? false;
  }

  /// 清除 Token
  static Future<bool> removeToken() async {
    return await _prefs?.remove(_tokenKey) ?? false;
  }

  /// 获取用户信息
  static Map<String, dynamic>? getUser() {
    final userStr = _prefs?.getString(_userKey);
    if (userStr == null) return null;
    try {
      return json.decode(userStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 保存用户信息
  static Future<bool> setUser(Map<String, dynamic> user) async {
    return await _prefs?.setString(_userKey, json.encode(user)) ?? false;
  }

  /// 清除用户信息
  static Future<bool> removeUser() async {
    return await _prefs?.remove(_userKey) ?? false;
  }

  /// 获取保存的用户列表
  static List<Map<String, dynamic>> getSavedUsers() {
    final usersStr = _prefs?.getString(_savedUsersKey);
    if (usersStr == null) return [];
    try {
      final list = json.decode(usersStr) as List;
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  /// 保存用户列表
  static Future<bool> setSavedUsers(List<Map<String, dynamic>> users) async {
    return await _prefs?.setString(_savedUsersKey, json.encode(users)) ?? false;
  }

  /// 获取当前网吧
  static Map<String, dynamic>? getCurrentNetbar() {
    final netbarStr = _prefs?.getString(_currentNetbarKey);
    if (netbarStr == null) return null;
    try {
      return json.decode(netbarStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 保存当前网吧
  static Future<bool> setCurrentNetbar(Map<String, dynamic> netbar) async {
    return await _prefs?.setString(_currentNetbarKey, json.encode(netbar)) ??
        false;
  }

  /// 清除当前网吧
  static Future<bool> removeCurrentNetbar() async {
    return await _prefs?.remove(_currentNetbarKey) ?? false;
  }

  /// 获取是否自动连接上次网吧
  static bool getAutoConnectLastNetbar() {
    return _prefs?.getBool(_autoConnectKey) ?? false;
  }

  /// 设置是否自动连接上次网吧
  static Future<bool> setAutoConnectLastNetbar(bool enabled) async {
    return await _prefs?.setBool(_autoConnectKey, enabled) ?? false;
  }

  /// 清除所有认证数据
  static Future<void> clearAuth() async {
    try {
      await onBeforeClearAuth?.call();
    } catch (_) {}
    await removeToken();
    await removeUser();
    await removeCurrentNetbar();
    await _prefs?.remove(_autoConnectKey);
    // 历史遗留：旧版本曾存过 token_expire_at，主动清掉避免残留
    await _prefs?.remove('token_expire_at');
  }

  /// 是否已登录
  static bool isLoggedIn() {
    return getToken() != null;
  }

  /// 通用字符串获取
  static String? getString(String key) {
    return _prefs?.getString(key);
  }

  /// 通用字符串保存
  static Future<bool> setString(String key, String value) async {
    return await _prefs?.setString(key, value) ?? false;
  }
}
