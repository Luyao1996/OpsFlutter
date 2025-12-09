import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../channel/presentation/platform_helper.dart';
import '../../channel/presentation/drop_target_stub.dart'
    if (dart.library.io) 'package:desktop_drop/desktop_drop.dart';
import '../../channel/presentation/web_drop_zone.dart';
import '../../channel/presentation/widgets/upload_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../channel/data/resource_api.dart';
import '../../channel/data/startup_item_api.dart';
import '../../netbar/data/area_api.dart';
import '../../channel/presentation/widgets/add_startup_item_modal.dart';
import '../../channel/presentation/widgets/context_menu.dart';
import '../../channel/presentation/widgets/file_editor_modal.dart';
import '../../channel/presentation/widgets/file_icon.dart';
import '../../channel/presentation/widgets/disable_startup_modal.dart';
import '../../channel/presentation/widgets/startup_config_modal.dart';
import '../../channel/presentation/widgets/upload_modal.dart';
import '../../../shared/providers/upload_queue_provider.dart';

/// 资源区域 - 资源管理用三个区域
enum ResourceZone { headquarters, branch, shared }

/// 模块标签
enum ModuleTab { files, startup }

/// 布局模式
enum LayoutMode { grid, list }

/// 面包屑项
class BreadcrumbItem {
  final int? id;
  final String name;
  BreadcrumbItem({this.id, required this.name});
}

/// 资源管理页面
class ResourceManagementPage extends ConsumerStatefulWidget {
  const ResourceManagementPage({super.key});

  @override
  ConsumerState<ResourceManagementPage> createState() =>
      _ResourceManagementPageState();
}

class _ResourceManagementPageState
    extends ConsumerState<ResourceManagementPage> {
  final ResourceApi _resourceApi = ResourceApi();
  final StartupItemApi _startupItemApi = StartupItemApi();
  final AreaApi _areaApi = AreaApi();

  bool _isMobileFlag = false;
  bool get _isMobile => _isMobileFlag;

  ResourceZone _currentZone = ResourceZone.headquarters;
  ModuleTab _activeModule = ModuleTab.files;
  LayoutMode _layoutMode = LayoutMode.grid;

  String _searchQuery = '';
  int? _currentFolderId;
  List<BreadcrumbItem> _folderHistory = [
    BreadcrumbItem(id: null, name: '根目录')
  ];

  List<Resource> _files = [];
  List<Resource> _searchResults = []; // 搜索结果
  bool _isSearching = false; // 是否正在搜索模式
  List<StartupItem> _startupItems = [];
  List<NetbarArea> _areas = [];
  Set<String> _selectedIds = {};
  Set<int> _draggingFileIds = {};
  int? _dropTargetFolderId;

  bool _loading = false;
  String? _error;

  // 拖选相关状态
  bool _isDragSelecting = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;
  final GlobalKey _gridKey = GlobalKey();

  // 拖选矩形
  Rect? get _selectionRect {
    if (!_isDragSelecting || _dragStartPosition == null || _dragCurrentPosition == null) {
      return null;
    }
    return Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
  }

  // 剪贴板
  List<Resource> _clipboard = [];
  bool _isCut = false;
  bool _isExternalDragOver = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    if (kIsWeb) {
      _registerWebDropZone();
      _registerWebPasteHandler();
    }
  }

  List<StartupItem> get _selectedStartupItems {
    return _startupItems.where((s) => _selectedIds.contains('startup-${s.id}')).toList();
  }

  bool get _canDisableStartupItem => true;
  bool get _canDeleteStartupItem => _isAdmin;

  Future<void> _handleBatchStartupEnable(bool enable) async {
    for (final item in _selectedStartupItems) {
      if (enable) {
        await _startupItemApi.enable(item.id);
      } else {
        await _startupItemApi.disable(item.id, item.enabledState);
      }
    }
    _loadData();
  }

  Future<void> _handleBatchStartupDelete() async {
    for (final item in _selectedStartupItems) {
      await _startupItemApi.delete(item.id);
    }
    _loadData();
  }

  Widget _buildSearchField({double width = 160}) {
    return SizedBox(
      width: width,
      height: 32,
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: '搜索文件...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          contentPadding: EdgeInsets.zero,
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.iosBlue),
          ),
        ),
        style: const TextStyle(fontSize: 12),
        textAlignVertical: TextAlignVertical.center,
      ),
    );
  }

  Widget _buildLayoutToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLayoutButton(LayoutMode.grid, LucideIcons.layoutGrid),
          _buildLayoutButton(LayoutMode.list, LucideIcons.list),
        ],
      ),
    );
  }

  Widget _buildUploadButton() {
    return ElevatedButton.icon(
      onPressed: _canEdit ? _showUploadModal : null,
      icon: const Icon(LucideIcons.upload, size: 14),
      label: const Text('上传'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    if (kIsWeb) {
      webDropHandler.unregisterDropZone();
      webDropHandler.unregisterPasteHandler();
    }
    super.dispose();
  }

  void _registerWebDropZone() {
    webDropHandler.registerDropZone(
      onDragEnter: () {
        if (mounted) setState(() => _isExternalDragOver = true);
      },
      onDragLeave: () {
        if (mounted) setState(() => _isExternalDragOver = false);
      },
      onDrop: _handleWebDrop,
    );
  }

  void _registerWebPasteHandler() {
    webDropHandler.registerPasteHandler(onPaste: _handleWebPaste);
  }

  /// 检查是否需要解压ZIP文件
  /// 如果只有一个文件或全是ZIP文件，弹窗询问用户是否解压
  Future<bool> _askExtractZip(List<String> fileNames) async {
    // 检查是否只有一个文件或全是ZIP文件
    final zipFiles = fileNames.where((name) => name.toLowerCase().endsWith('.zip')).toList();

    // 如果没有ZIP文件，不需要解压
    if (zipFiles.isEmpty) return false;

    // 如果只有一个文件且是ZIP，或者全是ZIP文件，弹窗询问
    final shouldAsk = fileNames.length == 1 || zipFiles.length == fileNames.length;
    if (!shouldAsk) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ZIP文件处理'),
        content: Text(
          zipFiles.length == 1
            ? '检测到ZIP文件 "${zipFiles.first}"，是否在服务器端自动解压？'
            : '检测到 ${zipFiles.length} 个ZIP文件，是否在服务器端自动解压？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('直接上传'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('解压上传'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleWebDrop(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    if (mounted) setState(() => _isExternalDragOver = false);

    // 检查是否需要解压ZIP
    final fileNames = files.where((f) => !f.isDirectory).map((f) => f.name).toList();
    final extractZip = await _askExtractZip(fileNames);

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _getZoneString();
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id =
          'web-drop-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
      final isZip = file.name.toLowerCase().endsWith('.zip');
      tasks.add(UploadTask(
        id: id,
        name: file.name,
        size: file.bytes.length,
        isDirectory: file.isDirectory,
        relativePath: file.relativePath,
        parentId: _currentFolderId,
        zone: zone,
        netbarId: netbarId,
        bytes: file.isDirectory ? null : file.bytes,
        progress: file.isDirectory ? 100 : 0,
        status: file.isDirectory ? UploadStatus.success : UploadStatus.pending,
        extractZip: extractZip && isZip,
      ));
    }

    notifier.enqueue(tasks);
    _loadData();
  }

  Future<void> _handleWebPaste(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('粘贴')) return;
    if (_activeModule != ModuleTab.files) return;
    if (files.isEmpty) return;

    // 检查是否需要解压ZIP
    final fileNames = files.where((f) => !f.isDirectory).map((f) => f.name).toList();
    final extractZip = await _askExtractZip(fileNames);

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _getZoneString();
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id =
          'web-paste-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
      final isZip = file.name.toLowerCase().endsWith('.zip');
      tasks.add(UploadTask(
        id: id,
        name: file.name,
        size: file.bytes.length,
        isDirectory: file.isDirectory,
        relativePath: file.relativePath,
        parentId: _currentFolderId,
        zone: zone,
        netbarId: netbarId,
        bytes: file.isDirectory ? null : file.bytes,
        progress: file.isDirectory ? 100 : 0,
        status: file.isDirectory ? UploadStatus.success : UploadStatus.pending,
        extractZip: extractZip && isZip,
      ));
    }

    notifier.enqueue(tasks);
    _loadData();
  }

  /// 处理系统剪贴板粘贴（桌面端）
  Future<void> _handleSystemClipboardPaste() async {
    if (!_canEdit) return;
    if (kIsWeb) return; // Web 端由 _handleWebPaste 处理

    try {
      // 从系统剪贴板获取文件路径
      final paths = await platformFileHelper.getClipboardFilePaths();
      if (paths.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('剪贴板中没有文件')),
          );
        }
        return;
      }

      // 读取文件内容
      final items = await platformFileHelper.readFilesFromPaths(paths);
      if (items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法读取剪贴板中的文件')),
          );
        }
        return;
      }

      // 创建上传任务
      final notifier = ref.read(uploadQueueProvider.notifier);
      final tasks = <UploadTask>[];
      var counter = 0;
      final zone = _getZoneString();
      final netbarId = _getNetbarId();

      for (final item in items) {
        final id = 'clipboard-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
        tasks.add(UploadTask(
          id: id,
          name: item.name,
          size: item.bytes?.length ?? 0,
          isDirectory: item.isDirectory,
          relativePath: item.relativePath,
          parentId: _currentFolderId,
          zone: zone,
          netbarId: netbarId,
          bytes: item.bytes,
          progress: item.isDirectory ? 100 : 0,
          status: item.isDirectory ? UploadStatus.success : UploadStatus.pending,
        ));
      }

      notifier.enqueue(tasks);
      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加 ${tasks.length} 个项目到上传队列')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('粘贴失败: $e')),
        );
      }
    }
  }

  bool _handleKeyboard(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    // Escape - 清除选择
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _selectedIds.clear());
      return true;
    }

    // 只在文件模块处理快捷键
    if (_activeModule != ModuleTab.files) return false;

    // Ctrl+C - 复制
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_selectedResources.isNotEmpty) {
        _handleBatchCopy();
        return true;
      }
    }

    // Ctrl+X - 剪切
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (_selectedResources.isNotEmpty && _canEdit) {
        _handleBatchCut();
        return true;
      }
    }

    // Ctrl+V - 粘贴
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_canEdit) {
        if (_clipboard.isNotEmpty) {
          // 内部剪贴板有内容，执行内部粘贴
          _handlePaste();
          return true;
        } else {
          // 尝试从系统剪贴板读取文件（桌面端）
          _handleSystemClipboardPaste();
          return true;
        }
      }
    }

    // Ctrl+A - 全选
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      setState(() {
        _selectedIds.clear();
        for (final file in _files) {
          _selectedIds.add(file.id.toString());
        }
      });
      return true;
    }

    // Delete - 删除
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      if (_selectedResources.isNotEmpty && _canEdit) {
        _handleBatchDelete();
        return true;
      }
    }

    return false;
  }

  /// 获取区域字符串 (API 参数)
  String _getZoneString() {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return 'HEADQUARTERS';
      case ResourceZone.branch:
        return 'BRANCH';
      case ResourceZone.shared:
        return 'SHARED';
    }
  }

  /// 获取有效的 netbar_id（用于资源管理）
  /// - 总部(HEADQUARTERS): netbar_id = 0
  /// - 分公司(BRANCH): netbar_id = 用户的分组ID
  /// - 共享区(SHARED): 所有人可访问
  int? _getNetbarId() {
    final auth = ref.read(authNotifierProvider);
    final user = auth.user;

    switch (_currentZone) {
      case ResourceZone.headquarters:
        return 0; // 总部
      case ResourceZone.branch:
        // 分公司用用户的分组ID，这里简化处理
        return user?.id ?? 0;
      case ResourceZone.shared:
        return null; // 共享区不需要 netbar_id
    }
  }

  bool get _isAdmin {
    final auth = ref.watch(authNotifierProvider);
    final role = auth.user?.role.toLowerCase() ?? '';
    return role.contains('admin');
  }

  /// 是否可以编辑当前区域
  bool get _canEdit {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return _isAdmin; // 总部资源只有管理员可编辑
      case ResourceZone.branch:
        return !_isAdmin; // 分公司资源：非管理员可编辑自己公司的
      case ResourceZone.shared:
        return true; // 共享区所有人可上传
    }
  }

  /// 是否可以查看当前区域
  bool get _canView {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return true; // 所有人可查看总部资源
      case ResourceZone.branch:
        return !_isAdmin; // 分公司资源：管理员不显示，其他人可看自己公司的
      case ResourceZone.shared:
        return true; // 共享区所有人可查看
    }
  }

  String _editDeniedReason() {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return '总部资源仅管理员可编辑';
      case ResourceZone.branch:
        return '分公司资源仅分公司成员可编辑';
      case ResourceZone.shared:
        return '需要登录后才能上传到共享区';
    }
  }

  bool _ensureCanEdit(String actionLabel) {
    if (_canEdit) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$actionLabel失败：${_editDeniedReason()}')),
    );
    return false;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_activeModule == ModuleTab.files) {
        final resources = await _resourceApi.getAll(
          zone: _getZoneString(),
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
        );
        if (mounted) setState(() => _files = resources);
      } else {
        final items = await _startupItemApi.getAll(
          zone: _getZoneString(),
          netbarId: _getNetbarId(),
        );
        if (mounted) setState(() => _startupItems = items);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleZoneChange(ResourceZone zone) {
    // 分公司资源对管理员不显示
    if (zone == ResourceZone.branch && _isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理员不显示分公司资源')),
      );
      return;
    }
    setState(() {
      _currentZone = zone;
      _currentFolderId = null;
      _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleModuleChange(ModuleTab module) {
    setState(() {
      _activeModule = module;
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleBreadcrumbClick(int index) {
    setState(() {
      _currentFolderId = _folderHistory[index].id;
      _folderHistory = _folderHistory.sublist(0, index + 1);
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleFolderOpen(Resource folder) {
    setState(() {
      _currentFolderId = folder.id;
      _folderHistory.add(BreadcrumbItem(id: folder.id, name: folder.name));
      _selectedIds.clear();
    });
    _loadData();
  }

  List<Resource> get _filteredFiles {
    // 如果正在搜索模式，返回搜索结果
    if (_isSearching && _searchQuery.isNotEmpty) {
      return _searchResults;
    }
    // 否则返回当前目录的文件（后端已经按目录过滤）
    var files = _files.toList();
    // 目录在前，按名称排序
    files.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.compareTo(b.name);
    });
    return files;
  }

  List<StartupItem> get _filteredStartupItems {
    var items = _startupItems.toList();
    if (_searchQuery.isNotEmpty) {
      items = items
          .where((f) =>
              f.effectiveDisplayName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()))
          .toList();
    }
    return items;
  }

  /// 执行后端搜索
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
        _searchQuery = '';
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearching = true;
      _loading = true;
    });

    try {
      final results = await _resourceApi.search(
        keyword: query,
        zone: _getZoneString(),
        netbarId: _getNetbarId(),
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '搜索失败: $e';
          _loading = false;
        });
      }
    }
  }

  /// 清除搜索
  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
    });
  }

  List<Resource> get _selectedResources {
    return _files
        .where((f) => _selectedIds.contains(f.id.toString()))
        .toList();
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDragSelecting = true;
      _dragStartPosition = details.localPosition;
      _dragCurrentPosition = details.localPosition;
      if (!HardwareKeyboard.instance.isControlPressed) {
        _selectedIds.clear();
      }
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isDragSelecting) return;
    setState(() {
      _dragCurrentPosition = details.localPosition;
    });
    _updateDragSelection();
  }

  void _handleDragEnd(DragEndDetails details) {
    setState(() {
      _isDragSelecting = false;
      _dragStartPosition = null;
      _dragCurrentPosition = null;
    });
  }

  void _updateDragSelection() {
    if (_dragStartPosition == null || _dragCurrentPosition == null) return;

    final rect = Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
    final files = _filteredFiles;

    final gridWidth = _gridKey.currentContext?.size?.width ?? 800;
    if (_layoutMode == LayoutMode.grid) {
      // 与 _buildFileGrid 中的参数保持一致
      const maxCrossAxisExtent = 120.0;
      const spacing = 16.0;
      const childAspectRatio = 0.85;

      // 计算实际的列数和项目尺寸
      final crossAxisCount = (gridWidth / (maxCrossAxisExtent + spacing)).ceil().clamp(1, 100);
      final itemWidth = (gridWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
      final itemHeight = itemWidth / childAspectRatio;

      for (int i = 0; i < files.length; i++) {
        final row = i ~/ crossAxisCount;
        final col = i % crossAxisCount;
        final left = col * (itemWidth + spacing);
        final top = row * (itemHeight + spacing);
        final itemRect = Rect.fromLTWH(left, top, itemWidth, itemHeight);
        if (rect.overlaps(itemRect)) {
          _selectedIds.add(files[i].id.toString());
        }
      }
    } else {
      // list view: each row full width with fixed height
      const rowHeight = 64.0;
      for (int i = 0; i < files.length; i++) {
        final top = i * (rowHeight + 8); // separator 8
        final itemRect = Rect.fromLTWH(0, top, gridWidth, rowHeight);
        if (rect.overlaps(itemRect)) {
          _selectedIds.add(files[i].id.toString());
        }
      }
    }
  }

  void _showUploadModal() {
    if (!_ensureCanEdit('上传')) return;
    showDialog(
      context: context,
      builder: (context) => UploadModal(
        zone: _getZoneString(),
        parentId: _currentFolderId,
        netbarId: _getNetbarId(),
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  Future<void> _handleCreateFolder() async {
    if (!_ensureCanEdit('创建文件夹')) return;
    final controller = TextEditingController(text: '新建文件夹');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '文件夹名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      try {
        await _resourceApi.create(
          name: result,
          type: 'folder',
          isDirectory: true,
          zone: _getZoneString(),
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
        );
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已创建文件夹: $result')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e')),
          );
        }
      }
    }
  }

  void _handleFileSelect(Resource file, bool isCtrlPressed) {
    final fileId = file.id.toString();
    setState(() {
      if (isCtrlPressed) {
        if (_selectedIds.contains(fileId)) {
          _selectedIds.remove(fileId);
        } else {
          _selectedIds.add(fileId);
        }
      } else {
        _selectedIds.clear();
        _selectedIds.add(fileId);
      }
    });
  }

  void _handleOpenFile(Resource file) {
    showDialog(
      context: context,
      builder: (context) => FileEditorModal(
        file: file,
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  void _showEmptyContextMenu(Offset position) {
    final pasteLabel = _clipboard.isNotEmpty ? '粘贴 (已复制${_clipboard.length}个项)' : '粘贴';
    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: '新建文件夹',
          icon: LucideIcons.folderPlus,
          onTap: _canEdit ? _handleCreateFolder : null,
          disabled: !_canEdit,
        ),
        ContextMenuItem(
          label: '上传文件',
          icon: LucideIcons.upload,
          onTap: _canEdit ? _showUploadModal : null,
          disabled: !_canEdit,
        ),
        ContextMenuItem(
          label: pasteLabel,
          icon: LucideIcons.clipboard,
          onTap: _handlePaste,
          disabled: !_canEdit || _clipboard.isEmpty,
          divider: true,
        ),
        ContextMenuItem(
          label: '刷新',
          icon: LucideIcons.refreshCw,
          onTap: _loadData,
          divider: true,
        ),
      ],
    );
  }

  void _showFileContextMenu(Offset position, Resource file) {
    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: file.isDirectory ? '打开' : '查看/编辑',
          icon: file.isDirectory ? LucideIcons.folderOpen : LucideIcons.fileEdit,
          onTap: file.isDirectory
              ? () => _handleFolderOpen(file)
              : () => _handleOpenFile(file),
        ),
        if (!file.isDirectory)
          ContextMenuItem(
            label: '下载',
            icon: LucideIcons.download,
            onTap: () {
              // TODO: 实现下载功能
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('下载功能开发中')),
              );
            },
          ),
        ContextMenuItem(
          label: '复制',
          icon: LucideIcons.copy,
          onTap: () {
            setState(() {
              _clipboard = [file];
              _isCut = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已复制到剪贴板')),
            );
          },
        ),
        if (_canEdit)
          ContextMenuItem(
            label: '剪切',
            icon: LucideIcons.scissors,
            onTap: () {
              setState(() {
                _clipboard = [file];
                _isCut = true;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已剪切到剪贴板')),
              );
            },
          ),
        if (_canEdit)
          ContextMenuItem(
            label: '删除',
            icon: LucideIcons.trash2,
            color: Colors.red,
            onTap: () => _handleDeleteFile(file),
            divider: true,
          ),
      ],
    );
  }

  Future<void> _handleDeleteFile(Resource file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _resourceApi.delete(file.id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: ${file.name}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 项吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        for (final id in _selectedIds) {
          await _resourceApi.delete(int.parse(id));
        }
        _selectedIds.clear();
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _handleBatchCopy() {
    setState(() {
      _clipboard = _selectedResources;
      _isCut = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${_clipboard.length} 项到剪贴板')),
    );
  }

  void _handleBatchCut() {
    if (!_ensureCanEdit('剪切')) return;
    setState(() {
      _clipboard = _selectedResources;
      _isCut = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已剪切 ${_clipboard.length} 项到剪贴板')),
    );
  }

  Future<void> _handlePaste() async {
    if (_clipboard.isEmpty) return;
    if (!_ensureCanEdit('粘贴')) return;

    try {
      for (final file in _clipboard) {
        if (_isCut) {
          await _resourceApi.move(file.id, _currentFolderId);
        } else {
          await _resourceApi.copy(file.id, _currentFolderId);
        }
      }
      if (_isCut) {
        setState(() {
          _clipboard.clear();
          _isCut = false;
        });
      }
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isCut ? '移动成功' : '复制成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  /// 拷贝共享区到本网吧根目录
  Future<void> _handleCopyToLocal() async {
    try {
      final netbarId = ref.read(currentNetbarProvider).id;
      if (netbarId == null) return;
      // 逐个复制到本网吧根目录（zone=PUBLIC）
      for (final file in _selectedResources) {
        await _resourceApi.copy(
          file.id,
          null,
          zone: 'PUBLIC',
          netbarId: netbarId,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已拷贝到本网吧')),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拷贝失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isMobileFlag =
        platformHelper.isMobile || MediaQuery.of(context).size.width < 900;
    // 监听上传队列完成，自动刷新
    ref.listen<UploadQueueState>(uploadQueueProvider, (prev, next) {
      if (prev == null) return;

      // 检查是否有任务从非完成状态变为完成状态
      final prevPending = prev.tasks.where((t) =>
        t.status == UploadStatus.pending || t.status == UploadStatus.uploading).length;
      final nextPending = next.tasks.where((t) =>
        t.status == UploadStatus.pending || t.status == UploadStatus.uploading).length;

      // 当有任务完成（从有待处理任务变为无待处理任务）时刷新
      if (prevPending > 0 && nextPending == 0 && next.tasks.isNotEmpty) {
        _loadData();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _isMobile ? _buildMobileZoneSelector() : null,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isMobile
                ? _buildMainArea()
                : Row(
                    children: [
                      _buildSidebar(),
                      Expanded(child: _buildMainArea()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: _isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        boxShadow: AppShadows.sm,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.go('/monitor'),
            icon: Icon(LucideIcons.arrowLeft, color: Colors.grey.shade600),
          ),
          Container(
            width: 1,
            height: 24,
            color: Colors.grey.shade200,
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          const Text('资源管理',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('资源区域',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                    letterSpacing: 1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _buildZoneButton(
                  ResourceZone.headquarters,
                  LucideIcons.shieldAlert,
                  '总公司资源',
                  subtitle: _isAdmin ? null : '（只读）',
                ),
                const SizedBox(height: 4),
                // 分公司资源只对非管理员显示
                if (!_isAdmin)
                  _buildZoneButton(
                    ResourceZone.branch,
                    LucideIcons.building2,
                    '分公司资源',
                  ),
                if (!_isAdmin) const SizedBox(height: 4),
                _buildZoneButton(
                  ResourceZone.shared,
                  LucideIcons.share2,
                  '共享区资源',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileZoneSelector() {
    final pills = <Widget>[
      _buildZonePill(ResourceZone.headquarters, '总部', LucideIcons.shieldAlert, subtitle: _isAdmin ? null : '只读'),
      if (!_isAdmin) _buildZonePill(ResourceZone.branch, '分公司', LucideIcons.building2),
      _buildZonePill(ResourceZone.shared, '共享', LucideIcons.share2),
    ];
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: const [
            BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, -6), spreadRadius: 2),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: pills,
        ),
      ),
    );
  }

  Widget _buildZonePill(ResourceZone zone, String label, IconData icon, {String? subtitle}) {
    final isActive = _currentZone == zone;
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleZoneChange(zone),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.iosBlue : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isActive
                ? [BoxShadow(color: AppColors.iosBlue.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isActive ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? Colors.white70 : Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneButton(ResourceZone zone, IconData icon, String label,
      {String? subtitle}) {
    final isActive = _currentZone == zone;
    return GestureDetector(
      onTap: () => _handleZoneChange(zone),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.iosBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                      color: AppColors.iosBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isActive ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color:
                              isActive ? Colors.white : Colors.grey.shade600)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11,
                            color: isActive
                                ? Colors.white70
                                : Colors.grey.shade400)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainArea() {
    return Column(
      children: [
        _buildModuleTabs(),
        if (_activeModule == ModuleTab.files) _buildBreadcrumb(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildModuleTabs() {
    if (_isMobile) {
      final actions = <Widget>[];
      if (_activeModule == ModuleTab.files) {
        if (_selectedResources.isNotEmpty) {
          actions.add(Text('已选 ${_selectedResources.length} 项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)));
          actions.addAll([
            _buildBatchButton('复制', LucideIcons.copy, AppColors.iosBlue, _handleBatchCopy),
            _buildBatchButton('剪切', LucideIcons.scissors, Colors.orange, _handleBatchCut, enabled: _canEdit),
            _buildBatchButton('删除', LucideIcons.trash2, Colors.red, _handleBatchDelete, enabled: _canEdit),
            if (_currentZone == ResourceZone.shared)
              _buildBatchButton('拷贝到本网吧', LucideIcons.download, const Color(0xFF22C55E), _handleCopyToLocal),
          ]);
        }
        actions.add(_buildBatchButton(
          '粘贴${_clipboard.isNotEmpty ? ' (${_clipboard.length})' : ''}',
          LucideIcons.clipboard,
          Colors.green,
          _handlePaste,
          enabled: _canEdit && _clipboard.isNotEmpty,
        ));
        actions.add(_buildSearchField(width: double.infinity));
        actions.add(_buildLayoutToggle());
        actions.add(_buildUploadButton());
      } else {
        if (_selectedStartupItems.isNotEmpty) {
          actions.add(Text('已选 ${_selectedStartupItems.length} 项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)));
          actions.addAll([
            _buildBatchButton('批量启用', LucideIcons.toggleRight, const Color(0xFF22C55E), () => _handleBatchStartupEnable(true), enabled: _canDisableStartupItem),
            _buildBatchButton('批量禁用', LucideIcons.toggleLeft, Colors.grey.shade600, () => _handleBatchStartupEnable(false), enabled: _canDisableStartupItem),
            _buildBatchButton('批量删除', LucideIcons.trash2, Colors.red, _handleBatchStartupDelete, enabled: _canDeleteStartupItem),
          ]);
        }
        actions.add(ElevatedButton.icon(
          onPressed: _canEdit ? _showAddStartupItemModal : null,
          icon: const Icon(LucideIcons.plus, size: 14),
          label: const Text('新增启动项'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ));
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildModuleTab(ModuleTab.files, LucideIcons.folderOpen, '文件管理'),
                const SizedBox(width: 12),
                _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          _buildModuleTab(ModuleTab.files, LucideIcons.folderOpen, '文件管理'),
          const SizedBox(width: 16),
          _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
          const Spacer(),
          if (_activeModule == ModuleTab.files) ...[
            if (_selectedResources.isNotEmpty) ...[
              Text('已选 ${_selectedResources.length} 项',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(width: 12),
              _buildBatchButton(
                  '复制', LucideIcons.copy, AppColors.iosBlue, _handleBatchCopy),
              const SizedBox(width: 8),
              _buildBatchButton(
                  '剪切', LucideIcons.scissors, Colors.orange, _handleBatchCut,
                  enabled: _canEdit),
              const SizedBox(width: 8),
              _buildBatchButton(
                  '删除', LucideIcons.trash2, Colors.red, _handleBatchDelete,
                  enabled: _canEdit),
            ],
            const SizedBox(width: 12),
            _buildBatchButton(
              '粘贴${_clipboard.isNotEmpty ? ' (${_clipboard.length})' : ''}',
              LucideIcons.clipboard,
              Colors.green,
              _handlePaste,
              enabled: _canEdit && _clipboard.isNotEmpty,
            ),
            const SizedBox(width: 16),
            // 搜索框
            Container(
              width: 200,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isSearching ? AppColors.iosBlue : Colors.grey.shade200),
              ),
              child: Center(
                child: TextField(
                  onChanged: (v) {
                    // 使用防抖，避免频繁请求
                    if (v.isEmpty) {
                      _clearSearch();
                    }
                  },
                  onSubmitted: (v) {
                    if (v.isNotEmpty) {
                      _performSearch(v);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: '搜索文件（回车搜索）...',
                    hintStyle:
                        TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: Icon(LucideIcons.search,
                          size: 14, color: _isSearching ? AppColors.iosBlue : Colors.grey.shade400),
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    suffixIcon: _isSearching
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: Icon(LucideIcons.x, size: 14, color: Colors.grey.shade400),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  textAlignVertical: TextAlignVertical.center,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 布局切换
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  _buildLayoutButton(LayoutMode.grid, LucideIcons.layoutGrid),
                  _buildLayoutButton(LayoutMode.list, LucideIcons.list),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 上传按钮
            ElevatedButton.icon(
              onPressed: _canEdit ? _showUploadModal : null,
              icon: const Icon(LucideIcons.upload, size: 14),
              label: const Text('上传'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iosBlue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModuleTab(ModuleTab module, IconData icon, String label) {
    final isActive = _activeModule == module;
    return GestureDetector(
      onTap: () => _handleModuleChange(module),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: isActive ? Colors.grey.shade900 : Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isActive
                        ? Colors.grey.shade900
                        : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchButton(
      String label, IconData icon, Color color, VoidCallback onTap,
      {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (enabled ? color : Colors.grey).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: enabled ? color : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: enabled ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutButton(LayoutMode mode, IconData icon) {
    final isActive = _layoutMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _layoutMode = mode),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive ? AppShadows.sm : null,
        ),
        child: Icon(icon,
            size: 16,
            color: isActive ? Colors.grey.shade900 : Colors.grey.shade500),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _isMobile ? 12 : 24, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _folderHistory.length; i++) ...[
            GestureDetector(
              onTap: () => _handleBreadcrumbClick(i),
              child: Text(
                _folderHistory[i].name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      i == _folderHistory.length - 1 ? FontWeight.w500 : FontWeight.normal,
                  color: i == _folderHistory.length - 1
                      ? Colors.grey.shade900
                      : Colors.grey.shade500,
                ),
              ),
            ),
            if (i < _folderHistory.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(LucideIcons.chevronRight,
                    size: 14, color: Colors.grey.shade400),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_activeModule == ModuleTab.files) {
      return _buildFilesContent();
    } else {
      return _buildStartupContent();
    }
  }

  Widget _buildFilesContent() {
    final files = _filteredFiles;
    if (files.isEmpty) {
      return _buildEmptyState();
    }

    // 构建带拖选的文件列表
    Widget fileListWidget = GestureDetector(
      onSecondaryTapDown: (details) {
        // 右键点击空白区域
        if (_selectedIds.isEmpty) {
          _showEmptyContextMenu(details.globalPosition);
        }
      },
      onPanStart: _handleDragStart,
      onPanUpdate: _handleDragUpdate,
      onPanEnd: _handleDragEnd,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: _layoutMode == LayoutMode.grid ? _buildFileGrid(files) : _buildFileList(files),
          ),
          // 拖选矩形
          if (_selectionRect != null)
            Positioned.fromRect(
              rect: _selectionRect!,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.iosBlue.withValues(alpha: 0.1),
                  border: Border.all(color: AppColors.iosBlue, width: 1),
                ),
              ),
            ),
        ],
      ),
    );

    // 包装拖放区域
    if (kIsWeb) {
      return Stack(
        children: [
          fileListWidget,
          if (_isExternalDragOver) _buildDragOverlay(),
        ],
      );
    }

    // 桌面端使用 DropTarget
    return DropTarget(
      onDragDone: (details) => _handleExternalDrop(details.files),
      onDragEntered: (_) => setState(() => _isExternalDragOver = true),
      onDragExited: (_) => setState(() => _isExternalDragOver = false),
      child: Stack(
        children: [
          fileListWidget,
          if (_isExternalDragOver) _buildDragOverlay(),
        ],
      ),
    );
  }

  /// 处理外部拖入的文件和目录
  Future<void> _handleExternalDrop(List<dynamic> files) async {
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    setState(() => _isExternalDragOver = false);

    // 桌面端：检查是否有目录
    if (!kIsWeb && platformHelper.isDesktop) {
      final tasks = <UploadTask>[];
      var counter = 0;
      final zone = _getZoneString();
      final netbarId = _getNetbarId();

      for (final xf in files) {
        if (xf is! XFile) continue;
        final filePath = xf.path;
        if (filePath == null || filePath.isEmpty) continue;

        try {
          // 使用 platformFileHelper 检查是否为目录
          if (platformFileHelper.isDirectory(filePath)) {
            // 是目录，递归读取
            final dirItems = await platformFileHelper.readDirectoryFromPath(filePath);
            for (final item in dirItems) {
              final id = 'upload-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
              if (item.isDirectory) {
                tasks.add(UploadTask(
                  id: id,
                  name: item.name,
                  size: 0,
                  isDirectory: true,
                  relativePath: item.relativePath,
                  parentId: _currentFolderId,
                  zone: zone,
                  netbarId: netbarId,
                  bytes: null,
                ));
              } else if (item.bytes != null) {
                tasks.add(UploadTask(
                  id: id,
                  name: item.name,
                  size: item.bytes!.length,
                  isDirectory: false,
                  relativePath: item.relativePath,
                  parentId: _currentFolderId,
                  zone: zone,
                  netbarId: netbarId,
                  bytes: item.bytes,
                ));
              }
            }
          } else {
            // 是文件
            final bytes = await xf.readAsBytes();
            final fileName = xf.name.isNotEmpty ? xf.name : p.basename(filePath);
            final id = 'upload-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
            tasks.add(UploadTask(
              id: id,
              name: fileName,
              size: bytes.length,
              isDirectory: false,
              relativePath: fileName,
              parentId: _currentFolderId,
              zone: zone,
              netbarId: netbarId,
              bytes: bytes,
            ));
          }
        } catch (e) {
          debugPrint('处理拖拽项失败: $e');
        }
      }

      if (tasks.isNotEmpty) {
        ref.read(uploadQueueProvider.notifier).enqueue(tasks);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已添加 ${tasks.length} 个项目到上传队列')),
          );
        }
      }
      return;
    }

    // Web 平台或其他情况：原有逻辑
    int success = 0;
    for (final xf in files) {
      if (xf is! XFile) continue;
      try {
        final bytes = await xf.readAsBytes();
        final fileName = xf.name.isNotEmpty
            ? xf.name
            : (xf.path != null ? p.basename(xf.path) : 'upload.bin');
        await _resourceApi.uploadFile(
          name: fileName,
          bytes: bytes,
          zone: _getZoneString(),
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
        );
        success++;
      } catch (_) {}
    }
    if (success > 0) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功上传 $success 个文件')),
        );
      }
    }
  }

  Widget _buildDragOverlay() {
    return Container(
      color: AppColors.iosBlue.withValues(alpha: 0.1),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.upload, size: 48, color: AppColors.iosBlue),
              const SizedBox(height: 16),
              const Text('释放以上传文件',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showEmptyContextMenu(details.globalPosition),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.folderOpen, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('暂无文件', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            if (_canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _handleCreateFolder,
                    icon: const Icon(LucideIcons.folderPlus, size: 16),
                    label: const Text('新建文件夹'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _showUploadModal,
                    icon: const Icon(LucideIcons.upload, size: 16),
                    label: const Text('上传文件'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileGrid(List<Resource> files) {
    return GridView.builder(
      key: _gridKey,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return _buildFileGridItem(file);
      },
    );
  }

  Widget _buildFileGridItem(Resource file) {
    final isSelected = _selectedIds.contains(file.id.toString());
    // 使用 Listener 在 pointer 层立即处理点击，绕过 LongPressDraggable 延迟
    return Listener(
      onPointerDown: (event) {
        // 左键按下时立即选中（不等待抬起），buttons == 1 表示左键
        if (event.buttons == 1) {
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          _handleFileSelect(file, isCtrlPressed);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onDoubleTap: file.isDirectory ? () => _handleFolderOpen(file) : () => _handleOpenFile(file),
          onSecondaryTapDown: (details) {
            if (!isSelected) {
              setState(() {
                _selectedIds.clear();
                _selectedIds.add(file.id.toString());
              });
            }
            _showFileContextMenu(details.globalPosition, file);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.iosBlue.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: AppColors.iosBlue, width: 2) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FileIcon(
                  type: file.type,
                  isDirectory: file.isDirectory,
                  size: 32,
                ),
                const SizedBox(height: 4),
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileList(List<Resource> files) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return _buildFileListItem(file);
      },
    );
  }

  Widget _buildFileListItem(Resource file) {
    final isSelected = _selectedIds.contains(file.id.toString());
    // 使用 Listener 在 pointer 层立即处理点击，绕过 LongPressDraggable 延迟
    return Listener(
      onPointerDown: (event) {
        // 左键按下时立即选中（不等待抬起），buttons == 1 表示左键
        if (event.buttons == 1) {
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          _handleFileSelect(file, isCtrlPressed);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onDoubleTap: file.isDirectory ? () => _handleFolderOpen(file) : () => _handleOpenFile(file),
          onSecondaryTapDown: (details) {
            if (!isSelected) {
              setState(() {
                _selectedIds.clear();
                _selectedIds.add(file.id.toString());
              });
            }
            _showFileContextMenu(details.globalPosition, file);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.iosBlue.withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.iosBlue : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                FileIcon(
                  type: file.type,
                  isDirectory: file.isDirectory,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      if (!file.isDirectory)
                        Text(
                          _formatFileSize(file.size),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(file.updatedAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildStartupContent() {
    final items = _filteredStartupItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.zap, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('暂无启动项', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            if (_canEdit)
              ElevatedButton.icon(
                onPressed: _showAddStartupItemModal,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('添加启动项'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // 启动项网格
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 16,
                childAspectRatio: 4.4,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildStartupCard(items[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartupCard(StartupItem item) {
    final isSelected = _selectedIds.contains('startup-${item.id}');
    return _ResourceStartupCard(
      key: ValueKey('startup-${item.id}'),
      item: item,
      isSelected: isSelected,
      canEdit: _canEdit,
      onTap: () {
        final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
        setState(() {
          final key = 'startup-${item.id}';
          if (isCtrlPressed) {
            if (isSelected) {
              _selectedIds.remove(key);
            } else {
              _selectedIds.add(key);
            }
          } else {
            _selectedIds.clear();
            _selectedIds.add(key);
          }
        });
      },
      onDoubleTap: _canEdit ? () => _showStartupConfigModal(item) : null,
      onSecondaryTapDown: (details) {
        if (!isSelected) {
          setState(() {
            _selectedIds.clear();
            _selectedIds.add('startup-${item.id}');
          });
        }
        _showStartupItemContextMenu(details.globalPosition, item);
      },
      onEdit: () => _showStartupConfigModal(item),
      onDelete: () => _handleDeleteStartupItem(item),
    );
  }

  void _showStartupItemContextMenu(Offset position, StartupItem item) {
    showContextMenu(
      context: context,
      position: position,
      items: [
        if (_canEdit)
          ContextMenuItem(
            label: '配置',
            icon: LucideIcons.settings,
            onTap: () => _showStartupConfigModal(item),
          ),
        if (_canEdit)
          ContextMenuItem(
            label: '删除',
            icon: LucideIcons.trash2,
            onTap: () => _handleDeleteStartupItem(item),
            divider: true,
          ),
      ],
    );
  }

  void _showAddStartupItemModal() {
    if (!_ensureCanEdit('添加启动项')) return;
    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _getZoneString(),
        netbarId: _getNetbarId(),
        onSuccess: _loadData,
      ),
    );
  }

  void _showStartupConfigModal(StartupItem item) {
    showDialog(
      context: context,
      builder: (context) => StartupConfigModal(
        item: item,
        isAdmin: _isAdmin,
        areas: _areas,
        onSuccess: _loadData,
      ),
    );
  }

  Future<void> _handleDeleteStartupItem(StartupItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除启动项 "${item.effectiveDisplayName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _startupItemApi.delete(item.id);
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: ${item.effectiveDisplayName}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }
}

/// 资源管理启动项卡片组件（简化版，无禁用/启用功能）
class _ResourceStartupCard extends StatefulWidget {
  final StartupItem item;
  final bool isSelected;
  final bool canEdit;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(TapDownDetails) onSecondaryTapDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ResourceStartupCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.canEdit,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ResourceStartupCard> createState() => _ResourceStartupCardState();
}

class _ResourceStartupCardState extends State<_ResourceStartupCard> {
  bool _isHovered = false;
  DateTime? _lastTapTime;

  void _handleTap() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 300) {
      _lastTapTime = null;
      widget.onDoubleTap?.call();
    } else {
      _lastTapTime = now;
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _isHovered = false);
      },
      child: GestureDetector(
        onTapDown: (_) => _handleTap(),
        onSecondaryTapDown: widget.onSecondaryTapDown,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isSelected ? AppColors.iosBlue : Colors.grey.shade200,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected ? null : AppShadows.sm,
          ),
          child: Row(
            children: [
              // 图标
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: AppColors.iosBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(LucideIcons.zap, size: 16, color: AppColors.iosBlue),
              ),
              const SizedBox(width: 10),
              // 名称和信息
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.item.effectiveDisplayName,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.item.displayName?.isNotEmpty == true && widget.item.name.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.item.name,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        if (widget.item.delay > 0) ...[
                          Icon(LucideIcons.clock, size: 10, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Text('${widget.item.delay}s', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          const SizedBox(width: 6),
                        ],
                        if (widget.item.forceRun) ...[
                          Icon(LucideIcons.alertCircle, size: 10, color: Colors.orange.shade400),
                          const SizedBox(width: 2),
                          Text('强制', style: TextStyle(fontSize: 10, color: Colors.orange.shade500)),
                          const SizedBox(width: 6),
                        ],
                        if (widget.item.targetOs != null && widget.item.targetOs!.isNotEmpty) ...[
                          Icon(LucideIcons.monitor, size: 10, color: Colors.grey.shade400),
                          const SizedBox(width: 2),
                          Text(widget.item.targetOs!.toUpperCase(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // 操作按钮（hover 时显示）
              AnimatedOpacity(
                opacity: _isHovered || widget.isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.canEdit)
                      _buildCardActionButton(
                        icon: LucideIcons.settings,
                        tooltip: '配置',
                        onTap: widget.onEdit,
                      ),
                    if (widget.canEdit)
                      _buildCardActionButton(
                        icon: LucideIcons.trash2,
                        tooltip: '删除',
                        onTap: widget.onDelete,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 14, color: Colors.grey.shade400),
        ),
      ),
    );
  }
}
