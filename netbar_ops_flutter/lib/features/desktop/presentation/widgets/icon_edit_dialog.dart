import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/utils/icon_loader.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/desktop_model.dart';
import '../../data/desktop_api.dart';
import 'file_select_dialog.dart';

/// 图标编辑结果
class IconEditResult {
  final DesktopIconConfig config;
  final Uint8List? iconFile;
  final String? iconFileName;

  IconEditResult({
    required this.config,
    this.iconFile,
    this.iconFileName,
  });
}

/// 图标编辑弹窗
class IconEditDialog extends StatefulWidget {
  final DesktopIcon? initialIcon;
  final int? groupId;
  final int? netbarId;

  const IconEditDialog({
    super.key,
    this.initialIcon,
    this.groupId,
    this.netbarId,
  });

  @override
  State<IconEditDialog> createState() => _IconEditDialogState();
}

class _IconEditDialogState extends State<IconEditDialog> {
  late IconType _type;
  late TextEditingController _pathController;
  late TextEditingController _argsController;
  late TextEditingController _nameController;

  String? _iconUrl;
  Uint8List? _iconFile;
  String? _iconFileName;
  String? _groupFileId;
  String? _fileId;
  List<_IconItem> _iconList = [];
  int? _selectedIconIndex;
  bool _uploading = false;

  final IconApi _iconApi = IconApi();

  @override
  void initState() {
    super.initState();
    final config = widget.initialIcon?.config;

    _type = config?.type ?? IconType.file;
    _pathController = TextEditingController(text: config?.path ?? '');
    _argsController = TextEditingController(text: config?.parameter ?? '');
    _nameController = TextEditingController(text: config?.name ?? '');
    _iconUrl = config?.iconUrl ?? widget.initialIcon?.iconUrl;
    _groupFileId = config?.groupFileId;
    _fileId = config?.fileId;

    // 初始化图标列表
    _initIconList();
  }

  void _initIconList() {
    final config = widget.initialIcon?.config;

    // 添加当前图标URL
    if (_iconUrl != null && _iconUrl!.isNotEmpty) {
      _iconList.add(_IconItem(url: _iconUrl!, isDefault: false));
      _selectedIconIndex = 0;
    }

    // 添加files列表中的图标
    if (config?.files != null) {
      for (final file in config!.files) {
        if (file.url != null && file.url!.isNotEmpty) {
          final exists = _iconList.any((i) => i.url == file.url);
          if (!exists) {
            _iconList.add(_IconItem(
              url: file.url!,
              fileId: file.id,
              isDefault: file.isDefault,
            ));
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    _argsController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String _normalizeUrl(String url) {
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('data:')) {
      return url;
    }
    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final path = url.startsWith('/') ? url : '/$url';
    final token = TokenStore.getToken();
    final fullUrl = '$base$path';
    if (token == null || fullUrl.contains('token=')) return fullUrl;
    return '$fullUrl?token=$token';
  }

  Map<String, String>? _authHeaders() {
    final token = TokenStore.getToken();
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> _selectIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'ico'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() {
      _iconFile = file.bytes;
      _iconFileName = file.name;
      // 添加到图标列表
      final newItem = _IconItem(
        bytes: file.bytes,
        fileName: file.name,
        isDefault: false,
      );
      _iconList.add(newItem);
      _selectedIconIndex = _iconList.length - 1;
      _iconUrl = null;
      _fileId = null;
    });
  }

  void _selectIconItem(int index) {
    setState(() {
      _selectedIconIndex = index;
      final item = _iconList[index];
      if (item.bytes != null) {
        _iconFile = item.bytes;
        _iconFileName = item.fileName;
        _iconUrl = null;
        _fileId = null;
      } else {
        _iconUrl = item.url;
        _fileId = item.fileId;
        _iconFile = null;
        _iconFileName = null;
      }
    });
  }

  Future<void> _deleteIconItem(int index) async {
    final item = _iconList[index];

    // 如果是服务器端图标，调用删除接口
    if (item.fileId != null && widget.initialIcon?.id != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除图标'),
          content: const Text('确定要删除该图标吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await _iconApi.deleteIconFile(
          widget.initialIcon!.id,
          item.fileId!,
        );
        if (mounted) {
          showTopNotice(context, '删除成功', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
        }
        return;
      }
    }

    setState(() {
      _iconList.removeAt(index);
      if (_selectedIconIndex == index) {
        _selectedIconIndex = _iconList.isNotEmpty ? 0 : null;
        if (_iconList.isNotEmpty) {
          _selectIconItem(0);
        } else {
          _iconUrl = null;
          _iconFile = null;
          _iconFileName = null;
          _fileId = null;
        }
      } else if (_selectedIconIndex != null && _selectedIconIndex! > index) {
        _selectedIconIndex = _selectedIconIndex! - 1;
      }
    });
  }

  Future<void> _openFileDialog() async {
    final file = await showDialog<ServerFile>(
      context: context,
      builder: (context) => const FileSelectDialog(),
    );
    if (file == null) return;

    setState(() {
      _pathController.text = file.fullPath ?? file.path ?? file.name;
      if (_nameController.text.isEmpty) {
        // 从文件名提取名称（去掉扩展名）
        final name = file.name.replaceAll(RegExp(r'\.[^/.]+$'), '');
        _nameController.text = name;
      }
      _groupFileId = file.id.toString();
    });

    // 加载服务器返回的图标
    _loadServerIcon(file.id.toString());
  }

  Future<void> _loadServerIcon(String groupFileId) async {
    try {
      final iconUrl = await _iconApi.getFileIcon(groupFileId);
      if (iconUrl != null && iconUrl.isNotEmpty && mounted) {
        setState(() {
          final exists = _iconList.any((i) => i.url == iconUrl);
          if (!exists) {
            _iconList.insert(0, _IconItem(url: iconUrl, isDefault: true));
          }
          if (_selectedIconIndex == null || _iconList.length == 1) {
            _selectedIconIndex = 0;
            _iconUrl = iconUrl;
          }
        });
      }
    } catch (e) {
      debugPrint('加载文件图标失败: $e');
    }
  }

  void _confirm() {
    if (_nameController.text.isEmpty) {
      showTopNotice(context, '请填写名称', level: NoticeLevel.error);
      return;
    }

    // 验证文件/URL选择
    if (_type == IconType.file || _type == IconType.dir || _type == IconType.image) {
      if (_pathController.text.isEmpty) {
        showTopNotice(context, '请选择或输入文件路径', level: NoticeLevel.error);
        return;
      }
    } else if (_type == IconType.url) {
      if (_pathController.text.isEmpty) {
        showTopNotice(context, '请输入网址', level: NoticeLevel.error);
        return;
      }
    }

    // 验证图标
    if (_iconFile == null && _iconUrl == null && _groupFileId == null) {
      showTopNotice(context, '请上传图片或从文件列表选择已有文件', level: NoticeLevel.error);
      return;
    }

    final config = DesktopIconConfig(
      type: _type,
      path: _pathController.text,
      parameter: _type == IconType.file ? _argsController.text : _pathController.text,
      name: _nameController.text,
      iconUrl: _iconUrl,
      groupFileId: _groupFileId,
      fileId: _fileId,
    );

    Navigator.pop(
      context,
      IconEditResult(
        config: config,
        iconFile: _iconFile,
        iconFileName: _iconFileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialIcon != null;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFF0F2F5))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? '编辑图标' : '添加图标',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
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

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Form
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Type selector
                        _buildLabel('类型'),
                        const SizedBox(height: 8),
                        _buildTypeDropdown(),
                        const SizedBox(height: 16),

                        // Path/URL field
                        _buildLabel(_type == IconType.url ? '网址' : '位置'),
                        const SizedBox(height: 8),
                        _buildPathField(),
                        const SizedBox(height: 16),

                        // Args field (only for file type)
                        if (_type == IconType.file) ...[
                          _buildLabel('参数'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            _argsController,
                            hint: '启动参数（可选）',
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Name field
                        _buildLabel('名称'),
                        const SizedBox(height: 8),
                        _buildTextField(
                          _nameController,
                          hint: '程序名称',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Container(
                    width: 1,
                    height: 200,
                    color: const Color(0xFFF0F2F5),
                  ),
                  const SizedBox(width: 24),

                  // Right: Icon picker
                  SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('图标'),
                        const SizedBox(height: 12),
                        _buildIconPicker(),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE3E8F5))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 40),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<IconType>(
          value: _type,
          isExpanded: true,
          onChanged: (v) {
            if (v != null) setState(() => _type = v);
          },
          items: IconType.values.map((type) {
            return DropdownMenuItem(
              value: type,
              child: Text(type.label, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPathField() {
    if (_type == IconType.url) {
      return _buildTextField(
        _pathController,
        hint: '请输入网址 http://...',
      );
    }

    return Row(
      children: [
        Expanded(
          child: _buildTextField(
            _pathController,
            hint: _type == IconType.image ? '选择或输入图片路径' : '选择或输入文件路径',
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: _openFileDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: const Text('选择', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(TextEditingController controller, {String? hint}) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.iosBlue),
        ),
      ),
    );
  }

  Widget _buildIconPicker() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        // Add icon button
        _buildIconBox(
          child: InkWell(
            onTap: _uploading ? null : _selectIcon,
            borderRadius: BorderRadius.circular(8),
            child: _uploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.plus, size: 20, color: Colors.grey.shade600),
                      const SizedBox(height: 4),
                      Text(
                        '图片',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
          ),
          isDashed: true,
        ),

        // Icon list
        ..._iconList.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected = _selectedIconIndex == index;

          return _buildIconBox(
            isSelected: isSelected,
            child: Stack(
              children: [
                InkWell(
                  onTap: () => _selectIconItem(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: item.bytes != null
                        ? Image.memory(item.bytes!, fit: BoxFit.contain)
                        : NetworkIconImage(
                            url: _normalizeUrl(item.url!),
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              LucideIcons.image,
                              size: 24,
                              color: Colors.grey,
                            ),
                          ),
                  ),
                ),
                // Delete button
                if (!item.isDefault)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: InkWell(
                      onTap: () => _deleteIconItem(index),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          LucideIcons.x,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                // Check mark
                if (isSelected)
                  Positioned(
                    bottom: -6,
                    right: -6,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        LucideIcons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildIconBox({
    required Widget child,
    bool isSelected = false,
    bool isDashed = false,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFECF5FF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? AppColors.iosBlue
              : isDashed
                  ? Colors.grey.shade300
                  : Colors.grey.shade200,
          width: isDashed ? 1 : 1,
        ),
      ),
      child: child,
    );
  }
}

class _IconItem {
  final String? url;
  final Uint8List? bytes;
  final String? fileName;
  final String? fileId;
  final bool isDefault;

  _IconItem({
    this.url,
    this.bytes,
    this.fileName,
    this.fileId,
    this.isDefault = false,
  });
}
