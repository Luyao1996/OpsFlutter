import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/user_api.dart';
import '../../data/user_mock_data.dart';

/// 2FA 绑定对话框 - 参考 toolboxweb UserPage.vue 实现
class TwoFactorDialog extends StatefulWidget {
  final User user;

  const TwoFactorDialog({super.key, required this.user});

  @override
  State<TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<TwoFactorDialog> {
  final TextEditingController _codeController = TextEditingController();
  final UserApi _userApi = UserApi();

  // 状态
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;

  // 2FA 数据
  String _secret = '';
  String _qrCode = '';
  Uint8List? _qrImageBytes;

  @override
  void initState() {
    super.initState();
    _loadTwoFactorAuth();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// 加载 2FA 密钥和二维码
  Future<void> _loadTwoFactorAuth() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await _userApi.getTwoFactorAuth(widget.user.id);

      if (mounted) {
        setState(() {
          _secret = response.secret;
          _qrCode = response.qrCode;
          _qrImageBytes = _decodeQrCode(response.qrCode);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '获取 2FA 信息失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  /// 解码二维码 Base64 数据
  Uint8List? _decodeQrCode(String qrCode) {
    if (qrCode.isEmpty) return null;

    try {
      String base64Data = qrCode;
      // 处理 data:image/png;base64, 前缀
      if (base64Data.contains(',')) {
        base64Data = base64Data.split(',').last;
      }
      return base64Decode(base64Data);
    } catch (e) {
      debugPrint('解码二维码失败: $e');
      return null;
    }
  }

  /// 复制密钥
  void _handleCopy() {
    if (_secret.isEmpty) return;

    Clipboard.setData(ClipboardData(text: _secret));
    showTopNotice(
      context,
      '密钥已复制',
      level: NoticeLevel.success,
      duration: const Duration(seconds: 1),
    );
  }

  /// 确认绑定
  Future<void> _handleConfirm() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      showTopNotice(context, '请输入 6 位验证码', level: NoticeLevel.warning);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _userApi.bindTwoFactorAuth(widget.user.id, code: code);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '绑定失败: $e', level: NoticeLevel.error);
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// 显示下载验证器对话框
  void _showDownloadDialog() {
    showDialog(
      context: context,
      builder: (context) => const _DownloadAuthenticatorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '绑定两步验证 (2FA)',
      maxWidth: 480,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: _buildContent(),
      footer: (_isLoading || _error != null) ? null : _buildButtons(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTwoFactorAuth,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 步骤 1: 扫描二维码
          _buildStep1(),
          const SizedBox(height: 24),

          // 步骤 2: 手动输入密钥
          _buildStep2(),
          const SizedBox(height: 24),

          // 步骤 3: 验证并绑定
          _buildStep3(),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      children: [
        // 二维码
        Container(
          width: 192,
          height: 192,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: _qrImageBytes != null
              ? Image.memory(
                  _qrImageBytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => _buildQrPlaceholder(),
                )
              : _buildQrPlaceholder(),
        ),
        const SizedBox(height: 16),

        // 步骤说明
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '1. 扫描二维码',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _showDownloadDialog,
              child: const Text(
                '下载验证器APP',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.iosBlue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '使用 Microsoft Authenticator 或其他验证器扫描上方二维码',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildQrPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.qrCode, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            '二维码加载失败',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. 或手动输入密钥',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  _secret,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFF374151),
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _handleCopy,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Text(
                    '复制',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. 验证并绑定',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _codeController,
          maxLength: 6,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            letterSpacing: 12,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
          onChanged: (v) => setState(() {}),
          decoration: InputDecoration(
            hintText: '输入6位动态验证码',
            hintStyle: TextStyle(
              fontSize: 14,
              letterSpacing: 0,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.normal,
            ),
            counterText: '',
            prefixIcon: Icon(LucideIcons.lock, size: 20, color: Colors.grey.shade400),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    final canSubmit = _codeController.text.length == 6 && !_isSubmitting;

    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF3F4F6),
              foregroundColor: const Color(0xFF374151),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '取消',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: canSubmit ? _handleConfirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
              disabledBackgroundColor: AppColors.iosBlue.withOpacity(0.5),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.user.isBind2fa ? '更新绑定' : '确认绑定',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 下载验证器对话框
class _DownloadAuthenticatorDialog extends StatelessWidget {
  const _DownloadAuthenticatorDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '下载身份验证器',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 推荐应用列表
              _buildAppItem(
                'Microsoft Authenticator',
                '推荐使用，支持云备份',
                LucideIcons.shield,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildAppItem(
                'Google Authenticator',
                '简单易用，跨平台',
                LucideIcons.smartphone,
                Colors.green,
              ),
              const SizedBox(height: 12),
              _buildAppItem(
                'Authy',
                '支持多设备同步',
                LucideIcons.key,
                Colors.red,
              ),

              const SizedBox(height: 20),
              Text(
                '请在应用商店搜索以上任意应用下载安装',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppItem(String name, String desc, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
