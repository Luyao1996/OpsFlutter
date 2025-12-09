import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'platform_helper.dart';
import 'drop_target_stub.dart' if (dart.library.io) 'package:desktop_drop/desktop_drop.dart';
import 'web_drop_zone.dart';
import 'widgets/upload_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../data/resource_api.dart';
import '../data/startup_item_api.dart';
import '../../netbar/data/area_api.dart';
import 'widgets/add_startup_item_modal.dart';
import 'widgets/context_menu.dart';
import 'widgets/file_editor_modal.dart';
import 'widgets/file_icon.dart';
import 'widgets/disable_startup_modal.dart';
import 'widgets/startup_config_modal.dart';
import 'widgets/upload_modal.dart';
import '../../../shared/providers/upload_queue_provider.dart';

/// 文件来源
enum FileSource { local, hq, branch, shared }

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

/// 通道管理页面
class ChannelManagementPage extends ConsumerStatefulWidget {
  const ChannelManagementPage({super.key});

  @override
  ConsumerState<ChannelManagementPage> createState() => _ChannelManagementPageState();
}

class _ChannelManagementPageState extends ConsumerState<ChannelManagementPage> {
  final ResourceApi _resourceApi = ResourceApi();
  final StartupItemApi _startupItemApi = StartupItemApi();
  final AreaApi _areaApi = AreaApi();

  bool _isMobileFlag = false;
  bool get _isMobile => _isMobileFlag;

  FileSource _currentSource = FileSource.local;
  ModuleTab _activeModule = ModuleTab.files;
  LayoutMode _layoutMode = LayoutMode.grid;

  String _searchQuery = '';
  int? _currentFolderId;
  List<BreadcrumbItem> _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];

  List<Resource> _files = [];
  List<StartupItem> _startupItems = [];
  List<NetbarArea> _areas = []; // 网吧区域列表
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

  // 剪贴板
  List<Resource> _clipboard = [];
  bool _isCut = false;
  bool _isExternalDragOver = false;

  // 用于检测网吧切换
  int? _lastNetbarId;

  @override
  void initState() {
    super.initState();
    _loadData();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    // Web 平台注册拖拽和粘贴处理
    if (kIsWeb) {
      _registerWebDropZone();
      _registerWebPasteHandler();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboard);
    // Web 平台移除拖拽和粘贴处理
    if (kIsWeb) {
      webDropHandler.unregisterDropZone();
      webDropHandler.unregisterPasteHandler();
    }
    super.dispose();
  }

  /// Web 端注册拖拽区域
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

  /// Web 端注册粘贴处理
  void _registerWebPasteHandler() {
    webDropHandler.registerPasteHandler(onPaste: _handleWebPaste);
  }

  /// Web 端处理拖拽上传
  Future<void> _handleWebDrop(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    if (mounted) setState(() => _isExternalDragOver = false);

    // 转换为上传任务
    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _getZone();
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id = 'web-drop-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
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
      ));
    }

    notifier.enqueue(tasks);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加 ${files.length} 个文件到上传队列')),
      );
    }
  }

  /// Web 端处理粘贴上传
  Future<void> _handleWebPaste(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('粘贴')) return;
    if (_activeModule != ModuleTab.files) return;
    if (files.isEmpty) return;

    final notifier = ref.read(uploadQueueProvider.notifier);
    final tasks = <UploadTask>[];
    var counter = 0;
    final zone = _getZone();
    final netbarId = _getNetbarId();

    for (final file in files) {
      final id = 'web-paste-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
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
      ));
    }

    notifier.enqueue(tasks);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已粘贴 ${files.length} 个文件到上传队列')),
      );
    }
  }

  bool _handleKeyboard(KeyEvent event) {
    if (!mounted) return false;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _selectedIds.clear());
      return true;
    }
    return false;
  }

  String _getZone() {
    switch (_currentSource) {
      case FileSource.hq: return 'HEADQUARTERS';
      case FileSource.branch: return 'BRANCH';
      case FileSource.shared: return 'SHARED';
      case FileSource.local: return 'PUBLIC';
    }
  }

  int? _getNetbarId() {
    if (_currentSource == FileSource.local) {
      return ref.read(currentNetbarProvider).id;
    }
    return null;
  }

  bool get _isAdmin {
    final auth = ref.watch(authNotifierProvider);
    final role = auth.user?.role.toLowerCase() ?? '';
    return role.contains('admin');
  }

  /// 是否为只读来源（总部、分公司、共享区）
  bool get _isReadOnlySource {
    return _currentSource == FileSource.hq ||
           _currentSource == FileSource.branch ||
           _currentSource == FileSource.shared;
  }

  /// 是否可以编辑（文件上传、修改、启动项删除等）
  bool get _canEdit {
    // 总部、分公司、共享区的内容只读
    if (_isReadOnlySource) return false;
    // 本网吧需要选择网吧
    return _getNetbarId() != null;
  }

  /// 是否可以禁用启动项（总部和分公司的启动项可以禁用）
  bool get _canDisableStartupItem {
    // 本网吧的启动项可以禁用
    if (_currentSource == FileSource.local && _getNetbarId() != null) return true;
    // 总部和分公司的启动项也可以禁用（但不能删除）
    if (_currentSource == FileSource.hq || _currentSource == FileSource.branch) return true;
    return false;
  }

  /// 是否可以删除启动项
  bool get _canDeleteStartupItem {
    // 只有本网吧的启动项可以删除
    if (_currentSource == FileSource.local && _getNetbarId() != null) return true;
    return false;
  }

  String _editDeniedReason() {
    switch (_currentSource) {
      case FileSource.hq:
        return '总部资源只读';
      case FileSource.branch:
        return '分公司资源只读';
      case FileSource.shared:
        return '共享区资源只读，可拷贝到本网吧';
      case FileSource.local:
        return '请选择网吧后再编辑';
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
    setState(() { _loading = true; _error = null; });
    try {
      if (_activeModule == ModuleTab.files) {
        final resources = await _resourceApi.getAll(
          zone: _getZone(),
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
        );
        if (mounted) setState(() => _files = resources);
      } else {
        final items = await _startupItemApi.getAll(
          zone: _getZone(),
          netbarId: _getNetbarId(),
        );
        if (mounted) setState(() => _startupItems = items);
      }
      // 加载区域数据（用于启动项弹窗）
      final netbarId = _getNetbarId();
      if (netbarId != null) {
        try {
          final areas = await _areaApi.getByNetbar(netbarId);
          if (mounted) setState(() => _areas = areas);
        } catch (_) {
          // 区域加载失败不影响主流程
        }
      } else {
        if (mounted) setState(() => _areas = []);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleSourceChange(FileSource source) {
    setState(() {
      _currentSource = source;
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

  // 所有文件都可以编辑
  bool _isTextFile(Resource file) {
    return true;
  }

  bool _isExecutable(Resource file) {
    final name = file.name.toLowerCase();
    return name.endsWith('.exe') || name.endsWith('.bat');
  }

  void _handleFolderOpen(Resource folder) {
    setState(() {
      _currentFolderId = folder.id;
      _folderHistory.add(BreadcrumbItem(id: folder.id, name: folder.name));
      _selectedIds.clear();
      _draggingFileIds.clear();
      _dropTargetFolderId = null;
    });
    _loadData();
  }

  void _handleBreadcrumbClick(int index) {
    if (index >= _folderHistory.length - 1) return;
    setState(() {
      _currentFolderId = _folderHistory[index].id;
      _folderHistory = _folderHistory.sublist(0, index + 1);
      _selectedIds.clear();
    });
    _loadData();
  }

  // ========== 右键菜单 ==========
  void _showFileContextMenu(Offset position, Resource file) {
    final selected = _selectedIds.contains(file.id.toString())
        ? _files.where((f) => _selectedIds.contains(f.id.toString())).toList()
        : [file];
    showContextMenu(
      context: context,
      position: position,
      items: file.isDirectory
          ? FileContextMenuItems.forFolder(
              onOpen: () => _handleFolderOpen(file),
              onDownload: () => _handleDownload(file),
              onCopy: () => _handleCopy(selected),
              onCut: () => _handleCut(selected),
              onRename: () => _handleRename(file),
              onDelete: () => _handleDelete(selected),
              canEdit: _canEdit,
              canDownload: !kIsWeb,
            )
          : FileContextMenuItems.forFile(
              onOpen: () => _handleOpenFile(file),
              onEdit: () => _handleEditFile(file),
              onDownload: () => _handleDownload(file),
              onCopy: () => _handleCopy(selected),
              onCut: () => _handleCut(selected),
              onRename: () => _handleRename(file),
              onDelete: () => _handleDelete(selected),
              onAddToStartup: () => _handleAddToStartup(file),
              isTextFile: _isTextFile(file),
              canEdit: _canEdit,
              canAddToStartup: _isExecutable(file),
              canDownload: true,
            ),
    );
  }

  void _showEmptyContextMenu(Offset position) {
    showContextMenu(
      context: context,
      position: position,
      items: FileContextMenuItems.forEmpty(
        onNewFolder: _handleCreateFolder,
        onUpload: _showUploadModal,
        onPaste: _handlePaste,
        onRefresh: _loadData,
        canPaste: _clipboard.isNotEmpty,
        canEdit: _canEdit,
        clipboardCount: _clipboard.length,
      ),
    );
  }

  void _handleCopy(List<Resource> files) {
    setState(() {
      _clipboard = List.from(files);
      _isCut = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${files.length} 个项目'), duration: const Duration(seconds: 2)),
    );
  }

  void _handleCut(List<Resource> files) {
    if (!_ensureCanEdit('?????')) return;
    setState(() {
      _clipboard = List.from(files);
      _isCut = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已剪切 ${files.length} 个项目'), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _handlePaste() async {
    if (!_ensureCanEdit('粘贴')) return;
    if (_clipboard.isEmpty) return;
    try {
      final List<Resource> newFiles = [];
      final zone = _getZone();
      final netbarId = _getNetbarId();
      for (final file in _clipboard) {
        if (_isCut) {
            final moved = await _resourceApi.move(
              file.id,
              _currentFolderId,
              netbarId: netbarId,
              zone: zone,
            );
            newFiles.add(moved);
        } else {
            final copied = await _resourceApi.copy(
              file.id,
              _currentFolderId,
              netbarId: netbarId,
              zone: zone,
            );
            newFiles.add(copied);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_isCut ? '已移动' : '已粘贴'} ${_clipboard.length} 个项目',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      if (_isCut) {
        setState(() {
          _clipboard.clear();
          _isCut = false;
        });
      }
      // 如果目标是当前目录，直接合并显示，随后刷新确保状态一致
      if (_currentFolderId != null) {
        setState(() {
          _files.addAll(newFiles.where((f) => f.parentId == _currentFolderId));
        });
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('粘贴失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleRename(Resource file) {
    if (!_ensureCanEdit('重命名')) return;
    final controller = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '新名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == file.name) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context);
              try {
                await _resourceApi.update(file.id, name: newName);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已重命名为: $newName')),
                  );
                }
                _loadData();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('重命名失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _handleDelete(List<Resource> files) {
    if (!_ensureCanEdit('删除')) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 ${files.length} 个项目吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                for (final file in files) {
                  await _resourceApi.delete(file.id);
                }
                setState(() => _selectedIds.clear());
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除 ${files.length} 个项目')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleBatchCopy() {
    if (_selectedResources.isEmpty) return;
    _handleCopy(_selectedResources);
  }

  void _handleBatchCut() {
    if (_selectedResources.isEmpty) return;
    _handleCut(_selectedResources);
  }

  void _handleBatchDelete() {
    if (_selectedResources.isEmpty) return;
    _handleDelete(_selectedResources);
  }

  /// 拷贝选中的文件到本网吧
  Future<void> _handleCopyToLocal() async {
    final files = _selectedResources;
    if (files.isEmpty) return;

    final netbarId = ref.read(currentNetbarProvider).id;
    if (netbarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个网吧')),
      );
      return;
    }

    try {
      int success = 0;
      for (final file in files) {
        // 拷贝到本网吧根目录（zone=PUBLIC, netbarId=当前网吧ID, parentId=null）
        await _resourceApi.copy(
          file.id,
          null, // 拷贝到根目录
          zone: 'PUBLIC',
          netbarId: netbarId,
        );
        success++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已拷贝 $success 个文件到本网吧')),
        );
      }
      setState(() => _selectedIds.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拷贝失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 拷贝选中的启动项到本网吧
  Future<void> _handleCopyStartupToLocal() async {
    final items = _selectedStartupItems;
    if (items.isEmpty) return;

    final netbarId = ref.read(currentNetbarProvider).id;
    if (netbarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择一个网吧')),
      );
      return;
    }

    try {
      int success = 0;
      for (final item in items) {
        // 解析 targetIpRanges JSON 字符串
        List<Map<String, dynamic>>? targetIpRanges;
        if (item.targetIpRanges != null && item.targetIpRanges!.isNotEmpty) {
          try {
            final decoded = jsonDecode(item.targetIpRanges!);
            if (decoded is List) {
              targetIpRanges = decoded.cast<Map<String, dynamic>>();
            }
          } catch (_) {}
        }

        // 解析 releaseFiles JSON 字符串
        List<Map<String, dynamic>>? releaseFiles;
        if (item.releaseFiles != null && item.releaseFiles!.isNotEmpty) {
          try {
            final decoded = jsonDecode(item.releaseFiles!);
            if (decoded is List) {
              releaseFiles = decoded.cast<Map<String, dynamic>>();
            }
          } catch (_) {}
        }

        // 创建新的启动项到本网吧
        await _startupItemApi.create(
          name: item.name,
          displayName: item.displayName,
          path: item.path,
          zone: 'PUBLIC',
          netbarId: netbarId,
          enabled: item.enabled,
          args: item.args,
          delay: item.delay,
          forceRun: item.forceRun,
          workingDir: item.workingDir,
          targetOs: item.targetOs,
          targetAreas: item.targetAreas,
          targetIpRanges: targetIpRanges,
          timeRange: item.timeRange,
          crashAction: item.crashAction,
          runAsService: item.runAsService,
          randomProcessName: item.randomProcessName,
          releaseFiles: releaseFiles,
        );
        success++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已拷贝 $success 个启动项到本网吧')),
        );
      }
      setState(() => _selectedIds.clear());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拷贝失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleOpenFile(Resource file) {
    if (_isTextFile(file)) {
      _handleEditFile(file);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('暂不支持预览该类型文件: ${file.name}')),
    );
  }

  Future<void> _handleDownload(Resource file) async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Web 暂不支持下载')));
      return;
    }

    // 先选择保存目录
    final saveDir = await platformHelper.pickDirectory();
    if (saveDir == null) return;

    // 确保组件仍然挂载
    if (!mounted) return;

    // 开始下载
    await _executeDownload(file, saveDir);
  }

  Future<void> _executeDownload(Resource file, String saveDir) async {
    final fileName = file.isDirectory ? '${file.name}.zip' : file.name;
    final progressNotifier = ValueNotifier<double>(0);

    // 使用 OverlayEntry 而不是 showDialog，更安全
    OverlayEntry? overlayEntry;

    void showProgress() {
      overlayEntry = OverlayEntry(
        builder: (context) => Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('下载中: $fileName', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (_, progress, __) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(value: progress > 0 ? progress : null),
                          const SizedBox(height: 8),
                          Text('${(progress * 100).toStringAsFixed(1)}%'),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(overlayEntry!);
    }

    void hideProgress() {
      overlayEntry?.remove();
      overlayEntry = null;
      progressNotifier.dispose();
    }

    showProgress();

    try {
      List<int> bytes;
      if (file.isDirectory) {
        bytes = await _resourceApi.downloadDirectoryZip(
          file.id,
          onReceiveProgress: (received, total) {
            if (total > 0) progressNotifier.value = received / total;
          },
        );
      } else {
        bytes = await _resourceApi.downloadBytes(
          file.id,
          onReceiveProgress: (received, total) {
            if (total > 0) progressNotifier.value = received / total;
          },
        );
      }

      if (bytes.isEmpty) throw Exception('文件为空或无法获取');

      final savedPath = await platformHelper.saveBytesToDirectory(saveDir, fileName, bytes);

      hideProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(savedPath != null ? '已保存到 $savedPath' : '保存失败')),
        );
      }
    } catch (e) {
      hideProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleEditFile(Resource file) {
    showDialog(
      context: context,
      builder: (context) => FileEditorModal(
        file: file,
        onSuccess: () => _loadData(),
      ),
    );
  }

  void _handleAddToStartup(Resource file) {
    if (!_ensureCanEdit('添加到启动项')) return;
    if (!_isExecutable(file)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅可添加 .exe / .bat 文件到启动项')),
      );
      return;
    }
    _showAddStartupItemModal(defaultPath: file.name);
  }

  Future<void> _handleExternalDrop(List<dynamic> files) async {
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    setState(() => _isExternalDragOver = false);

    // 非 Web 平台：检查是否有目录
    if (!kIsWeb && platformHelper.isDesktop) {
      final tasks = <UploadTask>[];
      var counter = 0;

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
                  zone: _getZone(),
                  netbarId: _getNetbarId(),
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
                  zone: _getZone(),
                  netbarId: _getNetbarId(),
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
              zone: _getZone(),
              netbarId: _getNetbarId(),
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
          zone: _getZone(),
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
          SnackBar(content: Text('已上传 $success 个文件')),
        );
      }
    }
  }

  void _startFileDrag(Resource file) {
    final ids = _selectedIds.isNotEmpty
        ? _selectedIds
        : {file.id.toString()};
    setState(() {
      _selectedIds = ids;
      _draggingFileIds = ids.map(int.parse).toSet();
    });
  }

  void _endFileDrag() {
    setState(() {
      _draggingFileIds.clear();
      _dropTargetFolderId = null;
    });
  }

  Future<void> _handleFileDrop(Resource targetFolder) async {
    if (!_ensureCanEdit('移动')) return;
    if (!targetFolder.isDirectory) return;
    if (_draggingFileIds.isEmpty) return;
    try {
      for (final id in _draggingFileIds) {
        await _resourceApi.move(id, targetFolder.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已移动 ${_draggingFileIds.length} 个项目到 ${targetFolder.name}')),
        );
      }
      _endFileDrag();
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移动失败: $e'), backgroundColor: Colors.red),
        );
      }
      _endFileDrag();
    }
  }

  Future<void> _handleBatchStartupEnable(bool enabled) async {
    final items = _selectedStartupItems;
    if (items.isEmpty) return;
    if (!_canDisableStartupItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${enabled ? "批量启用" : "批量禁用"}失败：${_editDeniedReason()}')),
      );
      return;
    }
    try {
      for (final item in items) {
        await _startupItemApi.update(item.id, enabled: enabled);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${enabled ? '已启用' : '已禁用'} ${items.length} 个启动项'),
          ),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('批量操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleBatchStartupDelete() async {
    final items = _selectedStartupItems;
    if (items.isEmpty) return;
    if (!_canDeleteStartupItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量删除失败：只有本网吧的启动项可以删除')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 ${items.length} 个启动项吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      for (final item in items) {
        await _startupItemApi.delete(item.id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${items.length} 个启动项')),
        );
      }
      setState(() => _selectedIds.clear());
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _handleCreateFolder() {
    if (!_ensureCanEdit('新建文件夹')) return;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '文件夹名称'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context);
              try {
                await _resourceApi.create(
                  name: controller.text.trim(),
                  type: 'folder',
                  isDirectory: true,
                  zone: _getZone(),
                  parentId: _currentFolderId,
                  netbarId: _getNetbarId(),
                );
                final created = await _resourceApi.getAll(
                  zone: _getZone(),
                  parentId: _currentFolderId,
                  netbarId: _getNetbarId(),
                  search: controller.text.trim(),
                );
                final newFolder = created.firstWhere(
                  (r) => r.name == controller.text.trim() && r.isDirectory,
                  orElse: () => Resource(
                    id: -1,
                    name: controller.text.trim(),
                    type: 'folder',
                    isDirectory: true,
                    parentId: _currentFolderId,
                    size: 0,
                    zone: _getZone(),
                    isGlobal: false,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
                setState(() => _selectedIds = {newFolder.id.toString()});
                _loadData();
                if (newFolder.id != -1) {
                  // 弹出重命名对话框，方便继续修改
                  _handleRename(newFolder);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已创建文件夹: ${controller.text}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('创建失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  void _showUploadModal() {
    if (!_ensureCanEdit('上传')) return;
    showDialog(
      context: context,
      builder: (context) => UploadModal(
        zone: _getZone(),
        parentId: _currentFolderId,
        netbarId: _getNetbarId(),
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  // ========== 拖选 ==========
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
      const maxCrossAxisExtent = 100.0;
      const spacing = 12.0;
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

  Rect? get _selectionRect {
    if (!_isDragSelecting || _dragStartPosition == null || _dragCurrentPosition == null) {
      return null;
    }
    return Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
  }

  List<Resource> get _filteredFiles {
    var result = _files.where((f) => f.parentId == _currentFolderId).toList();
    if (_searchQuery.isNotEmpty) {
      result = result.where((f) => 
        f.name.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    result.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return result;
  }

  List<StartupItem> get _filteredStartupItems {
    if (_searchQuery.isEmpty) return _startupItems;
    return _startupItems.where((s) =>
      s.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  List<StartupItem> get _selectedStartupItems {
    return _startupItems
        .where((s) => _selectedIds.contains('startup-${s.id}'))
        .toList();
  }

  List<Resource> get _selectedResources {
    return _files.where((f) => _selectedIds.contains(f.id.toString())).toList();
  }

  /// 获取本网吧的名称（用于侧边栏第一项，始终显示网吧名）
  String _getLocalSourceName() {
    final netbar = ref.watch(currentNetbarProvider);
    return netbar.name?.isNotEmpty == true ? netbar.name! : '本网吧';
  }

  String _getSourceName() {
    switch (_currentSource) {
      case FileSource.local: return _getLocalSourceName();
      case FileSource.hq: return '总部资源';
      case FileSource.branch: return '分公司资源';
      case FileSource.shared: return '共享区';
    }
  }

  @override
  Widget build(BuildContext context) {
    _isMobileFlag = platformHelper.isMobile || MediaQuery.of(context).size.width < 900;
    // 监听网吧切换，切换后立即刷新数据
    final currentNetbar = ref.watch(currentNetbarProvider);
    if (_lastNetbarId != null && _lastNetbarId != currentNetbar.id) {
      // 网吧已切换，立即刷新
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectedIds.clear();
        _currentFolderId = null;
        _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
        _loadData();
      });
    }
    _lastNetbarId = currentNetbar.id;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _isMobile ? _buildMobileSourceSelector() : null,
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
          Container(width: 1, height: 24, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(horizontal: 16)),
          const Text('通道管理', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
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
        child: Icon(icon, size: 16, color: isActive ? Colors.grey.shade900 : Colors.grey.shade500),
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
            child: Text('资源来源', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _buildSourceButton(FileSource.local, LucideIcons.home, _getLocalSourceName()),
                const SizedBox(height: 4),
                _buildSourceButton(FileSource.hq, LucideIcons.shieldAlert, '总部资源'),
                const SizedBox(height: 4),
                _buildSourceButton(FileSource.branch, LucideIcons.building2, '分公司资源'),
                const SizedBox(height: 4),
                _buildSourceButton(FileSource.shared, LucideIcons.share2, '共享区'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceButton(FileSource source, IconData icon, String label) {
    final isActive = _currentSource == source;
    return GestureDetector(
      onTap: () => _handleSourceChange(source),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.iosBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive ? [BoxShadow(color: AppColors.iosBlue.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isActive ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isActive ? Colors.white : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
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

  Widget _buildMobileSourceSelector() {
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
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSourcePill(FileSource.local, _getLocalSourceName(), LucideIcons.home),
            _buildSourcePill(FileSource.hq, '总部资源', LucideIcons.shieldAlert),
            _buildSourcePill(FileSource.branch, '分公司资源', LucideIcons.building2),
            _buildSourcePill(FileSource.shared, '共享区', LucideIcons.share2),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceChip(FileSource source, String label) {
    final isActive = _currentSource == source;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 13, color: isActive ? Colors.white : Colors.grey.shade700)),
        selected: isActive,
        onSelected: (_) => _handleSourceChange(source),
        selectedColor: AppColors.iosBlue,
        backgroundColor: Colors.grey.shade100,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildSourcePill(FileSource source, String label, IconData icon) {
    final isActive = _currentSource == source;
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleSourceChange(source),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModuleTabs() {
    if (_isMobile) {
      final actions = <Widget>[];
      if (_activeModule == ModuleTab.files) {
        if (_selectedResources.isNotEmpty) {
          actions.add(Text('已选 ${_selectedResources.length} 项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)));
          actions.add(const SizedBox(width: 8));
          actions.addAll([
            _buildBatchButton('复制', LucideIcons.copy, AppColors.iosBlue, _handleBatchCopy),
            _buildBatchButton('剪切', LucideIcons.scissors, Colors.orange, _handleBatchCut, enabled: _canEdit),
            _buildBatchButton('删除', LucideIcons.trash2, Colors.red, _handleBatchDelete, enabled: _canEdit),
          ]);
          if (_currentSource == FileSource.shared) {
            actions.add(_buildBatchButton('拷贝到本网吧', LucideIcons.download, const Color(0xFF22C55E), _handleCopyToLocal));
          }
        }
        actions.add(_buildBatchButton(
          '粘贴${_clipboard.isNotEmpty ? ' (${_clipboard.length})' : ''}',
          LucideIcons.clipboard,
          Colors.green,
          _handlePaste,
          enabled: _canEdit && _clipboard.isNotEmpty,
        ));
        actions.add(_buildSearchField(width: 220));
        actions.add(_buildLayoutToggle());
        actions.add(_buildUploadButton());
      } else if (_activeModule == ModuleTab.startup) {
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildModuleTab(ModuleTab.files, LucideIcons.folderOpen, '文件管理'),
                  const SizedBox(width: 12),
                  _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
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
              Text('已选${_selectedResources.length} 项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(width: 12),
              _buildBatchButton('复制', LucideIcons.copy, AppColors.iosBlue, _handleBatchCopy),
              const SizedBox(width: 8),
              _buildBatchButton('剪切', LucideIcons.scissors, Colors.orange, _handleBatchCut, enabled: _canEdit),
              const SizedBox(width: 8),
              _buildBatchButton('删除', LucideIcons.trash2, Colors.red, _handleBatchDelete, enabled: _canEdit),
              // 只有共享区才显示"拷贝到本网吧"按钮
              if (_currentSource == FileSource.shared) ...[
                const SizedBox(width: 8),
                _buildBatchButton('拷贝到本网吧', LucideIcons.download, const Color(0xFF22C55E), _handleCopyToLocal),
              ],
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
            _buildSearchField(width: 160),
            const SizedBox(width: 8),
            // 布局切换
            _buildLayoutToggle(),
            const SizedBox(width: 8),
            // 上传按钮
            _buildUploadButton(),
          ] else if (_activeModule == ModuleTab.startup && _selectedStartupItems.isNotEmpty) ...[
            Text('已选 ${_selectedStartupItems.length} 项', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(width: 12),
            _buildBatchButton('批量启用', LucideIcons.toggleRight, const Color(0xFF22C55E), () => _handleBatchStartupEnable(true), enabled: _canDisableStartupItem),
            const SizedBox(width: 8),
            _buildBatchButton('批量禁用', LucideIcons.toggleLeft, Colors.grey.shade600, () => _handleBatchStartupEnable(false), enabled: _canDisableStartupItem),
            const SizedBox(width: 8),
            _buildBatchButton('批量删除', LucideIcons.trash2, Colors.red, _handleBatchStartupDelete, enabled: _canDeleteStartupItem),
          ],
          if (_activeModule == ModuleTab.startup) ...[
            const SizedBox(width: 12),
            ElevatedButton.icon(
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
            ),
          ],
        ],
      ),
    );
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
            Icon(icon, size: 16, color: isActive ? Colors.grey.shade900 : Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isActive ? Colors.grey.shade900 : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchButton(String label, IconData icon, Color color, VoidCallback onTap, {bool enabled = true}) {
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
                  fontWeight: i == _folderHistory.length - 1 ? FontWeight.w500 : FontWeight.normal,
                  color: i == _folderHistory.length - 1 ? Colors.grey.shade900 : Colors.grey.shade500,
                ),
              ),
            ),
            if (i < _folderHistory.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(LucideIcons.chevronRight, size: 14, color: Colors.grey.shade400),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent() {
    Widget child;
    if (_loading) {
      child = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      child = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text('重新加载')),
          ],
        ),
      );
    } else {
      child = _activeModule == ModuleTab.files ? _buildFileList() : _buildStartupList();
    }

    // Web 端：使用 Stack 显示拖拽覆盖层（拖拽事件由 webDropHandler 处理）
    if (kIsWeb && _activeModule == ModuleTab.files) {
      return Stack(
        children: [
          child,
          if (_isExternalDragOver) _buildDragOverlay(),
        ],
      );
    }

    // 非文件模块或移动端：直接返回
    if (_activeModule != ModuleTab.files || platformHelper.isMobile || !platformHelper.isDesktop) {
      return child;
    }

    // 桌面端：使用 desktop_drop 包的 DropTarget
    return DropTarget(
      onDragEntered: (_) => setState(() => _isExternalDragOver = true),
      onDragExited: (_) => setState(() => _isExternalDragOver = false),
      onDragDone: (details) => _handleExternalDrop(details.files),
      child: Stack(
        children: [
          child,
          if (_isExternalDragOver) _buildDragOverlay(),
        ],
      ),
    );
  }

  /// 构建拖拽覆盖层
  Widget _buildDragOverlay() {
    return Positioned.fill(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.iosBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.iosBlue, width: 2, style: BorderStyle.solid),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppShadows.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.uploadCloud, size: 32, color: AppColors.iosBlue),
                    const SizedBox(height: 12),
                    const Text('松开鼠标即可上传', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('支持拖入文件和文件夹', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileList() {
    final files = _filteredFiles;
    if (files.isEmpty) {
      return GestureDetector(
        onSecondaryTapDown: (details) => _showEmptyContextMenu(details.globalPosition),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.folderOpen, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('暂无文件', style: TextStyle(color: Colors.grey.shade400)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _canEdit ? _showUploadModal : null,
                icon: const Icon(LucideIcons.upload, size: 16),
                label: const Text('上传文件'),
              ),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
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
            padding: EdgeInsets.all(_isMobile ? 12 : 24),
            child: _layoutMode == LayoutMode.grid ? _buildFileGrid(files) : _buildFileListView(files),
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
  }

  Widget _buildFileGrid(List<Resource> files) {
    return GridView.builder(
      key: _gridKey,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: _isMobile ? 120 : 100,
        mainAxisSpacing: _isMobile ? 8 : 12,
        crossAxisSpacing: _isMobile ? 8 : 12,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) => _buildFileGridItem(files[index]),
    );
  }

  void _handleFileSelect(Resource file, bool isCtrlPressed) {
    final fileId = file.id.toString();
    setState(() {
      if (isCtrlPressed) {
        // Ctrl+点击: 切换选中状态
        if (_selectedIds.contains(fileId)) {
          _selectedIds.remove(fileId);
        } else {
          _selectedIds.add(fileId);
        }
      } else {
        // 普通点击: 单选
        _selectedIds.clear();
        _selectedIds.add(fileId);
      }
    });
  }

  Widget _buildFileGridItem(Resource file) {
    final isSelected = _selectedIds.contains(file.id.toString());
    final isDropHighlight = _dropTargetFolderId == file.id && file.isDirectory;
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
          child: LongPressDraggable<Set<int>>(
            data: _selectedIds.map(int.parse).toSet(),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: () => _startFileDrag(file),
            onDraggableCanceled: (_, __) => _endFileDrag(),
            onDragEnd: (_) => _endFileDrag(),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.8,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.iosBlue, width: 2),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Text('${_selectedIds.length} 项', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
            child: DragTarget<Set<int>>(
              onWillAccept: (ids) {
                final canAccept = file.isDirectory && (ids?.contains(file.id) != true);
                if (canAccept) setState(() => _dropTargetFolderId = file.id);
                return canAccept;
              },
              onLeave: (_) => setState(() => _dropTargetFolderId = null),
              onAccept: (_) => _handleFileDrop(file),
              builder: (context, _, __) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDropHighlight
                        ? Colors.green.shade50
                        : (isSelected ? AppColors.iosBlue.withValues(alpha: 0.1) : Colors.transparent),
                    borderRadius: BorderRadius.circular(8),
                    border: isDropHighlight
                        ? Border.all(color: Colors.green, width: 2)
                        : (isSelected ? Border.all(color: AppColors.iosBlue, width: 2) : null),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FileIcon(type: file.type, isDirectory: file.isDirectory, size: 32),
                      const SizedBox(height: 4),
                      Text(file.name, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileListView(List<Resource> files) {
    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildFileListItem(files[index]),
    );
  }

  Widget _buildFileListItem(Resource file) {
    final isSelected = _selectedIds.contains(file.id.toString());
    final isDropHighlight = _dropTargetFolderId == file.id && file.isDirectory;
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
          child: LongPressDraggable<Set<int>>(
            data: _selectedIds.map(int.parse).toSet(),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            onDragStarted: () => _startFileDrag(file),
            onDraggableCanceled: (_, __) => _endFileDrag(),
            onDragEnd: (_) => _endFileDrag(),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.8,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.iosBlue, width: 2),
                    boxShadow: AppShadows.sm,
                  ),
                  child: Text('${_selectedIds.length} 项', style: const TextStyle(fontSize: 12)),
                ),
              ),
            ),
            child: DragTarget<Set<int>>(
              onWillAccept: (ids) {
                final canAccept = file.isDirectory && (ids?.contains(file.id) != true);
                if (canAccept) setState(() => _dropTargetFolderId = file.id);
                return canAccept;
              },
              onLeave: (_) => setState(() => _dropTargetFolderId = null),
              onAccept: (_) => _handleFileDrop(file),
              builder: (context, _, __) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDropHighlight
                        ? Colors.green.shade50
                        : (isSelected ? AppColors.iosBlue.withValues(alpha: 0.1) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: isDropHighlight
                        ? Border.all(color: Colors.green, width: 2)
                        : (isSelected ? Border.all(color: AppColors.iosBlue, width: 2) : null),
                  ),
                  child: Row(
                    children: [
                      FileIcon(type: file.type, isDirectory: file.isDirectory, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Text(file.name, style: const TextStyle(fontSize: 14))),
                      SizedBox(width: 80, child: Text(file.formattedSize, style: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                      SizedBox(width: 120, child: Text(file.formattedUpdateTime, style: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _showAddStartupItemModal({String? defaultPath, String? defaultWorkingDir}) {
    if (!_ensureCanEdit('新增启动项')) return;
    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _getZone(),
        netbarId: _getNetbarId(),
        defaultPath: defaultPath,
        defaultWorkingDir: defaultWorkingDir,
        isAdmin: _isAdmin,
        areas: _areas,
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  void _showEditStartupItemModal(StartupItem item) {
    showDialog(
      context: context,
      builder: (context) => StartupConfigModal(
        item: item,
        isAdmin: _isAdmin,
        areas: _areas,
        onSuccess: () {
          _loadData();
        },
      ),
    );
  }

  Future<bool> _confirmDisableStartup(StartupItem item) async {
    final result = await showDisableStartupModal(
      context,
      itemName: item.effectiveDisplayName,
      currentlyEnabled: item.enabled,
      areas: _areas,
      currentState: item.enabled ? null : item.enabledState,
    );
    if (result == null) return false;

    // 如果返回的是启用状态，则启用
    if (result.status) {
      try {
        await _startupItemApi.enable(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已启用: ${item.effectiveDisplayName}')),
          );
        }
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('启用失败: $e')),
          );
        }
      }
      return false; // 不需要再调用 update
    }

    // 禁用
    try {
      await _startupItemApi.disable(item.id, result);
      final suffix = result.isPermanent ? '永久禁用' : '禁用${result.durationDays ?? 0}天';
      final strategyText = result.strategy == 'specific' ? ' (指定范围)' : '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已提交${item.effectiveDisplayName}的$suffix$strategyText')),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('禁用失败: $e')),
        );
      }
    }
    return false; // 已经处理了 API 调用，不需要再调用 update
  }

  void _handleDeleteStartupItem(StartupItem item) {
    if (!_ensureCanEdit('删除启动项')) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除启动项 "${item.effectiveDisplayName}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _startupItemApi.delete(item.id);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已删除启动项: ${item.effectiveDisplayName}')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showStartupItemContextMenu(Offset position, StartupItem item) {
    final canEdit = _canEdit;
    final canDisable = _canDisableStartupItem;
    final canDelete = _canDeleteStartupItem;
    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: '编辑配置',
          icon: LucideIcons.settings,
          onTap: canEdit ? () => _showEditStartupItemModal(item) : null,
          disabled: !canEdit,
        ),
        ContextMenuItem(
          label: '测试运行',
          icon: LucideIcons.play,
          onTap: () => _handleTestRun(item),
        ),
        ContextMenuItem(
          label: item.enabled ? '禁用' : '启用',
          icon: item.enabled ? LucideIcons.toggleLeft : LucideIcons.toggleRight,
          onTap: canDisable
              ? () async {
                  if (item.enabled) {
                    // 禁用：显示禁用弹窗，弹窗内部处理 API 调用
                    await _confirmDisableStartup(item);
                  } else {
                    // 启用：直接调用 API
                    try {
                      await _startupItemApi.enable(item.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已启用: ${item.effectiveDisplayName}')),
                        );
                      }
                      _loadData();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('启用失败: $e')),
                        );
                      }
                    }
                  }
                }
              : null,
          disabled: !canDisable,
        ),
        ContextMenuItem(
          label: '删除',
          icon: LucideIcons.trash2,
          color: Colors.red,
          onTap: canDelete ? () => _handleDeleteStartupItem(item) : null,
          disabled: !canDelete,
          divider: true,
        ),
      ],
    );
  }

  void _handleTestRun(StartupItem item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已下发测试运行: ${item.effectiveDisplayName}')),
    );
  }

  Widget _buildStartupList() {
    final items = _filteredStartupItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.zap, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('暂无启动项', style: TextStyle(color: Colors.grey.shade400)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _canEdit ? _showAddStartupItemModal : null,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('新增启动项'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.all(_isMobile ? 12 : 24),
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
    return _HoverableStartupCard(
      key: ValueKey('startup-${item.id}'),
      item: item,
      isSelected: isSelected,
      canEdit: _canEdit,
      canDisable: _canDisableStartupItem,
      canDelete: _canDeleteStartupItem,
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
      onDoubleTap: _canEdit ? () => _showEditStartupItemModal(item) : null,
      onSecondaryTapDown: (details) {
        if (!isSelected) {
          setState(() {
            _selectedIds.clear();
            _selectedIds.add('startup-${item.id}');
          });
        }
        _showStartupItemContextMenu(details.globalPosition, item);
      },
      // 点击开关：启用→禁用弹框，禁用→直接启用
      onConfirmDisable: () => _confirmDisableStartup(item),
      onEnable: () async {
        try {
          await _startupItemApi.enable(item.id);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已启用: ${item.effectiveDisplayName}')),
            );
          }
          _loadData();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('启用失败: $e')),
            );
          }
        }
      },
      onEdit: () => _showEditStartupItemModal(item),
      onTestRun: () => _handleTestRun(item),
      onDelete: () => _handleDeleteStartupItem(item),
    );
  }
}

/// 可悬停的启动项卡片组件
class _HoverableStartupCard extends StatefulWidget {
  final StartupItem item;
  final bool isSelected;
  final bool canEdit;
  final bool canDisable; // 是否可以禁用/启用
  final bool canDelete; // 是否可以删除
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(TapDownDetails) onSecondaryTapDown;
  final Future<void> Function() onConfirmDisable; // 禁用时弹框
  final Future<void> Function() onEnable; // 启用时直接调用
  final VoidCallback onEdit;
  final VoidCallback onTestRun;
  final VoidCallback onDelete;

  const _HoverableStartupCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.canEdit,
    required this.canDisable,
    required this.canDelete,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTapDown,
    required this.onConfirmDisable,
    required this.onEnable,
    required this.onEdit,
    required this.onTestRun,
    required this.onDelete,
  });

  @override
  State<_HoverableStartupCard> createState() => _HoverableStartupCardState();
}

class _HoverableStartupCardState extends State<_HoverableStartupCard> {
  bool _isHovered = false;

  DateTime? _lastTapTime;

  void _handleTap() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds < 300) {
      // 双击
      _lastTapTime = null;
      widget.onDoubleTap?.call();
    } else {
      // 单击 - 立即选中
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
        // 立即响应点击，不等待双击检测
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
          // 紧凑单行布局
          child: Row(
            children: [
              // 图标
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: widget.item.enabled ? const Color(0xFFDCFCE7) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.zap,
                  size: 16,
                  color: widget.item.enabled ? const Color(0xFF16A34A) : Colors.grey.shade400,
                ),
              ),
              const SizedBox(width: 10),
              // 名称和信息
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 启动项名称 + 执行文件名
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.item.effectiveDisplayName,
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 只有当有显示名称时，才额外显示文件路径
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
                    // 简化信息行
                    Row(
                      children: [
                        // 禁用状态信息
                        if (!widget.item.enabled) ...[
                          // 临时禁用提示
                          if (widget.item.enabledState.duration != null &&
                              widget.item.enabledState.duration != 'permanent') ...[
                            Icon(LucideIcons.clock, size: 10, color: Colors.amber.shade600),
                            const SizedBox(width: 2),
                            Text('临时禁用 ${widget.item.enabledState.durationDays ?? widget.item.enabledState.duration} 天',
                              style: TextStyle(fontSize: 10, color: Colors.amber.shade600)),
                            const SizedBox(width: 6),
                          ],
                          // 部分禁用提示
                          if (widget.item.disableStrategy == 'specific') ...[
                            Icon(LucideIcons.target, size: 10, color: Colors.amber.shade600),
                            const SizedBox(width: 2),
                            Text('部分禁用', style: TextStyle(fontSize: 10, color: Colors.amber.shade600)),
                            const SizedBox(width: 6),
                          ],
                        ],
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
                    _buildCardActionButton(
                      icon: LucideIcons.play,
                      tooltip: '测试运行',
                      onTap: widget.onTestRun,
                    ),
                    if (widget.canDelete)
                      _buildCardActionButton(
                        icon: LucideIcons.trash2,
                        tooltip: '删除',
                        onTap: widget.onDelete,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 开关
              Transform.scale(
                scale: 0.7,
                child: _buildSwitchWithColor(
                  item: widget.item,
                  canDisable: widget.canDisable,
                  onConfirmDisable: widget.onConfirmDisable,
                  onEnable: widget.onEnable,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建带颜色的开关
  /// - 启用：绿色
  /// - 半禁用（specific策略）：黄色
  /// - 完全禁用：灰色（默认）
  Widget _buildSwitchWithColor({
    required StartupItem item,
    required bool canDisable,
    required Future<void> Function() onConfirmDisable,
    required Future<void> Function() onEnable,
  }) {
    // 判断是否为半禁用状态
    final isPartialDisabled = !item.enabled && item.disableStrategy == 'specific';

    // 确定开关颜色
    Color switchColor;
    if (item.enabled) {
      switchColor = const Color(0xFF22C55E); // 绿色
    } else if (isPartialDisabled) {
      switchColor = const Color(0xFFF59E0B); // 黄色/琥珀色
    } else {
      switchColor = Colors.grey.shade400; // 灰色
    }

    // 半禁用时，开关处于"开"的位置但颜色为黄色
    final switchValue = item.enabled || isPartialDisabled;

    return Switch(
      value: switchValue,
      onChanged: canDisable
          ? (v) async {
              if (!v || isPartialDisabled) {
                // 启用→禁用 或 半禁用→完全禁用/启用：弹出禁用框
                await onConfirmDisable();
              } else {
                // 禁用→启用：直接启用
                await onEnable();
              }
            }
          : null,
      activeColor: switchColor,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: Colors.grey.shade300,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
