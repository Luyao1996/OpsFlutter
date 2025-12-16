import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';
import '../data/netbar_api.dart';
import '../data/area_api.dart';

/// 可编辑的区域
class EditableArea {
  int? id;
  String name;
  String startIp;
  String endIp;

  EditableArea({this.id, this.name = '', this.startIp = '', this.endIp = ''});

  factory EditableArea.fromNetbarArea(NetbarArea area) {
    return EditableArea(
      id: area.id,
      name: area.name,
      startIp: area.startIp,
      endIp: area.endIp,
    );
  }
}

/// 编辑网吧弹窗 - 对应 Vue 的 EditNetbarModal.vue
class EditNetbarModal extends StatefulWidget {
  final Netbar netbar;
  final VoidCallback? onSaved;

  const EditNetbarModal({super.key, required this.netbar, this.onSaved});

  @override
  State<EditNetbarModal> createState() => _EditNetbarModalState();
}

class _EditNetbarModalState extends State<EditNetbarModal> {
  final _netbarApi = NetbarApi();
  final _areaApi = AreaApi();

  late TextEditingController _nameController;
  late TextEditingController _terminalCountController;

  List<EditableArea> _areas = [];
  final List<int> _areasToDelete = [];
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.netbar.name);
    _terminalCountController = TextEditingController(
      text: widget.netbar.terminalCount.toString(),
    );
    HardwareKeyboard.instance.addHandler(_handleKey);
    _loadAreas();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _nameController.dispose();
    _terminalCountController.dispose();
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

  Future<void> _loadAreas() async {
    try {
      final areas = await _areaApi.getByNetbar(widget.netbar.id);
      setState(() {
        _areas = areas.map((a) => EditableArea.fromNetbarArea(a)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _addArea() {
    setState(() {
      _areas.add(EditableArea());
    });
  }

  void _removeArea(int index) {
    final area = _areas[index];
    if (area.id != null) {
      _areasToDelete.add(area.id!);
    }
    setState(() {
      _areas.removeAt(index);
    });
  }

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    try {
      // 1. 更新网吧基本信息
      await _netbarApi.update(widget.netbar.id, {
        'name': _nameController.text,
        'total_seats': int.tryParse(_terminalCountController.text) ?? 0,
      });

      // 2. 删除标记的区域
      for (final id in _areasToDelete) {
        await _areaApi.delete(id);
      }

      // 3. 更新或创建区域
      for (final area in _areas) {
        if (area.name.isEmpty) continue;
        if (area.id != null) {
          await _areaApi.update(
            area.id!,
            name: area.name,
            startIp: area.startIp,
            endIp: area.endIp,
          );
        } else {
          await _areaApi.create(
            widget.netbar.id,
            name: area.name,
            startIp: area.startIp.isNotEmpty ? area.startIp : null,
            endIp: area.endIp.isNotEmpty ? area.endIp : null,
          );
        }
      }

      widget.onSaved?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 100, vertical: 50),
      child: Container(
        width: 640,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.iosBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              LucideIcons.building2,
              size: 24,
              color: AppColors.iosBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '编辑网吧',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${widget.netbar.id}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              shape: const CircleBorder(),
            ),
            icon: Icon(LucideIcons.x, size: 18, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基本信息
          _buildSectionLabel('基本信息'),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              children: [
                _buildTextField(_nameController, '网吧名称'),
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Colors.grey.shade200,
                ),
                _buildTextField(
                  _terminalCountController,
                  '终端数量',
                  isNumber: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 区域配置
          _buildSectionLabel('区域配置'),
          _buildAreasSection(),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String placeholder, {
    bool isNumber = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(color: Colors.grey.shade400),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }

  Widget _buildAreasSection() {
    if (_loading) {
      return Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          ..._areas.asMap().entries.map(
            (entry) => _buildAreaRow(entry.key, entry.value),
          ),
          const SizedBox(height: 8),
          _buildAddAreaButton(),
        ],
      ),
    );
  }

  Widget _buildAreaRow(int index, EditableArea area) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(LucideIcons.gripVertical, size: 16, color: Colors.grey.shade300),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _buildAreaInput(area, 'name', '分区名称')),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _buildAreaInput(area, 'startIp', '开始 IP')),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: _buildAreaInput(area, 'endIp', '结束 IP')),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _removeArea(index),
            icon: Icon(
              LucideIcons.trash2,
              size: 16,
              color: Colors.grey.shade400,
            ),
            hoverColor: Colors.red.shade50,
            style: IconButton.styleFrom(foregroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaInput(EditableArea area, String field, String placeholder) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextField(
        controller: TextEditingController(
          text: field == 'name'
              ? area.name
              : (field == 'startIp' ? area.startIp : area.endIp),
        ),
        onChanged: (v) {
          if (field == 'name') {
            area.name = v;
          } else if (field == 'startIp')
            area.startIp = v;
          else
            area.endIp = v;
        },
        decoration: InputDecoration(
          hintText: placeholder,
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _buildAddAreaButton() {
    return GestureDetector(
      onTap: _addArea,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(
              '添加新分区',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.grey.shade50.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          // 删除按钮
          TextButton.icon(
            onPressed: () {}, // TODO: 实现删除
            icon: Icon(
              LucideIcons.trash2,
              size: 16,
              color: Colors.red.shade500,
            ),
            label: Text('删除档案', style: TextStyle(color: Colors.red.shade500)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          ElevatedButton.icon(
            onPressed: _saving ? null : _handleSave,
            icon: _saving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.save, size: 16),
            label: Text(_saving ? '保存中...' : '保存更改'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 4,
              shadowColor: AppColors.iosBlue.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
