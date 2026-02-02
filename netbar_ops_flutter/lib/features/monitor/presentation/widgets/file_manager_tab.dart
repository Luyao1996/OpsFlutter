import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

import 'file_download_helper.dart' if (dart.library.html) 'file_download_helper_web.dart' as download_helper;

class FileManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String seatId;
  const FileManagerTab({super.key, required this.terminalId, required this.seatId});

  @override
  ConsumerState<FileManagerTab> createState() => _FileManagerTabState();
}

class _FileManagerTabState extends ConsumerState<FileManagerTab> {
  String _currentPath = '';
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedFileId;
  List<TerminalFile> _files = [];
  bool _loading = false;
  String? _error;
  String? _downloadingFile; // 正在下载的文件路径

  final List<String> _history = [];
  int _historyIndex = -1;

  bool _computerExpanded = true;
  final Set<String> _expandedTreePaths = <String>{};
  final Map<String, List<_TreeNode>> _treeChildren = <String, List<_TreeNode>>{};
  final Set<String> _treeLoading = <String>{};

  // 动态磁盘列表
  List<TerminalFile> _drives = [];
  bool _drivesLoading = false;

  // 路径编辑模式
  bool _isEditingPath = false;
  final FocusNode _pathFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadDrives();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _searchController.dispose();
    _pathFocusNode.dispose();
    super.dispose();
  }

  /// 加载磁盘列表
  Future<void> _loadDrives() async {
    setState(() {
      _drivesLoading = true;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      final drives = await api.getFiles(widget.seatId, '', domain: domain);
      if (mounted) {
        setState(() {
          _drives = drives;
          _drivesLoading = false;
        });
        // 如果有磁盘，自动进入第一个磁盘
        if (drives.isNotEmpty) {
          final firstDrive = drives.first.path;
          _navigateTo(firstDrive);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _drivesLoading = false;
          _error = '获取磁盘列表失败: $e';
        });
      }
    }
  }

  Future<void> _loadFiles({required String path}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      debugPrint('[FileManager] Loading files: seatId=${widget.seatId}, path="$path", domain=$domain');
      final list = await api.getFiles(widget.seatId, path, domain: domain);
      debugPrint('[FileManager] Loaded ${list.length} files');
      if (mounted) {
        setState(() {
          _files = list;
          _loading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('[FileManager] Error loading files: $e');
      debugPrint('[FileManager] Stack: $stack');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<_TreeNode> get _driveNodes => _drives
      .map((d) => _TreeNode(
            label: '本地磁盘 (${d.name})',
            path: _normalizePath(d.path),
            kind: _TreeNodeKind.drive,
          ))
      .toList();

  /// 规范化路径
  /// 磁盘根保持为 C: 格式（不带反斜杠）
  /// 子目录为 C:\Windows 格式
  String _normalizePath(String path) {
    var out = path.replaceAll('/', r'\').trim();
    if (out.isEmpty) return '';
    // 移除开头的反斜杠
    while (out.startsWith('\\')) {
      out = out.substring(1);
    }
    // 大写盘符
    if (out.length >= 2 && out[1] == ':') {
      out = out[0].toUpperCase() + out.substring(1);
    }
    // 移除末尾的反斜杠（磁盘根 C:\ 也要移除变成 C:）
    while (out.endsWith('\\')) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  /// 判断是否为磁盘根路径（如 C:）
  bool _isDriveRoot(String path) {
    return RegExp(r'^[A-Za-z]:$').hasMatch(path);
  }

  /// 拼接路径
  String _joinPath(String base, String name) {
    final b = _normalizePath(base);
    // C: + folder = C:\folder
    // C:\Windows + System32 = C:\Windows\System32
    return '$b\\$name';
  }

  /// 获取父路径
  String _parentPath(String path) {
    final p = _normalizePath(path);
    if (p.isEmpty) return '';
    // 磁盘根没有父路径
    if (_isDriveRoot(p)) return p;
    final idx = p.lastIndexOf(r'\');
    if (idx <= 2) return p.substring(0, 2); // 返回磁盘根 C:
    return p.substring(0, idx);
  }

  /// 获取面包屑路径列表
  List<String> get _breadcrumbs {
    if (_currentPath.isEmpty) return [];
    final parts = _currentPath.split(r'\').where((p) => p.isNotEmpty).toList();
    return parts;
  }

  bool get _canGoBack => _historyIndex > 0;
  bool get _canGoForward => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  Future<void> _navigateTo(String path, {bool pushHistory = true}) async {
    final next = _normalizePath(path);

    setState(() {
      _currentPath = next;
      _pathController.text = next;
      _selectedFileId = null;
    });

    if (pushHistory) {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(next);
      _historyIndex = _history.length - 1;
    }

    await _loadFiles(path: next);
  }

  Future<void> _goBack() async {
    if (!_canGoBack) return;
    _historyIndex -= 1;
    await _navigateTo(_history[_historyIndex], pushHistory: false);
  }

  Future<void> _goForward() async {
    if (!_canGoForward) return;
    _historyIndex += 1;
    await _navigateTo(_history[_historyIndex], pushHistory: false);
  }

  Future<void> _navigateUp() async {
    final parent = _parentPath(_currentPath);
    if (parent.isNotEmpty && parent != _currentPath) {
      await _navigateTo(parent);
    }
  }

  Future<void> _openFolder(String name) async {
    await _navigateTo(_joinPath(_currentPath, name));
  }

  /// 点击面包屑导航
  Future<void> _navigateToBreadcrumb(int index) async {
    final parts = _breadcrumbs;
    if (index < 0 || index >= parts.length) return;
    // 构建路径
    final drive = parts[0]; // 如 "C:"
    if (index == 0) {
      // 点击盘符，导航到磁盘根
      await _navigateTo(drive);
    } else {
      // 点击子目录
      final pathParts = parts.sublist(0, index + 1);
      await _navigateTo('${pathParts[0]}\\${pathParts.sublist(1).join('\\')}');
    }
  }

  List<TerminalFile> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;
    final q = _searchQuery.toLowerCase();
    return _files.where((f) => f.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _ensureTreeChildren(String path) async {
    final p = _normalizePath(path);
    if (_treeChildren.containsKey(p) || _treeLoading.contains(p)) return;
    _treeLoading.add(p);
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      final items = await api.getFiles(widget.seatId, p, domain: domain);
      final dirs = items.where((f) => f.isDirectory).toList();
      final children = dirs
          .map(
            (d) => _TreeNode(
              label: d.name,
              path: _joinPath(p, d.name),
              kind: _TreeNodeKind.folder,
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _treeChildren[p] = children;
      });
    } catch (_) {
      // ignore tree errors; file list already shows errors
    } finally {
      _treeLoading.remove(p);
    }
  }

  /// 下载文件
  Future<void> _downloadFile(TerminalFile file) async {
    if (file.isDirectory || _downloadingFile == file.path) return;

    setState(() {
      _downloadingFile = file.path;
    });

    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      final bytes = await api.downloadFile(widget.seatId, file.path, domain: domain);

      // 使用平台相关的下载方法
      await download_helper.downloadFile(bytes, file.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载: ${file.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('下载失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingFile = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow || context.isPhone;

    if (_drivesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildTopBar(isNarrow: isNarrow),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '加载失败: $_error',
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _loadFiles(path: _currentPath),
                            icon: const Icon(LucideIcons.refreshCw, size: 16),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : isNarrow
                      ? _buildFileListNarrow()
                      : _buildFileManagerWide(),
        ),
      ],
    );
  }

  Widget _buildTopBar({required bool isNarrow}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          // 导航按钮 + 路径栏（面包屑/编辑框）+ 搜索框
          Row(
            children: [
              if (!isNarrow) ...[
                _buildNavIcon(
                  LucideIcons.arrowLeft,
                  tooltip: '后退',
                  enabled: _canGoBack,
                  onTap: _goBack,
                ),
                const SizedBox(width: 6),
                _buildNavIcon(
                  LucideIcons.arrowRight,
                  tooltip: '前进',
                  enabled: _canGoForward,
                  onTap: _goForward,
                ),
                const SizedBox(width: 6),
              ],
              _buildNavIcon(
                LucideIcons.arrowUp,
                tooltip: '上一级',
                enabled: _currentPath.isNotEmpty && !_isDriveRoot(_currentPath),
                onTap: _navigateUp,
              ),
              const SizedBox(width: 6),
              _buildNavIcon(
                LucideIcons.refreshCw,
                tooltip: '刷新',
                enabled: true,
                onTap: () => _loadFiles(path: _currentPath),
              ),
              const SizedBox(width: 10),
              // 合并的路径栏（面包屑 / 编辑模式）
              Expanded(child: _buildPathBar()),
              if (!isNarrow) ...[
                const SizedBox(width: 10),
                SizedBox(width: 200, height: 34, child: _buildSearchField()),
              ],
            ],
          ),
          // 移动端搜索框
          if (isNarrow) ...[
            const SizedBox(height: 8),
            SizedBox(height: 36, child: _buildSearchField()),
          ],
        ],
      ),
    );
  }

  /// 进入路径编辑模式
  void _enterEditMode() {
    setState(() {
      _isEditingPath = true;
      _pathController.text = _currentPath;
    });
    // 延迟聚焦并选中全部文本
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pathFocusNode.requestFocus();
      _pathController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _pathController.text.length,
      );
    });
  }

  /// 退出路径编辑模式
  void _exitEditMode() {
    setState(() => _isEditingPath = false);
  }

  /// 提交路径编辑
  void _submitPathEdit() {
    final path = _pathController.text.trim();
    _exitEditMode();
    if (path.isNotEmpty && path != _currentPath) {
      _navigateTo(path);
    }
  }

  /// 构建路径栏（面包屑 / 编辑模式切换）
  Widget _buildPathBar() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: _isEditingPath ? _buildPathEditField() : _buildBreadcrumbContent(),
    );
  }

  /// 构建路径编辑输入框
  Widget _buildPathEditField() {
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(LucideIcons.folderOpen, size: 14, color: Colors.grey.shade600),
        ),
        Expanded(
          child: Focus(
            onFocusChange: (hasFocus) {
              // 失去焦点时取消编辑
              if (!hasFocus && _isEditingPath) {
                _exitEditMode();
              }
            },
            child: KeyboardListener(
              focusNode: FocusNode(),
              onKeyEvent: (event) {
                // 按 ESC 取消编辑
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _exitEditMode();
                }
              },
              child: TextField(
                controller: _pathController,
                focusNode: _pathFocusNode,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
                onSubmitted: (_) => _submitPathEdit(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// 构建面包屑内容（支持双击编辑）
  Widget _buildBreadcrumbContent() {
    final parts = _breadcrumbs;
    return GestureDetector(
      onDoubleTap: _enterEditMode,
      child: Row(
        children: [
          const SizedBox(width: 6),
          // 此电脑图标
          InkWell(
            onTap: _loadDrives,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(LucideIcons.monitor, size: 14, color: Colors.grey.shade600),
            ),
          ),
          // 面包屑路径
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: parts.isEmpty
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '此电脑',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      ]
                    : parts.asMap().entries.expand((entry) {
                        final index = entry.key;
                        final part = entry.value;
                        final isLast = index == parts.length - 1;
                        return [
                          Icon(LucideIcons.chevronRight, size: 14, color: Colors.grey.shade400),
                          InkWell(
                            onTap: isLast ? null : () => _navigateToBreadcrumb(index),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              child: Text(
                                part,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isLast ? Colors.grey.shade900 : Colors.grey.shade600,
                                  fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ];
                      }).toList(),
              ),
            ),
          ),
          // 编辑图标提示
          Tooltip(
            message: '双击编辑路径',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(LucideIcons.edit3, size: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(
    IconData icon, {
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? Colors.grey.shade700 : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _searchQuery = v.trim()),
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
        prefixIcon: Icon(
          LucideIcons.search,
          size: 16,
          color: Colors.grey.shade400,
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : InkWell(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
              ),
        hintText: '搜索...',
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.iosBlue),
        ),
      ),
    );
  }

  Widget _buildFileManagerWide() {
    return Container(
      color: const Color(0xFFF3F4F6),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(width: 260, child: _buildTreePanel()),
          const SizedBox(width: 12),
          Expanded(child: _buildTablePanel()),
        ],
      ),
    );
  }

  Widget _buildFileListNarrow() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _filteredFiles.length,
            padding: const EdgeInsets.all(8),
            itemBuilder: (context, index) {
              final file = _filteredFiles[index];
              final isSelected = _selectedFileId == file.path;
              return _buildFileTile(file, isSelected);
            },
          ),
        ),
        _buildStatusBar(),
      ],
    );
  }

  Widget _buildTreePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(LucideIcons.monitor, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                const Text(
                  '此电脑',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _buildTreeComputer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeComputer() {
    return ExpansionTile(
      initiallyExpanded: _computerExpanded,
      onExpansionChanged: (v) => setState(() => _computerExpanded = v),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Icon(LucideIcons.monitor, size: 16, color: Colors.grey.shade600),
      title: const Text('此电脑', style: TextStyle(fontSize: 13)),
      childrenPadding: const EdgeInsets.only(left: 12),
      children: _driveNodes.map(_buildTreeNode).toList(),
    );
  }

  Widget _buildTreeNode(_TreeNode node) {
    final selected = _normalizePath(_currentPath) == _normalizePath(node.path);
    final canExpand = node.kind != _TreeNodeKind.file;
    final expanded = _expandedTreePaths.contains(node.path);

    final children = _treeChildren[node.path] ?? const [];
    final loading = _treeLoading.contains(node.path);

    return Column(
      children: [
        InkWell(
          onTap: () async {
            await _navigateTo(node.path);
            if (!canExpand) return;
            final next = !expanded;
            setState(() {
              if (next) {
                _expandedTreePaths.add(node.path);
              } else {
                _expandedTreePaths.remove(node.path);
              }
            });
            if (next) await _ensureTreeChildren(node.path);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: selected ? Colors.blue.withOpacity(0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  node.kind == _TreeNodeKind.drive
                      ? LucideIcons.hardDrive
                      : LucideIcons.folder,
                  size: 16,
                  color: node.kind == _TreeNodeKind.drive
                      ? Colors.grey.shade700
                      : Colors.amber.shade700,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? AppColors.iosBlue : Colors.grey.shade800,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (canExpand)
                  Icon(
                    expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: children.map(_buildTreeNode).toList(),
                  ),
          ),
      ],
    );
  }

  Widget _buildTablePanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildFileListHeader(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              itemCount: _filteredFiles.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (context, index) {
                final file = _filteredFiles[index];
                final isSelected = _selectedFileId == file.path;
                return _buildFileListItem(file, isSelected);
              },
            ),
          ),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildFileTile(TerminalFile file, bool isSelected) {
    final ext = file.name.split('.').last.toLowerCase();
    IconData icon;
    Color iconColor;
    if (file.isDirectory) {
      icon = LucideIcons.folder;
      iconColor = Colors.amber;
    } else if (['docx', 'txt'].contains(ext)) {
      icon = LucideIcons.fileText;
      iconColor = Colors.blue;
    } else if (['png', 'jpg', 'jpeg'].contains(ext)) {
      icon = LucideIcons.image;
      iconColor = Colors.purple;
    } else if (ext == 'exe') {
      icon = LucideIcons.appWindow;
      iconColor = Colors.grey.shade600;
    } else {
      icon = LucideIcons.file;
      iconColor = Colors.grey.shade400;
    }

    final subtitle = file.isDirectory
        ? '文件夹'
        : '${file.updatedAt} · ${_formatSize(file.size)} · ${_typeLabel(file)}';

    final isDownloading = _downloadingFile == file.path;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Icon(icon, size: 20, color: iconColor),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: file.isDirectory
          ? null
          : IconButton(
              icon: isDownloading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.grey.shade500,
                      ),
                    )
                  : Icon(LucideIcons.download, size: 18, color: Colors.grey.shade600),
              onPressed: isDownloading ? null : () => _downloadFile(file),
              tooltip: '下载',
            ),
      selected: isSelected,
      selectedTileColor: Colors.blue.withOpacity(0.06),
      onTap: () {
        if (file.isDirectory) {
          _openFolder(file.name);
          return;
        }
        setState(() => _selectedFileId = file.path);
      },
      onLongPress: () {
        if (file.isDirectory) _openFolder(file.name);
      },
    );
  }

  Widget _buildFileListHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildHeaderCell('名称')),
          SizedBox(width: 120, child: _buildHeaderCell('修改日期')),
          SizedBox(width: 80, child: _buildHeaderCell('类型')),
          SizedBox(width: 100, child: _buildHeaderCell('版本')),
          SizedBox(width: 80, child: _buildHeaderCell('大小', textAlign: TextAlign.right)),
          const SizedBox(width: 60), // 操作列
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {TextAlign textAlign = TextAlign.left}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w600,
      ),
      textAlign: textAlign,
    );
  }

  Widget _buildFileListItem(TerminalFile file, bool isSelected) {
    final isDownloading = _downloadingFile == file.path;

    return GestureDetector(
      onTap: () => setState(() => _selectedFileId = file.path),
      onDoubleTap: () {
        if (file.isDirectory) {
          _openFolder(file.name);
        }
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _buildFileLeadingIcon(file),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                file.updatedAt,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _typeLabel(file),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
            SizedBox(
              width: 100,
              child: Text(
                file.version,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                file.isDirectory ? '' : _formatSize(file.size),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 60,
              child: file.isDirectory
                  ? const SizedBox()
                  : IconButton(
                      icon: isDownloading
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.grey.shade500,
                              ),
                            )
                          : Icon(
                              LucideIcons.download,
                              size: 16,
                              color: AppColors.iosBlue,
                            ),
                      onPressed: isDownloading ? null : () => _downloadFile(file),
                      tooltip: '下载',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            '${_filteredFiles.length} 个项目',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 16),
          if (_selectedFileId != null)
            Text(
              '选中 1 个项目',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }

  Widget _buildFileLeadingIcon(TerminalFile file) {
    final name = file.name.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : '';
    if (file.isDirectory) {
      return Icon(LucideIcons.folder, size: 18, color: Colors.amber.shade700);
    }
    if (ext == 'exe') {
      return Container(
        width: 26,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          'EXE',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
      );
    }
    if (['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
      return const Icon(LucideIcons.image, size: 18, color: Color(0xFF8B5CF6));
    }
    if (['doc', 'docx', 'txt', 'md', 'log'].contains(ext)) {
      return const Icon(LucideIcons.fileText, size: 18, color: Color(0xFF3B82F6));
    }
    if (['xlsx', 'xls', 'csv'].contains(ext)) {
      return const Icon(LucideIcons.fileSpreadsheet, size: 18, color: Color(0xFF16A34A));
    }
    if (['zip', 'rar', '7z'].contains(ext)) {
      return const Icon(LucideIcons.archive, size: 18, color: Color(0xFFF59E0B));
    }
    return Icon(LucideIcons.file, size: 18, color: Colors.grey.shade500);
  }

  String _typeLabel(TerminalFile file) {
    if (file.isDirectory) return '文件夹';
    final name = file.name;
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : '';
    if (ext.isEmpty) return '文件';
    return '$ext 文件';
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const k = 1024.0;
    final kb = bytes / k;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

enum _TreeNodeKind { drive, folder, file }

class _TreeNode {
  final String label;
  final String path;
  final _TreeNodeKind kind;

  const _TreeNode({
    required this.label,
    required this.path,
    required this.kind,
  });
}
