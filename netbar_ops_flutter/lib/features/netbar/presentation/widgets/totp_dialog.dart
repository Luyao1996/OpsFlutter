import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/netbar_api.dart';

/// 超级管理密码生成对话框
/// 对标 Vue 端 SuperPasswordDialog.vue
class TotpDialog extends StatefulWidget {
  const TotpDialog({super.key});

  @override
  State<TotpDialog> createState() => _TotpDialogState();
}

class _TotpDialogState extends State<TotpDialog> {
  DateTime _selectedDateTime = DateTime.now();
  String _password = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generatePassword();
  }

  String get _formattedTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(_selectedDateTime);

  /// 生成超级密码（对标 Vue 端 generatePassword 第 117-134 行）
  Future<void> _generatePassword() async {
    setState(() => _loading = true);
    try {
      final api = NetbarApi();
      final totp = await api.generateTotp(time: _formattedTime);
      if (!mounted) return;
      setState(() {
        _password = totp;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopNotice(context, '生成失败', level: NoticeLevel.error);
    }
  }

  /// 设置为当前时间并重新生成（对标 Vue 端 setCurrentTime）
  void _setCurrentTime() {
    setState(() => _selectedDateTime = DateTime.now());
    _generatePassword();
  }

  /// 选择日期时间
  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (time == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    _generatePassword();
  }

  /// 复制密码（对标 Vue 端 copyPassword）
  void _copyPassword() {
    if (_password.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _password));
    showTopNotice(context, '超级管理密码已复制到剪贴板', level: NoticeLevel.success);
  }

  @override
  Widget build(BuildContext context) {
    final digits = _password.split('');

    return ResponsiveDialogScaffold(
      title: '超级管理密码',
      maxWidth: 450,
      bodyPadding: const EdgeInsets.all(24),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
              // 时间选择区域（对标 Vue 端 time-section）
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    const Text('密码生成时间', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '默认使用当前时间，也可手动修改',
                      child: Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDateTime,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_formattedTime, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _setCurrentTime,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('当前时间', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // 密码展示区域（对标 Vue 端 password-section）
              const Text('超级管理密码', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      CircularProgressIndicator(strokeWidth: 2),
                      SizedBox(height: 10),
                      Text('生成中...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              else if (_password.isNotEmpty)
                GestureDetector(
                  onTap: _copyPassword,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: digits.map((digit) {
                      return Expanded(
                        child: Container(
                        height: 56,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Colors.white, Color(0xFFF5F7FA)],
                          ),
                          border: Border.all(color: const Color(0xFFE4E7ED), width: 2),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          digit,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: Color(0xFF303133),
                          ),
                        ),
                      ),
                      );
                    }).toList(),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('生成失败', style: TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 24),
              // 底部按钮（对标 Vue 端 dialog-footer）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_password.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _copyPassword,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        elevation: 0,
                      ),
                    ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _generatePassword,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}
