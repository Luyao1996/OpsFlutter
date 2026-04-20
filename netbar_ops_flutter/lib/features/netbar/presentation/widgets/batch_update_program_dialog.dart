import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('批量更新程序', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else
                Expanded(
                  child: NetbarMultiSelectTable(
                    netbars: _netbars,
                    groups: _groups,
                    onSelectionChanged: (ids) => setState(() => _selectedIds = ids),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
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
            ],
          ),
        ),
      ),
    );
  }
}
