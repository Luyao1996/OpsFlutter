import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/user_mock_data.dart';

class TwoFactorDialog extends StatefulWidget {
  final User user;

  const TwoFactorDialog({super.key, required this.user});

  @override
  State<TwoFactorDialog> createState() => _TwoFactorDialogState();
}

class _TwoFactorDialogState extends State<TwoFactorDialog> {
  final TextEditingController _codeController = TextEditingController();
  final String _mockSecret = "66UXP57BWOPXUIXPZAAPTFXNVBLRIIMW";

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _handleCopy() {
    Clipboard.setData(ClipboardData(text: _mockSecret));
    showTopNotice(
      context,
      '密钥已复制',
      level: NoticeLevel.success,
      duration: const Duration(seconds: 1),
    );
  }

  void _handleConfirm() {
    if (_codeController.text.length == 6) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480, // max-w-lg in Vue (32rem = 512px), 480 is close and safe
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '扫码绑定 2FA',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(LucideIcons.x, size: 20, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // QR Code Section
                  Container(
                    width: 192,
                    height: 192,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        style: BorderStyle.solid,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Image.network(
                      'https://api.qrserver.com/v1/create-qr-code/?size=150x150&data=otpauth://totp/NetbarOps:admin?secret=$_mockSecret&issuer=NetbarOps',
                      width: 160,
                      height: 160,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        LucideIcons.qrCode,
                        size: 64,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '请使用身份验证器 (Microsoft Authenticator, Google Auth 等) 扫描上方二维码',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {}, // Link placeholder
                    child: const Text(
                      '下载身份验证器',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.iosBlue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Manual Entry Section
                  const Text(
                    '或者手动输入密钥',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB), // bg-gray-50
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _mockSecret,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 14,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: _handleCopy,
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              LucideIcons.copy,
                              size: 16,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Input & Buttons
                  TextField(
                    controller: _codeController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      letterSpacing: 8,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                    onChanged: (v) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '输入 6 位验证码',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        letterSpacing: 0,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.normal,
                      ),
                      counterText: '',
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
                        borderSide: const BorderSide(
                          color: AppColors.iosBlue,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFF3F4F6,
                            ), // bg-gray-100
                            foregroundColor: const Color(
                              0xFF374151,
                            ), // text-gray-700
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
                          onPressed: _codeController.text.length == 6
                              ? _handleConfirm
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.iosBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            disabledBackgroundColor: AppColors.iosBlue
                                .withOpacity(0.5),
                          ),
                          child: Text(
                            widget.user.is2FABound ? '重新绑定' : '确认绑定',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
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
