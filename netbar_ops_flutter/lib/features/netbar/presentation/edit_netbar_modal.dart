import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../data/netbar_api.dart';
import '../data/group_api.dart' as group_api;

/// 新增/编辑网吧弹窗 - 对应 Vue 的 AddNetbarDialog.vue
class EditNetbarModal extends StatefulWidget {
  /// 编辑模式时传入网吧对象，新增模式时为 null
  final Netbar? netbar;
  final VoidCallback? onSaved;
  final VoidCallback? onDeleted;

  const EditNetbarModal({
    super.key,
    this.netbar,
    this.onSaved,
    this.onDeleted,
  });

  /// 是否为新增模式
  bool get isCreateMode => netbar == null;

  @override
  State<EditNetbarModal> createState() => _EditNetbarModalState();
}

class _EditNetbarModalState extends State<EditNetbarModal> {
  final _netbarApi = NetbarApi();
  final _groupApi = group_api.GroupApi();

  late TextEditingController _nameController;
  late TextEditingController _terminalCountController;

  // 显式 FocusNode：用于干预 IME 在嵌套 Modal 下 reattach 失败的偶发问题
  final FocusNode _nameFocus = FocusNode(debugLabel: 'edit_netbar.name');
  final FocusNode _terminalFocus =
      FocusNode(debugLabel: 'edit_netbar.terminal');

  // 分组相关
  List<group_api.Group> _groupList = [];
  List<int> _selectedGroupIds = [];
  bool _loadingGroups = true;

  // 可管理人相关
  List<group_api.GroupUser> _userList = [];
  List<int> _selectedUserIds = [];
  bool _loadingUsers = true;

  bool _saving = false;
  bool _deleting = false;

  // 维护到期日期（null = 未设置），与 Web 端 maintenance_expired_at 对齐，提交格式 YYYY-MM-DD
  DateTime? _maintenanceExpiredAt;

  @override
  void initState() {
    super.initState();

    if (widget.isCreateMode) {
      // 新增模式：空值
      _nameController = TextEditingController();
      _terminalCountController = TextEditingController();
    } else {
      // 编辑模式：回填数据
      _nameController = TextEditingController(text: widget.netbar!.name);
      _terminalCountController = TextEditingController(
        text: widget.netbar!.terminalCount.toString(),
      );

      // 回填已选分组
      if (widget.netbar!.groups != null) {
        _selectedGroupIds = widget.netbar!.groups!.map((g) => g.id).toList();
      }

      // 回填已选用户
      if (widget.netbar!.users != null) {
        _selectedUserIds = widget.netbar!.users!.map((u) => u.id).toList();
      }

      // 回填维护到期：兼容 'YYYY-MM-DD' 与 'YYYY-MM-DD HH:mm:ss'，只取日期
      final rawExpired = widget.netbar!.maintenanceExpiredAt;
      if (rawExpired != null && rawExpired.isNotEmpty) {
        _maintenanceExpiredAt = DateTime.tryParse(rawExpired);
      }
    }

    HardwareKeyboard.instance.addHandler(_handleKey);
    _loadData();

    // 修复：嵌套 Modal 下中文 IME 偶发卡死（英文可输入但候选窗不弹）。
    // PostFrame unfocus 强制 clearClient，用户下一次点击 TextField 时框架会
    // 发起干净的 setClient → IME 正确关联到新 client。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _nameController.dispose();
    _terminalCountController.dispose();
    _nameFocus.dispose();
    _terminalFocus.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadGroups(),
      _loadUsers(),
    ]);
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _groupApi.getAll();
      if (mounted) {
        setState(() {
          _groupList = groups;
          _loadingGroups = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingGroups = false);
      }
    }
  }

  Future<void> _loadUsers() async {
    try {
      // 从分组列表中获取用户（GroupApi 返回的分组包含用户信息）
      final groups = await _groupApi.getAll();
      final users = <group_api.GroupUser>[];
      final seenIds = <int>{};

      for (final group in groups) {
        if (group.users != null) {
          for (final gu in group.users!) {
            if (!seenIds.contains(gu.id)) {
              seenIds.add(gu.id);
              users.add(gu);
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _userList = users;
          _loadingUsers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingUsers = false);
      }
    }
  }

  Future<void> _handleSave() async {
    // 表单验证
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showTopNotice(context, '请输入网吧名称', level: NoticeLevel.warning);
      return;
    }
    if (_selectedGroupIds.isEmpty) {
      showTopNotice(context, '请选择所属分组', level: NoticeLevel.warning);
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'name': name,
        'terminal_count': int.tryParse(_terminalCountController.text) ?? 0,
        'group_id': _selectedGroupIds.isNotEmpty ? _selectedGroupIds.first : null,
        'group_ids': _selectedGroupIds,
        'user_ids': _selectedUserIds,
        // 维护到期：YYYY-MM-DD；未设置/已清除则传空串，与 Web 端 clearable 行为一致
        'maintenance_expired_at':
            _maintenanceExpiredAt != null ? _fmtDate(_maintenanceExpiredAt!) : '',
      };

      if (widget.isCreateMode) {
        // 新增模式
        await _netbarApi.create(data);
        if (mounted) {
          showTopNotice(context, '创建成功', level: NoticeLevel.success);
        }
      } else {
        // 编辑模式
        await _netbarApi.update(widget.netbar!.id, data);
        if (mounted) {
          showTopNotice(context, '保存成功', level: NoticeLevel.success);
        }
      }

      widget.onSaved?.call();
      // 返回 true 通知调用方"已保存"，触发列表刷新（修复保存后重新打开仍显示旧值）
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '${widget.isCreateMode ? '创建' : '保存'}失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _handleDelete() async {
    if (widget.isCreateMode) return; // 新增模式不支持删除

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除网吧"${widget.netbar!.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _deleting = true);
    try {
      await _netbarApi.delete(widget.netbar!.id);
      widget.onDeleted?.call();
      if (mounted) {
        showTopNotice(context, '删除成功', level: NoticeLevel.success);
        // 返回 true 通知调用方"已删除"，触发列表刷新
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: widget.isCreateMode ? '新增网吧' : '编辑网吧',
      maxWidth: 500,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: _buildContent(),
      footer: _buildFooter(),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 网吧名称
          _buildFormField(
            label: '网吧名称',
            child: TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              decoration: _inputDecoration('请输入网吧名称'),
            ),
          ),
          const SizedBox(height: 16),

          // 终端数
          _buildFormField(
            label: '终端数',
            child: TextField(
              controller: _terminalCountController,
              focusNode: _terminalFocus,
              // 故意不设 keyboardType: 避免与相邻名称框的 InputScope 切换
              // 在 Flutter Windows engine 上偶发污染 IME 状态（候选窗不弹）。
              // digitsOnly formatter 已保证只能输入数字。
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDecoration('请输入终端数'),
            ),
          ),
          const SizedBox(height: 16),

          // 所属分组
          _buildFormField(
            label: '所属分组',
            child: _buildGroupSelector(),
          ),
          const SizedBox(height: 16),

          // 可管理人
          _buildFormField(
            label: '可管理人',
            child: _buildUserSelector(),
          ),
          const SizedBox(height: 16),

          // 维护到期
          _buildFormField(
            label: '维护到期',
            child: _buildMaintenanceSelector(),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  /// 分组多选器
  Widget _buildGroupSelector() {
    if (_loadingGroups) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return _buildMultiSelectChips(
      items: _groupList.map((g) => _SelectItem(id: g.id, label: g.name)).toList(),
      selectedIds: _selectedGroupIds,
      onChanged: (ids) => setState(() => _selectedGroupIds = ids),
      placeholder: '请选择分组',
    );
  }

  /// 用户多选器
  Widget _buildUserSelector() {
    if (_loadingUsers) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return _buildMultiSelectChips(
      items: _userList.map((u) => _SelectItem(id: u.id, label: u.nickname)).toList(),
      selectedIds: _selectedUserIds,
      onChanged: (ids) => setState(() => _selectedUserIds = ids),
      placeholder: '选择管理人',
    );
  }

  /// 格式化日期为 YYYY-MM-DD
  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// 维护到期日期选择器（点击弹日历，可清除，样式与其它字段统一）
  Widget _buildMaintenanceSelector() {
    final hasValue = _maintenanceExpiredAt != null;
    return InkWell(
      onTap: _pickMaintenanceDate,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? _fmtDate(_maintenanceExpiredAt!) : '选择维护到期日期',
                style: TextStyle(
                  fontSize: 14,
                  color: hasValue ? Colors.grey.shade800 : Colors.grey.shade400,
                ),
              ),
            ),
            // 有值时显示清除按钮（对应 Web 端 clearable）
            if (hasValue)
              InkWell(
                onTap: () => setState(() => _maintenanceExpiredAt = null),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close,
                      size: 16, color: Colors.grey.shade400),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 弹出日期选择器
  Future<void> _pickMaintenanceDate() async {
    final now = DateTime.now();
    final initial = _maintenanceExpiredAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      helpText: '选择维护到期日期',
    );
    if (picked != null) {
      setState(() => _maintenanceExpiredAt = picked);
    }
  }

  /// 多选 Chips 组件
  Widget _buildMultiSelectChips({
    required List<_SelectItem> items,
    required List<int> selectedIds,
    required ValueChanged<List<int>> onChanged,
    required String placeholder,
  }) {
    return InkWell(
      onTap: () => _showMultiSelectDialog(
        items: items,
        selectedIds: selectedIds,
        onChanged: onChanged,
        title: placeholder,
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Expanded(
              child: selectedIds.isEmpty
                  ? Text(
                      placeholder,
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: selectedIds.map((id) {
                        final item = items.firstWhere(
                          (i) => i.id == id,
                          orElse: () => _SelectItem(id: id, label: id.toString()),
                        );
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.iosBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.iosBlue,
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  final newIds = List<int>.from(selectedIds)..remove(id);
                                  onChanged(newIds);
                                },
                                child: Icon(
                                  LucideIcons.x,
                                  size: 14,
                                  color: AppColors.iosBlue.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            Icon(LucideIcons.chevronDown, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  /// 显示多选对话框
  void _showMultiSelectDialog({
    required List<_SelectItem> items,
    required List<int> selectedIds,
    required ValueChanged<List<int>> onChanged,
    required String title,
  }) {
    final tempSelected = List<int>.from(selectedIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16)),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          content: SizedBox(
            width: 300,
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('暂无数据')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (ctx, index) {
                      final item = items[index];
                      final isSelected = tempSelected.contains(item.id);
                      return CheckboxListTile(
                        value: isSelected,
                        title: Text(item.label, style: const TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              tempSelected.add(item.id);
                            } else {
                              tempSelected.remove(item.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                onChanged(tempSelected);
                Navigator.of(ctx).pop();
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      children: [
          // 删除按钮（仅编辑模式显示）
          if (!widget.isCreateMode)
            TextButton.icon(
              onPressed: _deleting ? null : _handleDelete,
              icon: _deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.trash2, size: 16),
              label: Text(_deleting ? '删除中...' : '删除'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
            ),
          const Spacer(),
          // 取消按钮
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '取消',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 保存按钮
          ElevatedButton(
            onPressed: _saving ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(widget.isCreateMode ? '创建' : '保存'),
          ),
        ],
    );
  }
}

/// 选项项
class _SelectItem {
  final int id;
  final String label;

  _SelectItem({required this.id, required this.label});
}
