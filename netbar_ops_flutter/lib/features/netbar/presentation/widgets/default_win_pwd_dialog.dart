import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/group_api.dart';

/// 默认服务端Windows密码对话框
/// 对标 Vue 端 NetbarPage.vue 第 479-494 行 + useNetbarDataList.js 第 339-369 行
class DefaultWinPwdDialog extends ConsumerStatefulWidget {
  const DefaultWinPwdDialog({super.key});

  @override
  ConsumerState<DefaultWinPwdDialog> createState() => _DefaultWinPwdDialogState();
}

class _DefaultWinPwdDialogState extends ConsumerState<DefaultWinPwdDialog> {
  final _pwdController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pwdController.dispose();
    super.dispose();
  }

  /// 密码验证：>=8位，含大写+小写+数字
  /// 对标 Vue 端 useNetbarDataList.js 第 346 行
  String? _validatePassword(String pwd) {
    if (pwd.isEmpty) return '请输入默认密码';
    if (pwd.length < 8) return '密码长度至少8位';
    if (!RegExp(r'[A-Z]').hasMatch(pwd)) return '密码必须包含大写字母';
    if (!RegExp(r'[a-z]').hasMatch(pwd)) return '密码必须包含小写字母';
    if (!RegExp(r'[0-9]').hasMatch(pwd)) return '密码必须包含数字';
    return null;
  }

  Future<void> _confirm() async {
    final pwd = _pwdController.text.trim();
    final error = _validatePassword(pwd);
    if (error != null) {
      showTopNotice(context, error, level: NoticeLevel.error);
      return;
    }

    final user = ref.read(authNotifierProvider).user;
    final groupId = user?.groupId;
    if (groupId == null || groupId == 0) {
      showTopNotice(context, '总部用户无需设置默认密码', level: NoticeLevel.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      final groupApi = GroupApi();
      await groupApi.setPassword(groupId, password: pwd);
      if (!mounted) return;
      showTopNotice(context, '默认密码设置成功', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '保存失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '默认Windows密码',
      maxWidth: 360,
      bodyPadding: const EdgeInsets.all(24),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '请输入服务端Windows默认密码',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdController,
            decoration: const InputDecoration(
              hintText: '请输入服务端Windows默认密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '密码必须大于等于8位(大写+小写+数字)',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _saving ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('确认'),
          ),
        ],
      ),
    );
  }
}
