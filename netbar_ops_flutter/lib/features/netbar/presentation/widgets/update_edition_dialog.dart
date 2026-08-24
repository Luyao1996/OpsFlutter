import 'package:flutter/material.dart';
import '../../../../core/network/error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/edition_meta.dart';
import '../../data/netbar_api.dart';

void _log(String level, String contextId, String msg) {
  final ts = DateTime.now().toIso8601String();
  debugPrint('[$ts][$level][netbar][updateProgram][$contextId] $msg');
}

/// 单网吧「更新程序」完整流程，列表行 / 卡片两个入口共用：
/// - 总部管理员：先弹通道选择窗（对齐 web isHQAdmin 才走 openUpdateEditionDialog）；
/// - 其他角色：web 是点击即下发，Flutter 图标按钮更易误触，这里加一步简单确认，
///   下发时不带 type（不改通道）。
Future<void> runUpdateProgramFlow(
  BuildContext context,
  Netbar netbar, {
  required bool isTopManager,
}) async {
  String type;
  if (isTopManager) {
    final picked = await showAdaptive<String>(
      context,
      (context) => UpdateEditionDialog(netbar: netbar),
      routeName: '/dialog/update-edition',
    );
    if (picked == null) return;
    type = picked;
  } else {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('更新程序'),
        content: const Text('确认更新程序吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    type = '';
  }

  _log('INFO', '${netbar.id}', 'send type=${type.isEmpty ? 'keep' : type}');
  try {
    await NetbarApi().updateProgram(merchantId: netbar.id, type: type);
    if (!context.mounted) return;
    showTopNotice(context, '操作成功', level: NoticeLevel.success);
  } catch (e) {
    final msg = friendlyErrorMessage(e);
    _log('ERROR', '${netbar.id}', 'send fail err=$msg');
    if (!context.mounted) return;
    showTopNotice(context, '操作失败：$msg', level: NoticeLevel.error);
  }
}

/// 「选择版本后更新」弹窗，对齐 web 的 showUpdateEditionDialog：
/// 只负责选通道，确认后 pop 返回 type（'' = 不改变），下发由调用方执行
class UpdateEditionDialog extends StatefulWidget {
  final Netbar netbar;

  const UpdateEditionDialog({super.key, required this.netbar});

  @override
  State<UpdateEditionDialog> createState() => _UpdateEditionDialogState();
}

class _UpdateEditionDialogState extends State<UpdateEditionDialog> {
  /// '' 即「不改变」。web 因 el-select 空串无法回显选中态才用 'keep' 哨兵，
  /// Flutter Dropdown 没这个限制，直接用空串省一次转换
  String _choice = '';

  @override
  Widget build(BuildContext context) {
    final n = widget.netbar;
    final hasVersion = n.version != null && n.version!.isNotEmpty;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );

    return ResponsiveDialogScaffold(
      title: '选择版本后更新',
      maxWidth: 400,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasVersion ? '${n.name}（当前 v${n.version}）' : n.name,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _choice,
            isExpanded: true,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: border,
              enabledBorder: border,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
              ),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('不改变', style: TextStyle(fontSize: 14)),
              ),
              ...kEditionOptions.map((m) => DropdownMenuItem<String>(
                    value: m.value,
                    child: Text(m.label, style: const TextStyle(fontSize: 14)),
                  )),
            ],
            onChanged: (v) => setState(() => _choice = v ?? ''),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(_choice),
            child: const Text('确认更新'),
          ),
        ],
      ),
    );
  }
}
