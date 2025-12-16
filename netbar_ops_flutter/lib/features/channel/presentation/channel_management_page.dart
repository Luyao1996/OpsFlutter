import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/responsive/responsive.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/permission_provider.dart';
import '../../../shared/providers/upload_queue_provider.dart';
import '../../../shared/utils/web_download_helper_stub.dart'
    if (dart.library.html) '../../../shared/utils/web_download_helper_web.dart';
import '../../../shared/utils/resource_path_display.dart';
import '../../../shared/utils/top_notice.dart';

import '../data/resource_api.dart';
import '../data/startup_item_api.dart';
import 'drop_target_stub.dart'
    if (dart.library.io) 'package:desktop_drop/desktop_drop.dart';
import 'platform_helper.dart';
import 'web_drop_zone.dart';
import 'widgets/add_startup_item_modal.dart';
import 'widgets/context_menu.dart';
import 'widgets/file_editor_modal.dart';
import 'widgets/file_icon.dart';
import 'widgets/startup_config_modal.dart';
import 'widgets/upload_helper.dart';
import 'widgets/upload_modal.dart';

enum ModuleTab { files, startup }

enum LayoutMode { grid, list }

class BreadcrumbItem {
  final int? id;
  final String name;
  BreadcrumbItem({this.id, required this.name});
}

class ChannelManagementPage extends ConsumerStatefulWidget {
  const ChannelManagementPage({super.key});

  @override
  ConsumerState<ChannelManagementPage> createState() =>
      _ChannelManagementPageState();
}

class _ChannelManagementPageState extends ConsumerState<ChannelManagementPage> {
  final ResourceApi _resourceApi = ResourceApi();
  final StartupItemApi _startupItemApi = StartupItemApi();

  bool _isMobileFlag = false;
  bool get _isMobile => _isMobileFlag;

  String _currentZone = 'PUBLIC'; // PUBLIC/BRANCH/HEADQUARTERS
  ModuleTab _activeModule = ModuleTab.files;
  LayoutMode _layoutMode = LayoutMode.grid;

  String _searchQuery = '';
  final TextEditingController _fileSearchController = TextEditingController();
  Timer? _searchDebounce;
  int? _currentFolderId;
  List<BreadcrumbItem> _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];

  List<Resource> _files = [];
  List<Resource> _searchResults = [];
  bool _isSearching = false;
  List<StartupItem> _startupItems = [];

  final Set<String> _selectedIds = {};

  bool _loading = false;
  String? _error;

  // Drag-select state (align with ResourceManagement)
  bool _isDragSelecting = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;
  final GlobalKey _gridKey = GlobalKey();

  Rect? get _selectionRect {
    if (!_isDragSelecting ||
        _dragStartPosition == null ||
        _dragCurrentPosition == null) {
      return null;
    }
    return Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
  }

  // Clipboard (copy/cut/paste)
  List<Resource> _clipboard = [];
  bool _isCut = false;

  bool _isExternalDragOver = false;
  ProviderSubscription<CurrentNetbar>? _netbarSubscription;

  bool get _isAdmin {
    final auth = ref.watch(authNotifierProvider);
    final role = auth.user?.role.toLowerCase() ?? '';
    return role.contains('admin');
  }

  bool get _canEdit {
    final netbarId = ref.read(currentNetbarProvider).id;
    final perm = ref.read(permissionProvider);
    return perm.canEditZone(_currentZone, netbarId: netbarId);
  }

  int? _getNetbarId() {
    final netbarId = ref.read(currentNetbarProvider).id;
    if (_currentZone == 'PUBLIC') return netbarId;
    return null;
  }

  String _editDeniedReason() {
    final netbarId = ref.read(currentNetbarProvider).id;
    if (_currentZone == 'PUBLIC') {
      return netbarId == null ? '请先选择网吧' : '无写入权限';
    }
    return '当前来源仅支持查看/下载';
  }

  bool _ensureCanEdit(String actionLabel) {
    if (_canEdit) return true;
    showTopNotice(context, '$actionLabel失败：${_editDeniedReason()}', level: NoticeLevel.warning);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    if (kIsWeb) {
      _registerWebDropZone();
      _registerWebPasteHandler();
    }

    _netbarSubscription = ref.listenManual<CurrentNetbar>(
      currentNetbarProvider,
      (prev, next) {
        if (prev?.id != next.id || prev?.version != next.version) {
          setState(() {
            _currentFolderId = null;
            _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
            _selectedIds.clear();
            _clipboard.clear();
            _isCut = false;
          });
          _loadData();
        }
      },
    );
  }

  @override
  void dispose() {
    _netbarSubscription?.close();
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    _searchDebounce?.cancel();
    _fileSearchController.dispose();
    if (kIsWeb) {
      webDropHandler.unregisterDropZone();
      webDropHandler.unregisterPasteHandler();
    }
    super.dispose();
  }

  bool _handleKeyboard(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    // Escape - clear selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _selectedIds.clear());
      return true;
    }

    // Only handle shortcuts in Files tab
    if (_activeModule != ModuleTab.files) return false;

    // Ctrl+C - copy
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      if (_selectedResources.isNotEmpty) {
        _handleBatchCopy();
        return true;
      }
    }

    // Ctrl+X - cut
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyX) {
      if (_selectedResources.isNotEmpty && _canEdit) {
        _handleBatchCut();
        return true;
      }
    }

    // Ctrl+V - paste (internal clipboard first, else system clipboard files)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (_canEdit) {
        if (_clipboard.isNotEmpty) {
          _handlePaste();
          return true;
        } else {
          _handleSystemClipboardPaste();
          return true;
        }
      }
    }

    // Ctrl+A - select all (current folder list)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      setState(() {
        _selectedIds.clear();
        for (final file in _files) {
          _selectedIds.add(file.id.toString());
        }
      });
      return true;
    }

    // Delete - delete selected
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      if (_selectedResources.isNotEmpty && _canEdit) {
        _handleBatchDelete();
        return true;
      }
    }

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
          zone: _currentZone,
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
        );
        if (mounted) setState(() => _files = resources);
      } else {
        final items = await _startupItemApi.getAll(
          zone: _currentZone,
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

  void _handleZoneChange(String zone) {
    setState(() {
      _currentZone = zone;
      _currentFolderId = null;
      _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
      _selectedIds.clear();
      _clipboard.clear();
      _isCut = false;
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _fileSearchController.clear();
    });
    _loadData();
  }

  void _handleModuleChange(ModuleTab module) {
    setState(() {
      _activeModule = module;
      _selectedIds.clear();
      if (module == ModuleTab.files) {
        _searchQuery = '';
        _isSearching = false;
        _searchResults = [];
        _fileSearchController.clear();
      }
    });
    _loadData();
  }

  void _handleBreadcrumbClick(int index) {
    setState(() {
      _currentFolderId = _folderHistory[index].id;
      _folderHistory = _folderHistory.sublist(0, index + 1);
      _selectedIds.clear();
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _fileSearchController.clear();
    });
    _loadData();
  }

  void _handleFolderOpen(Resource folder) {
    setState(() {
      _currentFolderId = folder.id;
      _folderHistory.add(BreadcrumbItem(id: folder.id, name: folder.name));
      _selectedIds.clear();
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _fileSearchController.clear();
    });
    _loadData();
  }

  List<Resource> get _filteredFiles {
    if (_isSearching && _searchQuery.isNotEmpty) {
      return _searchResults;
    }
    final files = _files.toList();
    files.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.compareTo(b.name);
    });
    return files;
  }

  List<Resource> get _selectedResources {
    return _files.where((f) => _selectedIds.contains(f.id.toString())).toList();
  }

  List<StartupItem> get _selectedStartupItems {
    return _startupItems
        .where((s) => _selectedIds.contains('startup-${s.id}'))
        .toList();
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint(
        '[ChannelManagement] performSearch="$query" zone=$_currentZone netbarId=${_getNetbarId()}',
      );
    }
    setState(() {
      _searchQuery = query;
      _isSearching = true;
      _loading = true;
      _error = null;
    });

    try {
      final results = await _resourceApi.search(
        keyword: query,
        zone: _currentZone,
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

  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
    });
  }

  void _clearSearchAndText() {
    if (_fileSearchController.text.isNotEmpty) {
      _fileSearchController.clear();
    }
    _clearSearch();
  }

  void _scheduleSearch(String raw) {
    final q = raw.trim();
    _searchDebounce?.cancel();
    if (q.isEmpty) {
      _clearSearch();
      return;
    }
    if (_isSearching && q == _searchQuery) return;
    if (kDebugMode) {
      debugPrint('[ChannelManagement] scheduleSearch="$q"');
    }
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[ChannelManagement] debounceFire="$q"');
      }
      _performSearch(q);
    });
  }

  void _handleFileSelect(Resource file, bool isCtrlPressed) {
    setState(() {
      final key = file.id.toString();
      if (isCtrlPressed) {
        if (_selectedIds.contains(key)) {
          _selectedIds.remove(key);
        } else {
          _selectedIds.add(key);
        }
      } else {
        _selectedIds.clear();
        _selectedIds.add(key);
      }
    });
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
      const maxCrossAxisExtent = 120.0;
      const spacing = 16.0;
      const childAspectRatio = 0.85;

      final crossAxisCount = (gridWidth / (maxCrossAxisExtent + spacing))
          .ceil()
          .clamp(1, 100);
      final itemWidth =
          (gridWidth - (crossAxisCount - 1) * spacing) / crossAxisCount;
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
      const rowHeight = 64.0;
      for (int i = 0; i < files.length; i++) {
        final top = i * (rowHeight + 8);
        final itemRect = Rect.fromLTWH(0, top, gridWidth, rowHeight);
        if (rect.overlaps(itemRect)) {
          _selectedIds.add(files[i].id.toString());
        }
      }
    }
  }

  void _showUploadModal() {
    if (!_ensureCanEdit('上传')) return;
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => UploadModal(
          zone: _currentZone,
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
          onSuccess: _loadData,
          presentation: UploadModalPresentation.sheet,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => UploadModal(
        zone: _currentZone,
        parentId: _currentFolderId,
        netbarId: _getNetbarId(),
        onSuccess: _loadData,
        presentation: UploadModalPresentation.dialog,
      ),
    );
  }

  Future<void> _handleCreateFolder() async {
    if (!_ensureCanEdit('新建文件夹')) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '请输入文件夹名称'),
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
    if (name == null || name.trim().isEmpty) return;

    try {
      await _resourceApi.create(
        name: name.trim(),
        type: 'folder',
        isDirectory: true,
        parentId: _currentFolderId,
        zone: _currentZone,
        netbarId: _getNetbarId(),
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '创建失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _handleDeleteFile(Resource file) async {
    if (!_ensureCanEdit('删除')) return;
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
    if (confirmed != true) return;

    try {
      await _resourceApi.delete(file.id);
      _loadData();
      if (mounted) {
        showTopNotice(context, '删除成功', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _handleBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    if (!_ensureCanEdit('删除')) return;
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
    if (confirmed != true) return;

    try {
      for (final id in _selectedIds) {
        await _resourceApi.delete(int.parse(id));
      }
      setState(() => _selectedIds.clear());
      _loadData();
      if (mounted) {
        showTopNotice(context, '删除成功', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
      }
    }
  }

  void _handleBatchCopy() {
    setState(() {
      _clipboard = _selectedResources;
      _isCut = false;
    });
    showTopNotice(context, '已复制 ${_clipboard.length} 项到剪贴板', level: NoticeLevel.success);
  }

  void _handleBatchCut() {
    if (!_ensureCanEdit('剪切')) return;
    setState(() {
      _clipboard = _selectedResources;
      _isCut = true;
    });
    showTopNotice(context, '已剪切 ${_clipboard.length} 项到剪贴板', level: NoticeLevel.success);
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
        showTopNotice(context, _isCut ? '移动成功' : '复制成功', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '操作失败: $e', level: NoticeLevel.error);
      }
    }
  }

  bool _isExecutableFile(Resource file) {
    if (file.isDirectory) return false;
    return file.name.toLowerCase().endsWith('.exe');
  }

  void _showAddStartupFromFile(Resource file) {
    if (!_ensureCanEdit('添加启动项')) return;
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => AddStartupItemModal(
          zone: _currentZone,
          netbarId: _getNetbarId(),
          resourceId: file.id,
          defaultPath: file.path.isNotEmpty ? file.path : file.name,
          defaultWorkingDir: deriveDirectoryFromPath(file.path),
          isAdmin: _isAdmin,
          onSuccess: _loadData,
          fullscreenSheet: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _currentZone,
        netbarId: _getNetbarId(),
        resourceId: file.id,
        defaultPath: file.path.isNotEmpty ? file.path : file.name,
        defaultWorkingDir: deriveDirectoryFromPath(file.path),
        isAdmin: _isAdmin,
        onSuccess: _loadData,
      ),
    );
  }

  Future<void> _handleDownload(Resource file) async {
    if (file.isDirectory) {
      if (mounted) {
        showTopNotice(context, '文件夹暂不支持下载', level: NoticeLevel.warning);
      }
      return;
    }

    if (kIsWeb) {
      try {
        final bytes = await _resourceApi.downloadBytes(file.id);
        await downloadBytesAsFile(bytes, file.name);
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
        }
      }
      return;
    }

    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      try {
        if (mounted) {
          showTopBanner(
            context,
            content: Row(
              children: const [
                Text('正在下载...'),
                SizedBox(width: 12),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            level: NoticeLevel.info,
            duration: null,
          );
        }

        final bytes = await _resourceApi.downloadBytes(file.id);
        if (mounted) hideTopNotice(context);

        final saved = await FilePicker.platform.saveFile(
          dialogTitle: '保存文件',
          fileName: file.name,
          bytes: Uint8List.fromList(bytes),
        );
        if (saved == null) return;

        if (mounted) {
          showTopNotice(context, '下载成功: $saved', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          hideTopNotice(context);
          showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
        }
      }
      return;
    }

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: file.name,
      );
      if (savePath == null) return;

      if (mounted) {
        showTopBanner(
          context,
          content: Row(
            children: const [
              Text('正在下载...'),
              SizedBox(width: 12),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          level: NoticeLevel.info,
          duration: null,
        );
      }

      await _resourceApi.downloadToFile(file.id, savePath);

      if (mounted) {
        hideTopNotice(context);
        showTopNotice(context, '下载成功: $savePath', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        hideTopNotice(context);
        showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
      }
    }
  }

  void _handleOpenFile(Resource file, {required bool readOnly}) {
    final category = FileIcon.getTypeFromName(file.name);
    if (category == 'image') {
      _showImagePreview(file);
      return;
    }

    if (!FileIcon.isTextFile(file.name)) {
    showTopNotice(context, '该文件类型仅支持下载查看', level: NoticeLevel.warning);
      return;
    }

    showDialog(
      context: context,
      builder: (context) =>
          FileEditorModal(file: file, readOnly: readOnly, onSuccess: _loadData),
    );
  }

  void _showImagePreview(Resource file) {
    final future = _resourceApi.downloadBytes(file.id);
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: FutureBuilder<List<int>>(
              future: future,
              builder: (context, snapshot) {
                Widget content;
                if (snapshot.connectionState != ConnectionState.done) {
                  content = const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                } else if (snapshot.hasError) {
                  content = Center(
                    child: Text(
                      '图片加载失败: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                } else {
                  final bytes = Uint8List.fromList(snapshot.data ?? const []);
                  content = InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  );
                }

                return Stack(
                  children: [
                    Positioned.fill(child: content),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: 10,
                      child: Text(
                        file.name,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showEmptyContextMenu(Offset position) {
    if (!_canEdit) {
      showContextMenu(
        context: context,
        position: position,
        items: [
          ContextMenuItem(
            label: '刷新',
            icon: LucideIcons.refreshCw,
            onTap: _loadData,
          ),
        ],
      );
      return;
    }

    final pasteLabel = _clipboard.isNotEmpty
        ? '粘贴 (已复制${_clipboard.length}个项)'
        : '粘贴';
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
    final isExe = _isExecutableFile(file) && _canEdit;
    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: file.isDirectory ? '打开' : (_canEdit ? '查看/编辑' : '查看'),
          icon: file.isDirectory
              ? LucideIcons.folderOpen
              : (_canEdit ? LucideIcons.fileEdit : LucideIcons.fileText),
          onTap: file.isDirectory
              ? () => _handleFolderOpen(file)
              : () => _handleOpenFile(file, readOnly: !_canEdit),
        ),
        if (!file.isDirectory)
          ContextMenuItem(
            label: '下载',
            icon: LucideIcons.download,
            onTap: () => _handleDownload(file),
          ),
        if (isExe)
          ContextMenuItem(
            label: '添加到启动项',
            icon: LucideIcons.zap,
            color: const Color(0xFF22C55E),
            onTap: () => _showAddStartupFromFile(file),
            divider: true,
          ),
        if (_canEdit) ...[
          ContextMenuItem(
            label: '复制',
            icon: LucideIcons.copy,
            onTap: () {
              setState(() {
                _clipboard = [file];
                _isCut = false;
              });
              showTopNotice(context, '已复制到剪贴板', level: NoticeLevel.success);
            },
          ),
          ContextMenuItem(
            label: '剪切',
            icon: LucideIcons.scissors,
            onTap: () {
              setState(() {
                _clipboard = [file];
                _isCut = true;
              });
              showTopNotice(context, '已剪切到剪贴板', level: NoticeLevel.success);
            },
          ),
          ContextMenuItem(
            label: '删除',
            icon: LucideIcons.trash2,
            color: Colors.red,
            onTap: () => _handleDeleteFile(file),
            divider: true,
          ),
        ],
      ],
    );
  }

  // ---- Upload queue / external drag&drop / clipboard paste (align with ResourceManagement) ----

  Future<bool> _askExtractZip(List<String> fileNames) async {
    final zipFiles = fileNames
        .where((name) => name.toLowerCase().endsWith('.zip'))
        .toList();
    if (zipFiles.isEmpty) return false;

    final shouldAsk =
        fileNames.length == 1 || zipFiles.length == fileNames.length;
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

  Future<void> _handleWebDrop(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    if (mounted) setState(() => _isExternalDragOver = false);

    final fileNames = files
        .where((f) => !f.isDirectory)
        .map((f) => f.name)
        .toList();
    final extractZip = await _askExtractZip(fileNames);

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _currentZone;
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id =
          'web-drop-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
      final isZip = file.name.toLowerCase().endsWith('.zip');
      tasks.add(
        UploadTask(
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
          status: file.isDirectory
              ? UploadStatus.success
              : UploadStatus.pending,
          extractZip: extractZip && isZip,
        ),
      );
    }

    notifier.enqueue(tasks);
    _loadData();
  }

  Future<void> _handleWebPaste(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('粘贴')) return;
    if (_activeModule != ModuleTab.files) return;
    if (files.isEmpty) return;

    final fileNames = files
        .where((f) => !f.isDirectory)
        .map((f) => f.name)
        .toList();
    final extractZip = await _askExtractZip(fileNames);

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _currentZone;
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id =
          'web-paste-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
      final isZip = file.name.toLowerCase().endsWith('.zip');
      tasks.add(
        UploadTask(
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
          status: file.isDirectory
              ? UploadStatus.success
              : UploadStatus.pending,
          extractZip: extractZip && isZip,
        ),
      );
    }

    notifier.enqueue(tasks);
    _loadData();
  }

  Future<void> _handleSystemClipboardPaste() async {
    if (!_canEdit) return;
    if (kIsWeb) return;

    try {
      final paths = await platformFileHelper.getClipboardFilePaths();
      if (paths.isEmpty) {
        if (mounted) {
          showTopNotice(context, '剪贴板中没有文件', level: NoticeLevel.warning);
        }
        return;
      }

      final items = await platformFileHelper.readFilesFromPaths(paths);
      if (items.isEmpty) {
        if (mounted) {
          showTopNotice(context, '无法读取剪贴板中的文件', level: NoticeLevel.error);
        }
        return;
      }

      final notifier = ref.read(uploadQueueProvider.notifier);
      final tasks = <UploadTask>[];
      var counter = 0;
      final zone = _currentZone;
      final netbarId = _getNetbarId();

      for (final item in items) {
        final id =
            'clipboard-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
        tasks.add(
          UploadTask(
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
            status: item.isDirectory
                ? UploadStatus.success
                : UploadStatus.pending,
          ),
        );
      }

      notifier.enqueue(tasks);
      _loadData();
      if (mounted) {
        showTopNotice(context, '已从剪贴板添加 ${tasks.length} 个文件到上传队列', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '粘贴失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _handleExternalDrop(List<dynamic> files) async {
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    if (mounted) setState(() => _isExternalDragOver = false);

    final xfiles = <XFile>[];
    for (final f in files) {
      if (f is XFile) xfiles.add(f);
    }
    if (xfiles.isEmpty) return;

    final fileNames = xfiles.map((f) => f.name).toList();
    final extractZip = await _askExtractZip(fileNames);

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _currentZone;
    final netbarId = _getNetbarId();

    for (final file in xfiles) {
      final bytes = await file.readAsBytes();
      final id = 'drop-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
      final isZip = file.name.toLowerCase().endsWith('.zip');
      tasks.add(
        UploadTask(
          id: id,
          name: file.name,
          size: bytes.length,
          isDirectory: false,
          relativePath: null,
          parentId: _currentFolderId,
          zone: zone,
          netbarId: netbarId,
          bytes: bytes,
          progress: 0,
          status: UploadStatus.pending,
          extractZip: extractZip && isZip,
        ),
      );
    }

    notifier.enqueue(tasks);
    _loadData();
  }

  Widget _buildDragOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: AppColors.iosBlue.withValues(alpha: 0.08),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.iosBlue, width: 2),
                boxShadow: AppShadows.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.upload, color: AppColors.iosBlue),
                  const SizedBox(width: 12),
                  const Text(
                    '松开鼠标上传文件',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- Startup item actions (align with ResourceManagement) ----

  Future<void> _handleDeleteStartupItem(StartupItem item) async {
    if (!_ensureCanEdit('删除启动项')) return;
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
    if (confirmed != true) return;

    try {
      await _startupItemApi.delete(item.id);
      _loadData();
      if (mounted) {
        showTopNotice(context, '删除成功', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _toggleStartupItemEnabled(StartupItem item, bool enable) async {
    if (!_ensureCanEdit(enable ? '启用启动项' : '禁用启动项')) return;
    try {
      if (enable) {
        await _startupItemApi.enable(item.id);
      } else {
        await _startupItemApi.disable(item.id, item.enabledState);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '更新启动项状态失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _handleBatchStartupEnable(bool enable) async {
    if (!_ensureCanEdit(enable ? '启用启动项' : '禁用启动项')) return;
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
    if (!_ensureCanEdit('删除启动项')) return;
    for (final item in _selectedStartupItems) {
      await _startupItemApi.delete(item.id);
    }
    _loadData();
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
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => AddStartupItemModal(
          zone: _currentZone,
          netbarId: _getNetbarId(),
          isAdmin: _isAdmin,
          onSuccess: _loadData,
          fullscreenSheet: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _currentZone,
        netbarId: _getNetbarId(),
        isAdmin: _isAdmin,
        onSuccess: _loadData,
      ),
    );
  }

  void _showStartupConfigModal(StartupItem item) {
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => StartupConfigModal(
          item: item,
          isAdmin: _isAdmin,
          areas: const [],
          onSuccess: _loadData,
          fullscreenSheet: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => StartupConfigModal(
        item: item,
        isAdmin: _isAdmin,
        areas: const [],
        onSuccess: _loadData,
      ),
    );
  }

  // ---- Build UI (align with ResourceManagement) ----

  @override
  Widget build(BuildContext context) {
    _isMobileFlag = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                if (!_isMobile) _buildSidebar(),
                Expanded(child: _buildMainArea()),
              ],
            ),
          ),
          if (_isMobile) _buildMobileZoneSelector(),
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
          const Text(
            '通道管理',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
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
            child: Text(
              '资源来源',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade500,
                letterSpacing: 1,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _buildZoneButton(
                  'PUBLIC',
                  LucideIcons.globe,
                  '本网吧资源',
                  subtitle: _canEdit
                      ? null
                      : (ref.watch(currentNetbarProvider).id == null
                            ? '（需选择网吧）'
                            : '（只读）'),
                ),
                const SizedBox(height: 4),
                _buildZoneButton(
                  'BRANCH',
                  LucideIcons.building2,
                  '分公司资源',
                  subtitle: '（只读）',
                ),
                const SizedBox(height: 4),
                _buildZoneButton(
                  'HEADQUARTERS',
                  LucideIcons.shieldAlert,
                  '总部资源',
                  subtitle: '（只读）',
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
      _buildZonePill(
        'PUBLIC',
        '本网吧',
        LucideIcons.globe,
        subtitle: _canEdit
            ? null
            : (ref.watch(currentNetbarProvider).id == null ? '需选择网吧' : '只读'),
      ),
      _buildZonePill('BRANCH', '分公司', LucideIcons.building2, subtitle: '只读'),
      _buildZonePill(
        'HEADQUARTERS',
        '总部',
        LucideIcons.shieldAlert,
        subtitle: '只读',
      ),
    ];
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 16,
              offset: Offset(0, -6),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: pills,
        ),
      ),
    );
  }

  Widget _buildZonePill(
    String zone,
    String label,
    IconData icon, {
    String? subtitle,
  }) {
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.iosBlue : Colors.grey.shade200,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? Colors.white : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    subtitle ?? ' ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.9)
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoneButton(
    String zone,
    IconData icon,
    String label, {
    String? subtitle,
  }) {
    final isActive = _currentZone == zone;
    return InkWell(
      onTap: () => _handleZoneChange(zone),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.iosBlue.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.iosBlue : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? AppColors.iosBlue : Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isActive
                          ? AppColors.iosBlue
                          : Colors.grey.shade800,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
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
    final isPhone = context.isPhone;
    final actions = <Widget>[];
    if (_activeModule == ModuleTab.files) {
      if (_isMobile) {
        actions.add(_buildSearchBox(width: double.infinity));
        actions.add(_buildLayoutToggle());
        if (_canEdit) actions.add(_buildUploadButton());
      } else {
        if (_canEdit) {
          if (_selectedResources.isNotEmpty) {
            actions.add(
              Text(
                '已选 ${_selectedResources.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            );
            actions.addAll([
              _buildBatchButton(
                '复制',
                LucideIcons.copy,
                AppColors.iosBlue,
                _handleBatchCopy,
              ),
              _buildBatchButton(
                '剪切',
                LucideIcons.scissors,
                Colors.orange,
                _handleBatchCut,
                enabled: _canEdit,
              ),
              _buildBatchButton(
                '删除',
                LucideIcons.trash2,
                Colors.red,
                _handleBatchDelete,
                enabled: _canEdit,
              ),
            ]);
          }
          actions.add(const SizedBox(width: 12));
          actions.add(
            _buildBatchButton(
              '粘贴${_clipboard.isNotEmpty ? ' (${_clipboard.length})' : ''}',
              LucideIcons.clipboard,
              Colors.green,
              _handlePaste,
              enabled: _canEdit && _clipboard.isNotEmpty,
            ),
          );
          actions.add(const SizedBox(width: 16));
        }

        actions.add(_buildSearchBox());
        actions.add(const SizedBox(width: 8));
        actions.add(_buildLayoutToggle());
        if (_canEdit) {
          actions.add(const SizedBox(width: 8));
          actions.add(_buildUploadButton());
        }
      }
    } else {
      if (_canEdit) {
        if (_selectedStartupItems.isNotEmpty) {
          actions.add(
            Text(
              '已选 ${_selectedStartupItems.length} 项',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          );
          actions.addAll([
            _buildBatchButton(
              isPhone ? '启用' : '批量启用',
              LucideIcons.toggleRight,
              const Color(0xFF22C55E),
              () => _handleBatchStartupEnable(true),
              enabled: _canEdit,
            ),
            _buildBatchButton(
              isPhone ? '禁用' : '批量禁用',
              LucideIcons.toggleLeft,
              Colors.grey.shade600,
              () => _handleBatchStartupEnable(false),
              enabled: _canEdit,
            ),
            _buildBatchButton(
              isPhone ? '删除' : '批量删除',
              LucideIcons.trash2,
              Colors.red,
              _handleBatchStartupDelete,
              enabled: _canEdit,
            ),
          ]);
        }
        actions.add(
          ElevatedButton.icon(
            onPressed: _showAddStartupItemModal,
            icon: const Icon(LucideIcons.plus, size: 14),
            label: const Text('新增启动项'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }
    }

    if (_isMobile) {
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
                _buildModuleTab(
                  ModuleTab.files,
                  LucideIcons.folderOpen,
                  '文件管理',
                ),
                const SizedBox(width: 12),
                _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
              ],
            ),
            const SizedBox(height: 8),
            if (_activeModule == ModuleTab.startup && _canEdit && isPhone) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildMobileActionButton(
                      label: '启用',
                      icon: LucideIcons.toggleRight,
                      color: const Color(0xFF22C55E),
                      enabled: _selectedStartupItems.isNotEmpty,
                      onTap: () => _handleBatchStartupEnable(true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMobileActionButton(
                      label: '禁用',
                      icon: LucideIcons.toggleLeft,
                      color: Colors.grey.shade600,
                      enabled: _selectedStartupItems.isNotEmpty,
                      onTap: () => _handleBatchStartupEnable(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMobileActionButton(
                      label: '删除',
                      icon: LucideIcons.trash2,
                      color: Colors.red,
                      enabled: _selectedStartupItems.isNotEmpty,
                      onTap: _handleBatchStartupDelete,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMobileActionButton(
                      label: '新增',
                      icon: LucideIcons.plus,
                      color: const Color(0xFF22C55E),
                      enabled: true,
                      onTap: _showAddStartupItemModal,
                    ),
                  ),
                ],
              ),
            ] else
              Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          _buildModuleTab(ModuleTab.files, LucideIcons.folderOpen, '文件管理'),
          const SizedBox(width: 12),
          _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }

  Widget _buildModuleTab(ModuleTab tab, IconData icon, String label) {
    final isActive = _activeModule == tab;
    return InkWell(
      onTap: () => _handleModuleChange(tab),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? Colors.grey.shade300 : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.grey.shade900 : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.grey.shade900 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.3)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: enabled ? color : Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? color : Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final bg = enabled ? color.withValues(alpha: 0.12) : Colors.grey.shade100;
    final fg = enabled ? color : Colors.grey.shade400;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? color.withValues(alpha: 0.25)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox({double width = 220}) {
    final hasText = _fileSearchController.text.trim().isNotEmpty;
    final borderColor =
        (_isSearching || hasText) ? AppColors.iosBlue : Colors.grey.shade200;

    return SizedBox(
      width: width,
      height: 32,
      child: TextField(
        controller: _fileSearchController,
        textInputAction: TextInputAction.search,
        onChanged: (v) {
          setState(() {});
          _scheduleSearch(v);
        },
        onSubmitted: (v) {
          _searchDebounce?.cancel();
          final q = v.trim();
          if (q.isEmpty) {
            _clearSearch();
          } else {
            _performSearch(q);
          }
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          hintText: '搜索文件...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Icon(
              LucideIcons.search,
              size: 14,
              color: _isSearching ? AppColors.iosBlue : Colors.grey.shade400,
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: '清除',
                  onPressed: _clearSearchAndText,
                  icon: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                )
              : null,
          contentPadding: EdgeInsets.zero,
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.iosBlue),
          ),
        ),
        style: const TextStyle(fontSize: 12),
        textAlignVertical: TextAlignVertical.center,
      ),
    );
  }

  Widget _buildLayoutToggle() {
    return SizedBox(
      height: 32,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildLayoutButton(LayoutMode.grid, LucideIcons.layoutGrid),
            _buildLayoutButton(LayoutMode.list, LucideIcons.list),
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
          borderRadius: BorderRadius.circular(4),
          boxShadow: isActive ? AppShadows.sm : null,
        ),
        child: Icon(
          icon,
          size: 16,
          color: isActive ? AppColors.iosBlue : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildUploadButton() {
    if (!_canEdit) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: _showUploadModal,
        icon: const Icon(LucideIcons.upload, size: 14),
        label: const Text('上传'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _folderHistory.length; i++) ...[
                    InkWell(
                      onTap: () => _handleBreadcrumbClick(i),
                      child: Text(
                        _folderHistory[i].name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == _folderHistory.length - 1
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: i == _folderHistory.length - 1
                              ? Colors.grey.shade900
                              : Colors.grey.shade500,
                        ),
                      ),
                    ),
                    if (i < _folderHistory.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          LucideIcons.chevronRight,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
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
    }
    return _buildStartupContent();
  }

  Widget _buildFilesContent() {
    final files = _filteredFiles;
    if (files.isEmpty) {
      return _buildEmptyState();
    }

    Widget fileListWidget = GestureDetector(
      onSecondaryTapDown: (details) {
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
            padding: _isMobile
                ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
                : const EdgeInsets.all(24),
            child: _layoutMode == LayoutMode.grid
                ? _buildFileGrid(files)
                : _buildFileList(files),
          ),
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

    if (kIsWeb) {
      return Stack(
        children: [
          fileListWidget,
          if (_isExternalDragOver) _buildDragOverlay(),
        ],
      );
    }

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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.folderOpen, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            _isSearching ? '未找到相关文件' : '暂无文件',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          if (_canEdit && !_isSearching)
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
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 1) {
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          _handleFileSelect(file, isCtrlPressed);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onDoubleTap: file.isDirectory
              ? () => _handleFolderOpen(file)
              : () => _handleOpenFile(file, readOnly: !_canEdit),
          onLongPressStart: (details) {
            if (!isSelected) {
              setState(() {
                _selectedIds.clear();
                _selectedIds.add(file.id.toString());
              });
            }
            _showFileContextMenu(details.globalPosition, file);
          },
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
              border: isSelected
                  ? Border.all(color: AppColors.iosBlue, width: 2)
                  : null,
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
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 1) {
          final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
          _handleFileSelect(file, isCtrlPressed);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onDoubleTap: file.isDirectory
              ? () => _handleFolderOpen(file)
              : () => _handleOpenFile(file, readOnly: !_canEdit),
          onLongPressStart: (details) {
            if (!isSelected) {
              setState(() {
                _selectedIds.clear();
                _selectedIds.add(file.id.toString());
              });
            }
            _showFileContextMenu(details.globalPosition, file);
          },
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

  Widget _buildStartupContent() {
    final items = _startupItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.zap, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              '暂无启动项',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            if (_canEdit)
              ElevatedButton.icon(
                onPressed: _showAddStartupItemModal,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('新增启动项'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 400,
        mainAxisExtent: 180,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildStartupCard(items[index]),
    );
  }

  Widget _buildStartupCard(StartupItem item) {
    final isSelected = _selectedIds.contains('startup-${item.id}');
    return _ResourceStartupCard(
      key: ValueKey('startup-${item.id}'),
      item: item,
      isSelected: isSelected,
      canEdit: _canEdit,
      updatedAtText: _formatDate(item.updatedAt),
      onToggleEnabled: _canEdit
          ? (val) => _toggleStartupItemEnabled(item, val)
          : null,
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ResourceStartupCard extends StatelessWidget {
  final StartupItem item;
  final bool isSelected;
  final bool canEdit;
  final String updatedAtText;
  final ValueChanged<bool>? onToggleEnabled;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback onSecondaryTapDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ResourceStartupCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.canEdit,
    required this.updatedAtText,
    required this.onToggleEnabled,
    required this.onTap,
    required this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (event.buttons == 1) onTap();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onDoubleTap: onDoubleTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onLongPressStart: (details) {
            onSecondaryTapDown(
              TapDownDetails(
                globalPosition: details.globalPosition,
                localPosition: details.localPosition,
              ),
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.iosBlue.withValues(alpha: 0.08)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.iosBlue : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: AppShadows.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.effectiveDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (onToggleEnabled != null)
                      Switch(
                        value: item.enabled,
                        onChanged: onToggleEnabled,
                        activeThumbColor: const Color(0xFF22C55E),
                      )
                    else
                      Text(
                        item.enabled ? '启用' : '禁用',
                        style: TextStyle(
                          fontSize: 12,
                          color: item.enabled
                              ? const Color(0xFF22C55E)
                              : Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const Spacer(),
                Row(
                  children: [
                    Text(
                      updatedAtText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    if (canEdit) ...[
                      _iconButton(LucideIcons.settings, onEdit),
                      const SizedBox(width: 8),
                      _iconButton(
                        LucideIcons.trash2,
                        onDelete,
                        color: Colors.red,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: (color ?? Colors.grey.shade600).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color ?? Colors.grey.shade600),
      ),
    );
  }
}
