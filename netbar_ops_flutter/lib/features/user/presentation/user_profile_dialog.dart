import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../core/storage/token_store.dart';

class UserProfileDialog extends ConsumerStatefulWidget {
  const UserProfileDialog({super.key});

  @override
  ConsumerState<UserProfileDialog> createState() => _UserProfileDialogState();
}

class _UserProfileDialogState extends ConsumerState<UserProfileDialog> {
  String _activeTab = 'overview';
  bool _notifications = true;
  bool _autoConnect = false;
  bool _is2FAEnabled = true;

  @override
  void initState() {
    super.initState();
    _autoConnect = TokenStore.getAutoConnectLastNetbar();
  }

  @override
  Widget build(BuildContext context) {
    // 模拟 Vue 中的 User 数据
    final user = ref.watch(authNotifierProvider).user;
    final userName = user?.name ?? 'Administrator';
    final userRole = user?.role == 'admin' ? '管理员' : '操作员';
    final userAccount = user?.username ?? 'N/A';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 800,
          height: 500,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.xl,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Row(
                children: [
                  // Sidebar
                  Container(
                    width: 256, // w-64 = 16rem = 256px
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9FAFB), // gray-50
                      border: Border(
                        right: BorderSide(color: Color(0xFFF3F4F6)), // gray-100
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 24, top: 8),
                          child: Text(
                            '个人中心',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827), // gray-900
                            ),
                          ),
                        ),
                        _buildNavItem('overview', LucideIcons.user, '账户概览'),
                        const SizedBox(height: 4),
                        _buildNavItem('security', LucideIcons.shield, '安全设置'),
                        const SizedBox(height: 4),
                        _buildNavItem('settings', LucideIcons.settings, '偏好设置'),
                        const Spacer(),
                        _buildLogoutButton(),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                            child: _buildActiveTabContent(userName, userRole, userAccount),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Close Button
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                  color: const Color(0xFF9CA3AF), // gray-400
                  hoverColor: const Color(0xFFF3F4F6), // gray-100
                  splashRadius: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(String id, IconData icon, String label) {
    final isActive = _activeTab == id;
    return InkWell(
      onTap: () => setState(() => _activeTab = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            )
          ] : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? const Color(0xFF111827) : const Color(0xFF6B7280), // gray-900 vs gray-500
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive ? const Color(0xFF111827) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        // 立即切回登录界面（路由重定向也会兜底）
        ref.read(authNotifierProvider.notifier).logout();
        context.go('/login');
        // Router redirection handles the rest
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(LucideIcons.logOut, size: 18, color: Color(0xFFDC2626)), // red-600
            SizedBox(width: 12),
            Text(
              '退出登录',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(String userName, String role, String account) {
    switch (_activeTab) {
      case 'overview':
        return _buildOverviewTab(userName, role, account);
      case 'security':
        return _buildSecurityTab();
      case 'settings':
        return _buildSettingsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildOverviewTab(String userName, String role, String account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gradient Card
        Container(
          height: 160, // approximate height based on visual
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF4F46E5)], // blue-500 to indigo-600
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.lg,
          ),
          child: Stack(
            children: [
              // Decorative circle (top right)
              Positioned(
                top: -40,
                right: -40,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Info
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          role,
                          style: TextStyle(
                            fontSize: 14,
                            color: const Color(0xFFDBEAFE).withOpacity(0.9), // blue-100
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white.withOpacity(0.1)),
                              ),
                              child: Text(
                                '账号: $account',
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ADE80).withOpacity(0.3), // green-400/30
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF4ADE80).withOpacity(0.2)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF4ADE80),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '在线',
                                    style: TextStyle(color: Color(0xFFF0FDF4), fontSize: 12), // green-50
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Recent Login
        const Row(
          children: [
            Icon(LucideIcons.user, size: 16, color: Color(0xFF6B7280)), // gray-500
            SizedBox(width: 8),
            Text(
              '最近登录',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB), // gray-50
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)), // gray-200
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chrome (Windows)',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                        ),
                        Text(
                          '成都, 中国 (192.168.1.102)',
                          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4), // green-50
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '当前设备',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF16A34A)), // green-600
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Change Password
        const Row(
          children: [
            Icon(LucideIcons.lock, size: 16, color: Color(0xFF6B7280)),
            SizedBox(width: 8),
            Text(
              '修改密码',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInput('当前密码'),
        const SizedBox(height: 12),
        _buildInput('新密码'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF374151), // gray-700
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: const Text('更新密码', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
        ),
        
        const SizedBox(height: 24),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        const SizedBox(height: 24),
        
        // 2FA
        const Row(
          children: [
            Icon(LucideIcons.shield, size: 16, color: Color(0xFF6B7280)),
            SizedBox(width: 8),
            Text(
              '双因素认证 (2FA)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _is2FAEnabled ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6), // green-100 : gray-100
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.smartphone,
                  size: 20,
                  color: _is2FAEnabled ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF), // green-600 : gray-400
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _is2FAEnabled ? '已启用身份验证器' : '未启用',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                    ),
                    Text(
                      _is2FAEnabled ? '账号受到高强度保护' : '建议开启以提升安全性',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _is2FAEnabled,
                activeColor: AppColors.iosBlue,
                onChanged: (val) => setState(() => _is2FAEnabled = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInput(String hint) {
    return TextField(
      obscureText: true,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)), // gray-400
        filled: true,
        fillColor: const Color(0xFFF9FAFB), // gray-50
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), // py-2.5 ~ 10-12px
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)), // gray-200
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 2), // ring-2
        ),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(LucideIcons.settings, size: 16, color: Color(0xFF6B7280)),
            SizedBox(width: 8),
            Text(
              '通用设置',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            children: [
              _buildSettingItem(
                icon: LucideIcons.bell,
                iconColor: const Color(0xFF2563EB), // blue-600
                iconBg: const Color(0xFFEFF6FF), // blue-50
                title: '系统通知',
                subtitle: '接收异常告警和系统维护通知',
                value: _notifications,
                onChanged: (v) => setState(() => _notifications = v),
              ),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildSettingItem(
                icon: LucideIcons.logOut, // Actually using LogOut icon in Vue for AutoConnect? Vue code says LogOut. Okay.
                iconColor: const Color(0xFF9333EA), // purple-600
                iconBg: const Color(0xFFFAF5FF), // purple-50
                title: '自动连接',
                subtitle: '登录时自动进入上次管理的网吧',
                value: _autoConnect,
                onChanged: (v) {
                  setState(() => _autoConnect = v);
                  TokenStore.setAutoConnectLastNetbar(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: AppColors.iosBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
