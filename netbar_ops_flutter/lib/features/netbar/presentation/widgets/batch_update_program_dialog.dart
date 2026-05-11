import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/netbar_api.dart';
import 'netbar_multi_select_table.dart';

/// 批量更新程序对话框
/// 对标 Vue 端 BatchProgramUpdateDialog.vue
class BatchUpdateProgramDialog extends StatefulWidget {
  const BatchUpdateProgramDialog({super.key});

  @override
  State<BatchUpdateProgramDialog> createState() => _BatchUpdateProgramDialogState();
}

class _BatchUpdateProgramDialogState extends State<BatchUpdateProgramDialog> {
  List<Netbar> _netbars = [];
  List<GroupBrief> _groups = [];
  List<int> _selectedIds = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final api = NetbarApi();
      final result = await api.getListFull();
      if (!mounted) return;
      setState(() {
        _netbars = result.merchants;
        _groups = result.groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopNotice(context, '加载网吧列表失败：$e', level: NoticeLevel.error);
    }
  }

  Future<void> _handleConfirm() async {
    if (_submitting || _selectedIds.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final api = NetbarApi();
      await api.batchProgramUpdate(merchantIds: _selectedIds);
      if (!mounted) return;
      showTopNotice(context, '更新指令已下发', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '操作失败：$e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '批量更新程序',
      maxWidth: 640,
      maxHeight: 560,
      scrollableBody: false,
      bodyPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NetbarMultiSelectTable(
              netbars: _netbars,
              groups: _groups,
              onSelectionChanged: (ids) => setState(() => _selectedIds = ids),
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
            onPressed: (_submitting || _selectedIds.isEmpty) ? null : _handleConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('确认更新'),
          ),
        ],
      ),
    );
  }
}
