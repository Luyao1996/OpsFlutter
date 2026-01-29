import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../data/user_mock_data.dart';
import 'user_card.dart';

class UserGrid extends StatelessWidget {
  final List<User> users;
  final Function(User) onEditUser;
  final Function(User) onBind2FA;
  final Function(User) onBindMiniProgram;
  final Function(User) onUnbindMiniProgram;

  const UserGrid({
    super.key,
    required this.users,
    required this.onEditUser,
    required this.onBind2FA,
    required this.onBindMiniProgram,
    required this.onUnbindMiniProgram,
  });

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.shield, size: 32, color: Colors.grey.shade300),
            ),
            const SizedBox(height: 16),
            Text(
              '该分组下暂无成员',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive Grid
        int crossAxisCount;
        double width = constraints.maxWidth;
        if (width >= 1600) {
          crossAxisCount = 5;
        } else if (width >= 1300) {
          crossAxisCount = 4;
        } else if (width >= 1000) {
          crossAxisCount = 3;
        } else if (width >= 700) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.15, // Adjust ratio for card height (lowered for mini program binding section)
          ),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return UserCard(
              user: user,
              onEdit: () => onEditUser(user),
              onBind2FA: () => onBind2FA(user),
              onBindMiniProgram: () => onBindMiniProgram(user),
              onUnbindMiniProgram: () => onUnbindMiniProgram(user),
            );
          },
        );
      },
    );
  }
}
