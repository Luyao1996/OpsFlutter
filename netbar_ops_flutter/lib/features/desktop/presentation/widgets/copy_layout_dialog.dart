import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../netbar/data/netbar_api.dart';
import '../../data/desktop_model.dart';
import '../../data/desktop_api.dart';

/// 复制布局弹窗
class CopyLayoutDialog extends StatefulWidget {
  final int? currentNetbarId;
  final int? groupId;

  const CopyLayoutDialog({
    super.key,
    this.currentNetbarId,
    this.groupId,
  });

  @override
  State<CopyLayoutDialog> createState() => _CopyLayoutDialogState();
}

class _CopyLayoutDialogState extends State<CopyLayoutDialog> {
  final DesktopApi _desktopApi = DesktopApi();
  final NetbarApi _netbarApi = NetbarApi();
  final GlobalKey _dropdownKey = GlobalKey();

  List<Netbar> _netbarOptions = [];
  bool _loadingNetbars = true;
  String? _netbarError;

  int? _selectedNetbarId;
  List<DesktopLayout> _layouts = [];
  DesktopLayout? _selectedLayout;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNetbars();
  }

  List<Netbar> get _filteredNetbars {
    return _netbarOptions
        .where((n) => n.id != widget.currentNetbarId)
        .toList();
  }

  Future<void> _loadNetbars() async {
    setState(() {
      _loadingNetbars = true;
      _netbarError = null;
    });

    try {
      final response = await _netbarApi.getListFull(groupId: widget.groupId);
      setState(() {
        _netbarOptions = response.merchants;
        _loadingNetbars = false;
      });
    } catch (e) {
      setState(() {
        _netbarError = e.toString();
        _loadingNetbars = false;
      });
    }
  }

  Future<void> _loadLayouts(int netbarId) async {
    setState(() {
      _loading = true;
      _error = null;
      _layouts = [];
      _selectedLayout = null;
    });

    try {
      // 获取选中网吧所属的 group_id
      final selectedNetbar = _netbarOptions.firstWhere(
        (n) => n.id == netbarId,
        orElse: () => _netbarOptions.first,
      );
      final groupId = selectedNetbar.groups?.isNotEmpty == true
          ? selectedNetbar.groups!.first.id
          : widget.groupId;

      final layouts = await _desktopApi.getLayouts(
        netbarId: netbarId,
        groupId: groupId,
      );
      setState(() {
        _layouts = layouts.where((l) => l.resolution.isNotEmpty).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _confirm() {
    if (_selectedLayout == null) return;
    Navigator.pop(context, _selectedLayout);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '复制其他网吧配置',
      maxWidth: 400,
      bodyPadding: const EdgeInsets.all(20),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '选择网吧',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildNetbarDropdown(),
          const SizedBox(height: 16),
          if (_selectedNetbarId != null) ...[
            const Text(
              '选择分辨率',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _buildLayoutSelector(),
          ],
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _selectedLayout != null ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('确定复制'),
          ),
        ],
      ),
    );
  }

  Widget _buildNetbarDropdown() {
    if (_loadingNetbars) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('加载中...', style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }

    if (_netbarError != null) {
      return Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 16, color: Colors.red.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '加载失败',
                style: TextStyle(fontSize: 14, color: Colors.red.shade600),
              ),
            ),
            InkWell(
              onTap: _loadNetbars,
              child: Icon(LucideIcons.refreshCw, size: 16, color: Colors.red.shade600),
            ),
          ],
        ),
      );
    }

    final selectedNetbar = _selectedNetbarId != null
        ? _filteredNetbars.firstWhere(
            (n) => n.id == _selectedNetbarId,
            orElse: () => _filteredNetbars.first,
          )
        : null;
    final displayText = selectedNetbar != null
        ? selectedNetbar.name
        : '请选择网吧';

    return InkWell(
      key: _dropdownKey,
      onTap: () => _showNetbarMenu(),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedNetbarId != null ? Colors.black87 : Colors.grey.shade400,
                ),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  void _showNetbarMenu() {
    final RenderBox? renderBox = _dropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final items = _filteredNetbars.map((netbar) {
      return PopupMenuItem<int>(
        value: netbar.id,
        child: Text(
          netbar.name,
          style: const TextStyle(fontSize: 14),
        ),
      );
    }).toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可选择的其他网吧')),
      );
      return;
    }

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        position.dx + size.width,
        position.dy + size.height + 300,
      ),
      items: items,
      constraints: const BoxConstraints(maxHeight: 300, minWidth: 200),
    ).then((value) {
      if (value != null) {
        setState(() => _selectedNetbarId = value);
        _loadLayouts(value);
      }
    });
  }

  Widget _buildLayoutSelector() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 16, color: Colors.red.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '加载失败: $_error',
                style: TextStyle(fontSize: 13, color: Colors.red.shade600),
              ),
            ),
          ],
        ),
      );
    }

    if (_layouts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              '该网吧暂无布局配置',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _layouts.length,
        itemBuilder: (context, index) {
          final layout = _layouts[index];
          final isSelected = _selectedLayout?.id == layout.id;

          return InkWell(
            onTap: () => setState(() => _selectedLayout = layout),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE9F3FF) : Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.monitor,
                    size: 16,
                    color: isSelected ? AppColors.iosBlue : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      layout.resolution,
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected ? AppColors.iosBlue : Colors.black87,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(LucideIcons.check, size: 16, color: AppColors.iosBlue),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
