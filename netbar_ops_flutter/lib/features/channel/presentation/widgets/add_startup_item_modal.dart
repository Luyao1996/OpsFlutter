import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/startup_item_api.dart';
import '../../../netbar/data/area_api.dart';
import 'executable_path_picker_field.dart';

/// 释放文件配置（与 Web ConfigFile 对应）
class ConfigFile {
  String path;
  String content;
  String mode; // 'edit' | 'upload'
  String? fileName;

  ConfigFile({this.path = '', this.content = '', this.mode = 'edit', this.fileName});
}

/// IP范围（与 Web IpRange 对应）
class IpRange {
  String start;
  String end;

  IpRange({this.start = '', this.end = ''});
}

/// 新增启动项弹窗 - 与 Web AddStartupItemModal.vue 1:1 对齐
class AddStartupItemModal extends StatefulWidget {
  final String zone;
  final int? netbarId;
  final int? resourceId;
  final String? defaultPath;
  final String? defaultWorkingDir;
  final bool isAdmin; // 是否管理员
  final List<NetbarArea> areas; // 可用区域列表
  final VoidCallback onSuccess;

  const AddStartupItemModal({
    super.key,
    required this.zone,
    this.netbarId,
    this.resourceId,
    this.defaultPath,
    this.defaultWorkingDir,
    this.isAdmin = false,
    this.areas = const [],
    required this.onSuccess,
  });

  @override
  State<AddStartupItemModal> createState() => _AddStartupItemModalState();
}

class _AddStartupItemModalState extends State<AddStartupItemModal> {
  final StartupItemApi _api = StartupItemApi();
  final _formKey = GlobalKey<FormState>();

  // 基础字段
  final _displayNameController = TextEditingController(); // 启动项名称
  final _nameController = TextEditingController(); // 执行程序路径
  final _workingDirController = TextEditingController();
  final _argsController = TextEditingController();
  final _delayController = TextEditingController(text: '0');
  int? _selectedExeResourceId;

  // 基础设置（与 Web config 对应）
  bool _enabled = true;
  bool _forceRun = false;

  // 生效范围（与 Web 对应）
  List<String> _targetOs = []; // win7, win10, win11, win12
  List<String> _targetAreas = [];

  // 高级策略（与 Web 对应）
  bool _randomProcessName = false;
  bool _runAsService = false;
  String _crashAction = 'none'; // none, restart, reboot_os

  // 释放文件（与 Web releaseFiles 对应）
  List<ConfigFile> _releaseFiles = [];

  bool _saving = false;
  String? _error;

  // Windows 版本选项（与 Web WINDOWS_VERSIONS 对应）
  static const List<String> _windowsVersions = ['win7', 'win10', 'win11', 'win12'];

  @override
  void initState() {
    super.initState();
    _selectedExeResourceId = widget.resourceId;
    if (widget.defaultPath != null) {
      _nameController.text = widget.defaultPath!;
    }
    if (widget.defaultWorkingDir != null) {
      _workingDirController.text = widget.defaultWorkingDir!;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _nameController.dispose();
    _workingDirController.dispose();
    _argsController.dispose();
    _delayController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameController.text.trim().isEmpty) return;

    setState(() { _saving = true; _error = null; });
    try {
      // 清理释放文件（移除 UI 状态字段）
      final cleanFiles = _releaseFiles
          .where((f) => f.path.isNotEmpty)
          .map((f) => {'path': f.path, 'content': f.content})
          .toList();

      await _api.create(
        resourceId: _selectedExeResourceId ?? widget.resourceId,
        netbarId: widget.netbarId,
        name: _nameController.text.trim(),
        displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
        path: _nameController.text.trim(), // 与 Web 一致：name 即为路径
        zone: widget.zone,
        enabled: _enabled,
        args: _argsController.text.isEmpty ? null : _argsController.text,
        delay: int.tryParse(_delayController.text) ?? 0,
        forceRun: _forceRun,
        workingDir: _workingDirController.text.isEmpty ? null : _workingDirController.text,
        targetOs: _targetOs.isEmpty ? null : _targetOs.join(','),
        targetAreas: _targetAreas.isEmpty ? null : _targetAreas.join(','),
        crashAction: _crashAction,
        runAsService: _runAsService,
        randomProcessName: _randomProcessName,
        releaseFiles: cleanFiles.isEmpty ? null : cleanFiles,
      );
      widget.onSuccess();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建成功: ${_displayNameController.text.trim().isNotEmpty ? _displayNameController.text.trim() : _nameController.text.trim()}'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _error = '保存失败: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  void _handleOsChange(String os) {
    setState(() {
      if (_targetOs.contains(os)) {
        _targetOs.remove(os);
      } else {
        _targetOs.add(os);
      }
    });
  }

  void _handleAreaChange(String areaName) {
    setState(() {
      if (_targetAreas.contains(areaName)) {
        _targetAreas.remove(areaName);
      } else {
        _targetAreas.add(areaName);
      }
    });
  }

  void _addFile() {
    setState(() {
      _releaseFiles.add(ConfigFile());
    });
  }

  void _removeFile(int index) {
    setState(() {
      _releaseFiles.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 700,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: SingleChildScrollView(child: _buildForm())),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.iosBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(LucideIcons.zap, size: 20, color: AppColors.iosBlue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新增启动项', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('创建一个新的开机自动运行任务', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, size: 20, color: Colors.grey.shade400),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 启动项名称和执行程序路径
            _buildSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('启动项名称 (可选)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _displayNameController,
                    decoration: _inputDecoration('例如: Steam游戏平台'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    autofocus: true,
                  ),
                  const SizedBox(height: 4),
                  Text('用于显示的名称，不填则使用程序路径', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  const SizedBox(height: 16),
                  _buildLabel('执行程序路径/文件名', required: true),
                  const SizedBox(height: 8),
                  ExecutablePathPickerField(
                    controller: _nameController,
                    validator: (v) => v == null || v.isEmpty ? '请选择执行程序路径' : null,
                    decoration: _inputDecoration('请选择 exe 文件'),
                    onSelected: (r) => setState(() => _selectedExeResourceId = r.id),
                  ),
                  const SizedBox(height: 4),
                  Text('从资源管理中选择可执行文件', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  const SizedBox(height: 16),
                  _buildLabel('程序运行目录 (可选)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _workingDirController,
                    decoration: _inputDecoration('例如: C:\\Games\\Pubg'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              highlighted: true,
            ),
            const SizedBox(height: 24),

            // 释放文件配置
            _buildReleaseFilesSection(),
            const SizedBox(height: 24),

            // 基础设置
            _buildBasicSettingsSection(),
            const SizedBox(height: 24),

            // 生效范围
            _buildTargetRangeSection(),
            const SizedBox(height: 24),

            // 高级策略
            _buildAdvancedSettingsSection(),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.alertCircle, size: 16, color: Colors.red.shade600),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(fontSize: 12, color: Colors.red.shade600))),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseFilesSection() {
    return _buildSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.fileText, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  _buildLabel('释放文件 (可选)'),
                ],
              ),
              TextButton.icon(
                onPressed: _addFile,
                icon: const Icon(LucideIcons.plus, size: 12),
                label: const Text('添加文件', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.iosBlue,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_releaseFiles.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
              ),
              child: Center(
                child: Text('暂无需要释放的配置文件或脚本', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              ),
            )
          else
            ...List.generate(_releaseFiles.length, (index) => _buildFileItem(index)),
        ],
      ),
    );
  }

  Widget _buildFileItem(int index) {
    final file = _releaseFiles[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('目标路径 (相对或绝对)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: file.path,
                      onChanged: (v) => file.path = v,
                      decoration: _inputDecoration('例如: config.ini 或 C:\\Config\\settings.cfg').copyWith(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _removeFile(index),
                icon: Icon(LucideIcons.trash2, size: 14, color: Colors.red.shade400),
                splashRadius: 16,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 模式选择
          Row(
            children: [
              _buildRadioOption('直接编辑内容', file.mode == 'edit', () => setState(() => file.mode = 'edit')),
              const SizedBox(width: 16),
              _buildRadioOption('上传文件', file.mode == 'upload', () => setState(() => file.mode = 'upload')),
            ],
          ),
          const SizedBox(height: 8),
          if (file.mode == 'edit')
            TextFormField(
              initialValue: file.content,
              onChanged: (v) => file.content = v,
              maxLines: 3,
              decoration: _inputDecoration('在此输入文件内容...').copyWith(
                contentPadding: const EdgeInsets.all(8),
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.upload, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(file.fileName ?? '点击选择文件', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRadioOption(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.iosBlue : Colors.grey.shade400, width: 2),
            ),
            child: selected
                ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.iosBlue)))
                : null,
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _buildBasicSettingsSection() {
    return _buildSection(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('基础设置'),
          const SizedBox(height: 16),
          // 开机自动运行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('开机自动运行', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: const Color(0xFF22C55E),
              ),
            ],
          ),
          // 强制下级执行（仅管理员可见）
          if (widget.isAdmin) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 20, height: 20,
                  child: Checkbox(
                    value: _forceRun,
                    onChanged: (v) => setState(() => _forceRun = v ?? false),
                    activeColor: AppColors.iosBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Text('强制下级执行 (分公司不可禁用)', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          // 启动参数和延时
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('启动参数', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _argsController,
                      decoration: _inputDecoration('-silent -minimized'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('延时启动 (秒)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _delayController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('0'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetRangeSection() {
    return _buildSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              _buildLabel('生效范围'),
            ],
          ),
          const SizedBox(height: 16),
          // 指定操作系统
          Text('指定操作系统', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _windowsVersions.map((os) {
              final isSelected = _targetOs.contains(os);
              return GestureDetector(
                onTap: () => _handleOsChange(os),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => _handleOsChange(os),
                        activeColor: AppColors.iosBlue,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(os.toUpperCase(), style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    const SizedBox(width: 12),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          // 指定网吧区域
          Text('指定网吧区域', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          if (widget.areas.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.areas.map((area) {
                final isSelected = _targetAreas.contains(area.name);
                return GestureDetector(
                  onTap: () => _handleAreaChange(area.name),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.purple.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? Colors.purple : Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => _handleAreaChange(area.name),
                            activeColor: Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(area.name, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Text('当前网吧未配置区域', style: TextStyle(fontSize: 13, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildAdvancedSettingsSection() {
    return _buildSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cpu, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              _buildLabel('高级策略'),
            ],
          ),
          const SizedBox(height: 16),
          // 随机进程名
          _buildAdvancedRow(
            icon: LucideIcons.shuffle,
            iconColor: Colors.purple,
            title: '随机进程名',
            subtitle: '启动时随机重命名 EXE 文件',
            value: _randomProcessName,
            onChanged: (v) => setState(() => _randomProcessName = v),
          ),
          Divider(color: Colors.grey.shade100, height: 24),
          // 作为系统服务运行
          _buildAdvancedRow(
            icon: LucideIcons.activity,
            iconColor: AppColors.iosBlue,
            title: '作为系统服务运行',
            subtitle: '以 SYSTEM 权限在后台静默运行',
            value: _runAsService,
            onChanged: (v) => setState(() => _runAsService = v),
          ),
          Divider(color: Colors.grey.shade100, height: 24),
          // 进程崩溃动作
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('进程崩溃动作', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _crashAction,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('无动作', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'restart', child: Text('自动重启进程', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'reboot_os', child: Text('重启操作系统', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) => setState(() => _crashAction = v ?? 'none'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: iconColor,
        ),
      ],
    );
  }

  Widget _buildSection({required Widget child, Color? color, bool highlighted = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlighted ? Colors.grey.shade200 : Colors.grey.shade100),
        boxShadow: highlighted ? [BoxShadow(color: Colors.grey.shade100, blurRadius: 8, spreadRadius: 2)] : null,
      ),
      child: child,
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5),
        ),
        if (required)
          Text(' *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade500)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.iosBlue, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('取消', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _saving || _nameController.text.isEmpty ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('添加启动项', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
