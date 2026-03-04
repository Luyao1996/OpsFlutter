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
import 'package:path/path.dart' as p;

import '../../../shared/utils/web_download_helper_stub.dart'
    if (dart.library.html) '../../../shared/utils/web_download_helper_web.dart';

import '../../../core/responsive/responsive.dart';
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
import '../../../shared/utils/resource_path_display.dart';
import '../../channel/presentation/widgets/disable_startup_modal.dart';
import '../../channel/presentation/widgets/startup_config_modal.dart';
import '../../channel/presentation/widgets/upload_modal.dart';
import '../../../shared/providers/upload_queue_provider.dart';
import '../../../shared/utils/top_notice.dart';

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

  final TextEditingController _fileSearchController = TextEditingController();
  Timer? _searchDebounce;

  bool _isMobileFlag = false;
  bool get _isMobile => _isMobileFlag;

  ResourceZone _currentZone = ResourceZone.headquarters;
  ModuleTab _activeModule = ModuleTab.files;
  LayoutMode _layoutMode = LayoutMode.grid;

  String _searchQuery = '';
  int? _currentFolderId;
  List<BreadcrumbItem> _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];

  List<Resource> _files = [];
  List<Resource> _searchResults = []; // 搜索结果
  bool _isSearching = false; // 是否正在搜索模式
  List<TacticItem> _startupItems = [];
  final List<NetbarArea> _areas = [];
  final Set<String> _selectedIds = {};
  final Set<int> _draggingFileIds = {};
  int? _dropTargetFolderId;

  // 网吧视图选择（分公司资源用）
  List<MerchantOption> _merchants = [];
  int? _selectedMerchantId;

  bool _loading = false;
  String? _error;

  // 拖选相关状态
  bool _isDragSelecting = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;
  final GlobalKey _gridKey = GlobalKey();

  // 拖选矩形
  Rect? get _selectionRect {
    if (!_isDragSelecting ||
        _dragStartPosition == null ||
        _dragCurrentPosition == null) {
      return null;
    }
    return Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
  }

  // 剪贴板
  List<Resource> _clipboard = [];
  bool _isCut = false;
  bool _isExternalDragOver = false;

  // 网吧切换监听
  ProviderSubscription<CurrentNetbar>? _netbarSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    HardwareKeyboard.instance.addHandler(_handleKeyboard);
    if (kIsWeb) {
      _registerWebDropZone();
      _registerWebPasteHandler();
    }

    // 监听网吧切换，自动刷新数据
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
            _searchQuery = '';
            _fileSearchController.clear();
            _isSearching = false;
            _searchResults.clear();
          });
          _loadData();
        }
      },
    );
  }

  List<TacticItem> get _selectedStartupItems {
    return _startupItems
        .where((s) => _selectedIds.contains('startup-${s.id}'))
        .toList();
  }

  bool get _canDisableStartupItem => false; // 资源管理中启动项只读
  bool get _canDeleteStartupItem => false; // 资源管理中启动项只读

  Future<void> _handleBatchStartupEnable(bool enable) async {
    if (!_ensureCanEdit(enable ? '启用启动项' : '禁用启动项')) return;
    for (final item in _selectedStartupItems) {
      final startupId = item.startupId;
      if (startupId == null) continue;
      if (enable) {
        await _startupItemApi.enable(startupId);
      } else {
        await _startupItemApi.disable(startupId, item.enabledState);
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

  Future<void> _toggleStartupItemEnabled(TacticItem item, bool enable) async {
    if (!_ensureCanEdit(enable ? '启用启动项' : '禁用启动项')) return;
    final startupId = item.startupId;
    if (startupId == null) return;
    try {
      if (enable) {
        await _startupItemApi.enable(startupId);
      } else {
        await _startupItemApi.disable(startupId, item.enabledState);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '更新启动项状态失败: $e', level: NoticeLevel.error);
      }
    }
  }

  Widget _buildSearchField({double width = 160}) {
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
          _performSearch(v.trim());
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
              color: Colors.grey.shade400,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 28,
          ),
          suffixIcon: _fileSearchController.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: '清除',
                  onPressed: _clearSearchAndText,
                  icon: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: Colors.grey.shade500,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
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

  /// 网吧选择器
  Widget _buildMerchantSelector() {
    return SizedBox(
      height: 32,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            value: _selectedMerchantId,
            hint: Text(
              '选择网吧视图',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            isDense: true,
            icon: Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey.shade500),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Row(
                  children: [
                    Icon(LucideIcons.x, size: 12, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text('清除选择', style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
              ..._merchants.map((m) => DropdownMenuItem<int?>(
                value: m.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.building2, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(m.name),
                    if (m.terminalCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '(${m.terminalCount}台)',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                      ),
                    ],
                  ],
                ),
              )),
            ],
            onChanged: _handleMerchantSelect,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _netbarSubscription?.close();
    _searchDebounce?.cancel();
    _fileSearchController.dispose();
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
    final zipFiles = fileNames
        .where((name) => name.toLowerCase().endsWith('.zip'))
        .toList();

    // 如果没有ZIP文件，不需要解压
    if (zipFiles.isEmpty) return false;

    // 如果只有一个文件且是ZIP，或者全是ZIP文件，弹窗询问
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

  Future<void> _handleWebDrop(List<WebDropFileInfo> files) async {
    if (!mounted) return;
    if (!_ensureCanEdit('上传')) return;
    if (files.isEmpty) return;
    if (mounted) setState(() => _isExternalDragOver = false);

    // 检查是否需要解压ZIP
    final fileNames = files
        .where((f) => !f.isDirectory)
        .map((f) => f.name)
        .toList();
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

    // 检查是否需要解压ZIP
    final fileNames = files
        .where((f) => !f.isDirectory)
        .map((f) => f.name)
        .toList();
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

  /// 处理系统剪贴板粘贴（桌面端）
  Future<void> _handleSystemClipboardPaste() async {
    if (!_canEdit) return;
    if (kIsWeb) return; // Web 端由 _handleWebPaste 处理

    try {
      // 从系统剪贴板获取文件路径
      final paths = await platformFileHelper.getClipboardFilePaths();
      if (paths.isEmpty) {
        if (mounted) {
          showTopNotice(context, '剪贴板中没有文件', level: NoticeLevel.warning);
        }
        return;
      }

      // 读取文件内容
      final items = await platformFileHelper.readFilesFromPaths(paths);
      if (items.isEmpty) {
        if (mounted) {
          showTopNotice(context, '无法读取剪贴板中的文件', level: NoticeLevel.error);
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
        showTopNotice(context, '已添加 ${tasks.length} 个项目到上传队列', level: NoticeLevel.success);
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '粘贴失败: $e', level: NoticeLevel.error);
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
  /// - 总部(HEADQUARTERS): 不传 merchant_id（显示 group_id=0 的文件）
  /// - 分公司(BRANCH): merchant_id = 选中的网吧ID（网吧视图）
  /// - 共享区(SHARED): 所有人可访问
  int? _getNetbarId() {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return null; // 总部不传 merchant_id
      case ResourceZone.branch:
        // 分公司用选中的网吧ID
        return _selectedMerchantId;
      case ResourceZone.shared:
        return null; // 共享区不需要 merchant_id
    }
  }

  /// 获取启动项查询用的 netbar_id
  /// 后端 `/startup-items` 对非超管要求必须传 netbar_id，因此共享区也使用 0（全局）。
  int _getStartupNetbarId() {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return 0;
      case ResourceZone.branch:
        return ref.read(currentNetbarProvider).id ?? 0;
      case ResourceZone.shared:
        return 0;
    }
  }

  bool get _isAdmin {
    final auth = ref.watch(authNotifierProvider);
    return auth.user?.hasAdminAccess == true;
  }

  int get _userGroupId {
    final auth = ref.watch(authNotifierProvider);
    return auth.user?.groupId ?? 0;
  }

  int get _currentUserId {
    final auth = ref.watch(authNotifierProvider);
    return auth.user?.id ?? 0;
  }

  /// 是否是超级管理员（总部管理员，group_id == 0 或 null）
  bool get _isSuperAdmin {
    final auth = ref.watch(authNotifierProvider);
    final groupId = auth.user?.groupId;
    return groupId == null || groupId == 0;
  }

  /// 是否是管理员（SuperAdmin 或 分部管理员）
  bool get _isManager {
    final auth = ref.watch(authNotifierProvider);
    return auth.user?.hasAdminAccess == true;
  }

  /// 是否显示启动项 Tab（仅网吧资源显示）
  bool get _showStartupTab => _currentZone == ResourceZone.branch;

  /// 是否可以编辑文件（根据区域和角色判断）
  bool get _canEdit {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return _isSuperAdmin; // 总公司资源：仅 SuperAdmin 可编辑
      case ResourceZone.branch:
        return _isManager; // 网吧资源：SuperAdmin 和 Admin 可编辑
      case ResourceZone.shared:
        return _isManager; // 共享资源：SuperAdmin 和 Admin 可编辑（普通用户在 _canEditFile 中额外检查）
    }
  }

  /// 检查是否可以编辑指定文件（共享区需检查文件所有者）
  bool _canEditFile(Resource file) {
    if (_currentZone == ResourceZone.shared) {
      // 共享资源：SuperAdmin/Admin 可编辑，普通用户仅可编辑自己上传的文件
      if (_isManager) return true;
      return file.uploaderId == _currentUserId;
    }
    return _canEdit;
  }

  /// 启动项编辑权限（资源管理中全部只读）
  bool get _canEditStartup => false;

  /// 启动项启用/禁用权限（资源管理中全部只读）
  bool get _canToggleStartup => false;

  /// 是否可以查看当前区域
  bool get _canView {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return true; // 所有人可查看总公司资源
      case ResourceZone.branch:
        return true; // 所有人可查看网吧资源
      case ResourceZone.shared:
        return true; // 共享资源所有人可查看
    }
  }

  String _editDeniedReason() {
    switch (_currentZone) {
      case ResourceZone.headquarters:
        return '总公司资源仅超级管理员可编辑';
      case ResourceZone.branch:
        return '网吧资源仅管理员可编辑';
      case ResourceZone.shared:
        return '共享资源仅管理员或文件上传者可编辑';
    }
  }

  /// 选中的网吧名称
  String? get _selectedMerchantName {
    if (_selectedMerchantId == null) return null;
    final merchant = _merchants.where((m) => m.id == _selectedMerchantId).firstOrNull;
    return merchant?.name;
  }

  bool _ensureCanEdit(String actionLabel) {
    if (_canEdit) return true;
    showTopNotice(context, '$actionLabel失败：${_editDeniedReason()}', level: NoticeLevel.warning);
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
        List<Resource> resources;
        if (_currentZone == ResourceZone.shared) {
          // 共享资源：调用 /file/shared
          resources = await _resourceApi.getSharedFiles(parentId: _currentFolderId);
        } else {
          // 总公司资源和网吧资源：调用 /file/view，然后根据 group_id 过滤
          final response = await _resourceApi.getAllWithMerchants(
            parentId: _currentFolderId,
          );
          // 保存网吧列表
          if (_currentFolderId == null && response.merchants.isNotEmpty) {
            _merchants = response.merchants;
          }
          // 根据 group_id 过滤
          if (_currentZone == ResourceZone.headquarters) {
            // 总公司资源：group_id == 0
            resources = response.files.where((f) => f.groupId == 0 || f.groupId == null).toList();
          } else {
            // 网吧资源：group_id != 0
            resources = response.files.where((f) => f.groupId != null && f.groupId != 0).toList();
          }
        }
        if (mounted) setState(() => _files = resources);
      } else {
        // 启动项：仅网吧资源时加载
        if (_currentZone == ResourceZone.branch) {
          final items = await _startupItemApi.getAll();
          if (mounted) setState(() => _startupItems = items);
        } else {
          // 总公司和共享资源不显示启动项
          if (mounted) setState(() => _startupItems = []);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '加载失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _handleZoneChange(ResourceZone zone) {
    _searchDebounce?.cancel();
    _fileSearchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _currentZone = zone;
      _currentFolderId = null;
      _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
      _selectedIds.clear();
      // 如果不是网吧资源区域，自动切换到文件Tab（因为启动项Tab不显示）
      if (zone != ResourceZone.branch && _activeModule == ModuleTab.startup) {
        _activeModule = ModuleTab.files;
      }
    });
    _loadData();
  }

  /// 处理网吧视图选择
  void _handleMerchantSelect(int? merchantId) {
    setState(() {
      _selectedMerchantId = merchantId;
      _currentFolderId = null;
      _folderHistory = [BreadcrumbItem(id: null, name: '根目录')];
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleModuleChange(ModuleTab module) {
    _searchDebounce?.cancel();
    _fileSearchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _activeModule = module;
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleBreadcrumbClick(int index) {
    _searchDebounce?.cancel();
    _fileSearchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
      _currentFolderId = _folderHistory[index].id;
      _folderHistory = _folderHistory.sublist(0, index + 1);
      _selectedIds.clear();
    });
    _loadData();
  }

  void _handleFolderOpen(Resource folder) {
    _searchDebounce?.cancel();
    _fileSearchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
      _searchResults = [];
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

  List<TacticItem> get _filteredStartupItems {
    // 仅网吧资源区域显示启动项
    if (_currentZone != ResourceZone.branch) {
      return [];
    }

    var items = _startupItems.toList();

    // 根据当前网吧ID过滤启动项
    final currentNetbarId = ref.read(currentNetbarProvider).id;
    if (currentNetbarId != null) {
      items = items.where((item) => item.merchantId == currentNetbarId).toList();
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      items = items
          .where(
            (f) => f.effectiveDisplayName.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }
    return items;
  }

  /// 执行后端搜索
  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      _clearSearch();
      return;
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
        zone: _getZoneString(),
        netbarId: _getNetbarId(),
        parentId: _currentFolderId,
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

  void _clearSearchAndText() {
    _searchDebounce?.cancel();
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
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _performSearch(q);
    });
  }

  List<Resource> get _selectedResources {
    final byId = <String, Resource>{};
    for (final f in _files) {
      byId[f.id.toString()] = f;
    }
    for (final f in _searchResults) {
      byId[f.id.toString()] = f;
    }
    final selected = <Resource>[];
    for (final id in _selectedIds) {
      final f = byId[id];
      if (f != null) selected.add(f);
    }
    return selected;
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
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => UploadModal(
          zone: _getZoneString(),
          parentId: _currentFolderId,
          netbarId: _getNetbarId(),
          onSuccess: () => _loadData(),
          presentation: UploadModalPresentation.sheet,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => UploadModal(
        zone: _getZoneString(),
        parentId: _currentFolderId,
        netbarId: _getNetbarId(),
        onSuccess: () => _loadData(),
        presentation: UploadModalPresentation.dialog,
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
          showTopNotice(context, '已创建文件夹: $result', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '创建失败: $e', level: NoticeLevel.error);
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

  void _handleOpenFile(Resource file, {bool readOnly = false}) {
    final category = FileIcon.getTypeFromName(file.name);
    if (category == 'image') {
      _showImagePreview(file);
      return;
    }

    if (!FileIcon.isTextFile(file.name)) {
      // 二进制文件不在内置预览范围，提示下载
    showTopNotice(context, '该文件类型仅支持下载查看', level: NoticeLevel.warning);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => FileEditorModal(
        file: file,
        readOnly: readOnly,
        onSuccess: () {
          _loadData();
        },
      ),
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

  Future<void> _handleDownload(Resource file) async {
    if (kIsWeb) {
      try {
        final bytes = await _resourceApi.downloadBytes(file.id);
        await downloadBytesAsFile(bytes, file.name);
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '下载失败: $e', level: NoticeLevel.error);
        }
      }
    } else {
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

    showContextMenu(
      context: context,
      position: position,
      items: [
        ContextMenuItem(
          label: '新建文件夹',
          icon: LucideIcons.folderPlus,
          onTap: _handleCreateFolder,
        ),
        ContextMenuItem(
          label: '上传文件',
          icon: LucideIcons.upload,
          onTap: _showUploadModal,
        ),
        if (_clipboard.isNotEmpty)
          ContextMenuItem(
            label: '粘贴 (已复制${_clipboard.length}个项)',
            icon: LucideIcons.clipboard,
            onTap: _handlePaste,
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
    // "添加到启动项"条件：exe 文件 && 选择了网吧 && 是管理员（不受 _canEdit 限制）
    final netbarId = ref.read(currentNetbarProvider).id;
    final auth = ref.read(authNotifierProvider);
    final isManager = auth.user?.hasAdminAccess == true;
    final canAddStartup = netbarId != null && isManager;
    final isExe = !file.isDirectory && file.name.toLowerCase().endsWith('.exe') && canAddStartup;
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

  /// 获取当前目录路径（基于面包屑导航）
  String _getCurrentFolderPath() {
    if (_folderHistory.length <= 1) return '';
    return _folderHistory.skip(1).map((b) => b.name).join('/');
  }

  /// 构建文件的完整路径
  String _buildFullPath(Resource file) {
    if (file.path.isNotEmpty && file.path.contains('/')) {
      return file.path;
    }
    final folderPath = _getCurrentFolderPath();
    return folderPath.isNotEmpty ? '$folderPath/${file.name}' : file.name;
  }

  void _showAddStartupFromFile(Resource file) {
    // 检查是否选择了网吧
    final netbarId = ref.read(currentNetbarProvider).id;
    if (netbarId == null) {
      showTopNotice(context, '请先选择网吧', level: NoticeLevel.warning);
      return;
    }
    final auth = ref.read(authNotifierProvider);
    if (auth.user?.hasAdminAccess != true) {
      showTopNotice(context, '无启动项编辑权限', level: NoticeLevel.warning);
      return;
    }

    final fullPath = _buildFullPath(file);

    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => AddStartupItemModal(
          zone: _getZoneString(),
          netbarId: netbarId,
          resourceId: file.id,
          defaultPath: fullPath,
          defaultWorkingDir: deriveDirectoryFromPath(fullPath),
          isAdmin: _isAdmin,
          areas: _areas,
          onSuccess: _loadData,
          fullscreenSheet: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _getZoneString(),
        netbarId: netbarId,
        resourceId: file.id,
        defaultPath: fullPath,
        defaultWorkingDir: deriveDirectoryFromPath(fullPath),
        isAdmin: _isAdmin,
        areas: _areas,
        onSuccess: _loadData,
      ),
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
          showTopNotice(context, '已删除: ${file.name}', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
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
          showTopNotice(context, '删除成功', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
        }
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
        showTopNotice(context, '已拷贝到本网吧', level: NoticeLevel.success);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '拷贝失败: $e', level: NoticeLevel.error);
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
      final prevPending = prev.tasks
          .where(
            (t) =>
                t.status == UploadStatus.pending ||
                t.status == UploadStatus.uploading,
          )
          .length;
      final nextPending = next.tasks
          .where(
            (t) =>
                t.status == UploadStatus.pending ||
                t.status == UploadStatus.uploading,
          )
          .length;

      // 当有任务完成（从有待处理任务变为无待处理任务）时刷新
      if (prevPending > 0 && nextPending == 0 && next.tasks.isNotEmpty) {
        _loadData();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      bottomNavigationBar: _isMobile ? _buildMobileZoneSelector() : null,
      body: _isMobile
          ? _buildMainArea()
          : Row(
              children: [
                _buildSidebar(),
                Expanded(child: _buildMainArea()),
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
              '资源区域',
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
                  ResourceZone.headquarters,
                  LucideIcons.shieldAlert,
                  '总公司资源',
                  subtitle: _isSuperAdmin ? null : '（只读）',
                ),
                const SizedBox(height: 4),
                _buildZoneButton(
                  ResourceZone.branch,
                  LucideIcons.building2,
                  '网吧资源',
                ),
                const SizedBox(height: 4),
                _buildZoneButton(
                  ResourceZone.shared,
                  LucideIcons.share2,
                  '共享资源',
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
        ResourceZone.headquarters,
        '总部',
        LucideIcons.shieldAlert,
        subtitle: _isSuperAdmin ? null : '只读',
      ),
      _buildZonePill(
        ResourceZone.branch,
        '网吧',
        LucideIcons.building2,
      ),
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
    ResourceZone zone,
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
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.iosBlue : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.iosBlue.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isActive ? Colors.white : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                if (subtitle == null)
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : Colors.grey.shade700,
                    ),
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? Colors.white : Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? Colors.white70
                              : Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoneButton(
    ResourceZone zone,
    IconData icon,
    String label, {
    String? subtitle,
  }) {
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
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? Colors.white : Colors.grey.shade600,
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
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? Colors.white70 : Colors.grey.shade400,
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
    if (_isMobile) {
      final isPhone = context.isPhone;
      final quickActions = <Widget>[];
      final utilityActions = <Widget>[];

      if (_activeModule == ModuleTab.files) {
        utilityActions.add(_buildLayoutToggle());
        if (_canEdit) utilityActions.add(_buildUploadButton());
      } else {
        // 资源管理中启动项完全只读，不显示任何编辑按钮
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
                _buildModuleTab(
                  ModuleTab.files,
                  LucideIcons.folderOpen,
                  '文件管理',
                ),
                if (_showStartupTab) ...[
                  const SizedBox(width: 12),
                  _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
                ],
              ],
            ),
            if (_activeModule == ModuleTab.files &&
                _selectedResources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已选 ${_selectedResources.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
            if (_activeModule == ModuleTab.startup &&
                _selectedStartupItems.isNotEmpty &&
                !isPhone) ...[
              const SizedBox(height: 8),
              Text(
                '已选 ${_selectedStartupItems.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
            if (quickActions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: quickActions),
            ],
            const SizedBox(height: 8),
            if (_activeModule == ModuleTab.files)
              Row(
                children: [
                  Expanded(child: _buildSearchField(width: double.infinity)),
                  const SizedBox(width: 8),
                  for (int i = 0; i < utilityActions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    utilityActions[i],
                  ],
                ],
              )
            // 资源管理中启动项完全只读，不显示移动端编辑按钮
            else if (utilityActions.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: utilityActions),
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
          if (_showStartupTab) ...[
            const SizedBox(width: 16),
            _buildModuleTab(ModuleTab.startup, LucideIcons.zap, '启动项'),
          ],
          const Spacer(),
          if (_activeModule == ModuleTab.files) ...[
            if (_selectedResources.isNotEmpty) ...[
              Text(
                '已选 ${_selectedResources.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 12),
              _buildBatchButton(
                '复制',
                LucideIcons.copy,
                AppColors.iosBlue,
                _handleBatchCopy,
              ),
              if (_canEdit) ...[
                const SizedBox(width: 8),
                _buildBatchButton(
                  '剪切',
                  LucideIcons.scissors,
                  Colors.orange,
                  _handleBatchCut,
                  enabled: _canEdit,
                ),
                const SizedBox(width: 8),
                _buildBatchButton(
                  '删除',
                  LucideIcons.trash2,
                  Colors.red,
                  _handleBatchDelete,
                  enabled: _canEdit,
                ),
              ],
            ],
            if (_canEdit && _clipboard.isNotEmpty) ...[
              const SizedBox(width: 12),
              _buildBatchButton(
                '粘贴 (${_clipboard.length})',
                LucideIcons.clipboard,
                Colors.green,
                _handlePaste,
              ),
            ],
            if (_selectedResources.isNotEmpty || (_canEdit && _clipboard.isNotEmpty)) const SizedBox(width: 16),
            // 搜索框
            Container(
              width: 200,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isSearching
                      ? AppColors.iosBlue
                      : Colors.grey.shade200,
                ),
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
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      child: Icon(
                        LucideIcons.search,
                        size: 14,
                        color: _isSearching
                            ? AppColors.iosBlue
                            : Colors.grey.shade400,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    suffixIcon: _isSearching
                        ? IconButton(
                            onPressed: _clearSearch,
                            icon: Icon(
                              LucideIcons.x,
                              size: 14,
                              color: Colors.grey.shade400,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
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
            if (_canEdit) ...[
              const SizedBox(width: 8),
              // 上传按钮
              ElevatedButton.icon(
                onPressed: _showUploadModal,
                icon: const Icon(LucideIcons.upload, size: 14),
                label: const Text('上传'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.iosBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
          // 资源管理中启动项完全只读，不显示任何编辑按钮
          if (_activeModule == ModuleTab.startup) ...[
            // 仅显示已选数量（只读状态）
            if (_selectedStartupItems.isNotEmpty) ...[
              Text(
                '已选 ${_selectedStartupItems.length} 项',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
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
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.grey.shade900 : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.grey.shade900 : Colors.grey.shade500,
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: (enabled ? color : Colors.grey).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
          mainAxisSize: MainAxisSize.min,
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
          color: isActive ? Colors.grey.shade900 : Colors.grey.shade500,
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isMobile ? 12 : 24,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _folderHistory.length; i++) ...[
              GestureDetector(
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
            padding: _isMobile
                ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
                : const EdgeInsets.all(24),
            child: _layoutMode == LayoutMode.grid
                ? _buildFileGrid(files)
                : _buildFileList(files),
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
        if (filePath.isEmpty) continue;

        try {
          // 使用 platformFileHelper 检查是否为目录
          if (platformFileHelper.isDirectory(filePath)) {
            // 是目录，递归读取
            final dirItems = await platformFileHelper.readDirectoryFromPath(
              filePath,
            );
            for (final item in dirItems) {
              final id =
                  'upload-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
              if (item.isDirectory) {
                tasks.add(
                  UploadTask(
                    id: id,
                    name: item.name,
                    size: 0,
                    isDirectory: true,
                    relativePath: item.relativePath,
                    parentId: _currentFolderId,
                    zone: zone,
                    netbarId: netbarId,
                    bytes: null,
                  ),
                );
              } else if (item.bytes != null) {
                tasks.add(
                  UploadTask(
                    id: id,
                    name: item.name,
                    size: item.bytes!.length,
                    isDirectory: false,
                    relativePath: item.relativePath,
                    parentId: _currentFolderId,
                    zone: zone,
                    netbarId: netbarId,
                    bytes: item.bytes,
                  ),
                );
              }
            }
          } else {
            // 是文件
            final bytes = await xf.readAsBytes();
            final fileName = xf.name.isNotEmpty
                ? xf.name
                : p.basename(filePath);
            final id =
                'upload-${DateTime.now().millisecondsSinceEpoch}-${counter++}';
            tasks.add(
              UploadTask(
                id: id,
                name: fileName,
                size: bytes.length,
                isDirectory: false,
                relativePath: fileName,
                parentId: _currentFolderId,
                zone: zone,
                netbarId: netbarId,
                bytes: bytes,
              ),
            );
          }
        } catch (e) {
          debugPrint('处理拖拽项失败: $e');
        }
      }

      if (tasks.isNotEmpty) {
        ref.read(uploadQueueProvider.notifier).enqueue(tasks);
        if (mounted) {
          showTopNotice(context, '已添加 ${tasks.length} 个项目到上传队列', level: NoticeLevel.success);
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
        final fileName = xf.name.isNotEmpty ? xf.name : (p.basename(xf.path));
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
        showTopNotice(context, '成功上传 $success 个文件', level: NoticeLevel.success);
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
              const Text(
                '释放以上传文件',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
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
            // 资源管理中启动项只读，不显示添加按钮
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

  Widget _buildStartupCard(TacticItem item) {
    final isSelected = _selectedIds.contains('startup-${item.id}');
    return _ResourceStartupCard(
      key: ValueKey('startup-${item.id}'),
      item: item,
      isSelected: isSelected,
      canEdit: _canEditStartup, // 资源管理中启动项只读
      updatedAtText: _formatDate(DateTime.tryParse(item.updatedAt) ?? DateTime.now()),
      onToggleEnabled: null, // 资源管理中启动项不可启用/禁用
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
      onDoubleTap: null, // 资源管理中启动项不可双击编辑
      onSecondaryTapDown: (details) {
        if (!isSelected) {
          setState(() {
            _selectedIds.clear();
            _selectedIds.add('startup-${item.id}');
          });
        }
        _showStartupItemContextMenu(details.globalPosition, item);
      },
      onEdit: null, // 资源管理中启动项不可编辑
      onDelete: null, // 资源管理中启动项不可删除
    );
  }

  void _showStartupItemContextMenu(Offset position, TacticItem item) {
    // 资源管理中启动项只读，右键菜单为空
    // 可以考虑不显示右键菜单，或者只显示"查看"选项
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
          zone: _getZoneString(),
          netbarId: _getNetbarId(),
          isAdmin: _isAdmin,
          areas: _areas,
          onSuccess: _loadData,
          fullscreenSheet: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AddStartupItemModal(
        zone: _getZoneString(),
        netbarId: _getNetbarId(),
        isAdmin: _isAdmin,
        areas: _areas,
        onSuccess: _loadData,
      ),
    );
  }

  void _showStartupConfigModal(TacticItem item) {
    if (context.isPhone) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        enableDrag: false,
        builder: (context) => StartupConfigModal(
          item: item,
          isAdmin: _isAdmin,
          areas: _areas,
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
        areas: _areas,
        onSuccess: _loadData,
      ),
    );
  }

  Future<void> _handleDeleteStartupItem(TacticItem item) async {
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
    if (confirmed == true) {
      try {
        await _startupItemApi.delete(item.id);
        _loadData();
        if (mounted) {
          showTopNotice(context, '已删除: ${item.effectiveDisplayName}', level: NoticeLevel.success);
        }
      } catch (e) {
        if (mounted) {
          showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
        }
      }
    }
  }
}

/// 资源管理启动项卡片组件（样式与通道管理启动项一致）
class _ResourceStartupCard extends StatefulWidget {
  final TacticItem item;
  final bool isSelected;
  final bool canEdit;
  final String updatedAtText;
  final ValueChanged<bool>? onToggleEnabled;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final Function(TapDownDetails) onSecondaryTapDown;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ResourceStartupCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.canEdit,
    required this.updatedAtText,
    this.onToggleEnabled,
    required this.onTap,
    this.onDoubleTap,
    required this.onSecondaryTapDown,
    this.onEdit,
    this.onDelete,
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
    if (_lastTapTime != null &&
        now.difference(_lastTapTime!).inMilliseconds < 300) {
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
        onLongPressStart: (details) {
          widget.onSecondaryTapDown(
            TapDownDetails(
              globalPosition: details.globalPosition,
              localPosition: details.localPosition,
            ),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.iosBlue
                  : Colors.grey.shade200,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: widget.isSelected
                ? null
                : (_isHovered ? AppShadows.lg : AppShadows.sm),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.item.enabled
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      LucideIcons.zap,
                      color: widget.item.enabled ? Colors.green : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                widget.item.effectiveDisplayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.canEdit)
                              Switch.adaptive(
                                value: widget.item.enabled,
                                activeColor: AppColors.iosBlue,
                                onChanged: widget.onToggleEnabled,
                              ),
                          ],
                        ),
                        Text(
                          formatPathWithZone(
                            widget.item.path,
                            detectZoneFromPath(widget.item.path) ??
                                widget.item.zone,
                            maxLength: 36,
                          ),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if ((widget.item.delay ?? 0) > 0)
                    _buildTag(
                      LucideIcons.clock,
                      '${widget.item.delay}s',
                      Colors.orange,
                    ),
                  if (widget.item.args?.isNotEmpty == true)
                    _buildTag(LucideIcons.terminal, '参数', Colors.blue),
                  if (widget.item.forceRun)
                    _buildTag(LucideIcons.alertCircle, '强制', Colors.red),
                  if (widget.item.targetOs?.isNotEmpty == true)
                    _buildTag(
                      LucideIcons.monitor,
                      widget.item.targetOs!,
                      Colors.purple,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.updatedAtText,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  if (widget.canEdit && (widget.onEdit != null || widget.onDelete != null))
                    Row(
                      children: [
                        if (widget.onEdit != null)
                          _buildIconButton(LucideIcons.settings, widget.onEdit!),
                        if (widget.onEdit != null && widget.onDelete != null)
                          const SizedBox(width: 4),
                        if (widget.onDelete != null)
                          _buildIconButton(
                            LucideIcons.trash2,
                            widget.onDelete!,
                            color: Colors.red,
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(IconData icon, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback onTap, {
    Color color = Colors.grey,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 16,
          color: color == Colors.red
              ? Colors.red.shade400
              : Colors.grey.shade400,
        ),
      ),
    );
  }
}
