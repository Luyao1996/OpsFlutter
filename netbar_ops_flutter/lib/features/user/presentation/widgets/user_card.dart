import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/user_mock_data.dart';

class UserCard extends StatefulWidget {
  final User user;
  final VoidCallback onEdit;
  final VoidCallback onBind2FA;

  const UserCard({
    super.key,
    required this.user,
    required this.onEdit,
    required this.onBind2FA,
  });

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  bool _isHovered = false;

  Color _getAvatarColor(String name) {
    final colors = [
      Colors.blue.shade500,
      Colors.indigo.shade500,
      Colors.purple.shade500,
      Colors.teal.shade500,
      Colors.orange.shade500,
    ];
    final index = name.codeUnitAt(0) % colors.length;
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    final alwaysShowEdit =
        context.isPhone || (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
    final showEdit = _isHovered || alwaysShowEdit;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8), // Vue uses slightly smaller radius
          border: Border.all(
            color: _isHovered ? AppColors.iosBlue.withOpacity(0.5) : Colors.grey.shade200,
          ),
          boxShadow: _isHovered ? AppShadows.sm : [], // Vue is very flat, shadow only on hover
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getAvatarColor(widget.user.nickname),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    widget.user.nickname.isNotEmpty ? widget.user.nickname[0] : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.nickname,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${widget.user.username}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IgnorePointer(
                    ignoring: !showEdit,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: showEdit ? 1 : 0,
                      child: InkWell(
                        onTap: widget.onEdit,
                        borderRadius: BorderRadius.circular(8),
                        child: const Center(
                          child: Icon(LucideIcons.edit3, size: 16, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Roles
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.user.roles.map((role) {
                final isAdmin = role == UserRole.admin;
                final label = roleLabels[role] ?? role.name;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isAdmin ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF), // bg-red-50 : bg-blue-50
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isAdmin ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE), // border-red-100 : border-blue-100
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isAdmin ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8), // text-red-700 : text-blue-700
                    ),
                  ),
                );
              }).toList(),
            ),
            const Spacer(),
            // Footer
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.user.is2FABound ? LucideIcons.shield : LucideIcons.lock,
                        size: 14, // Smaller icon
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.user.is2FABound ? '已绑定' : '未绑定',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: widget.onBind2FA,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      widget.user.is2FABound ? '重新绑定' : '去绑定',
                      style: const TextStyle(fontSize: 12, color: AppColors.iosBlue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
