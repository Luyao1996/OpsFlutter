import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

class FileManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  const FileManagerTab({super.key, required this.terminalId});

  @override
  ConsumerState<FileManagerTab> createState() => _FileManagerTabState();
}

class _FileManagerTabState extends ConsumerState<FileManagerTab> {
  String _currentPath = r'C:\';
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedFileId;
  List<TerminalFile> _files = [];
  bool _loading = false;
  String? _error;

  final List<String> _history = [];
  int _historyIndex = -1;

  bool _computerExpanded = true;
  final Set<String> _expandedTreePaths = <String>{};
  final Map<String, List<_TreeNode>> _treeChildren = <String, List<_TreeNode>>{};
  final Set<String> _treeLoading = <String>{};

  @override
  void initState() {
    super.initState();
    _currentPath = _normalizePath(_currentPath);
    _pathController.text = _currentPath;
    _history.add(_currentPath);
    _historyIndex = 0;
    _loadFiles(path: _currentPath);
  }

  @override
  void dispose() {
    _pathController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles({required String path}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final list = await api.getFiles(widget.terminalId, path);
      if (mounted) {
        setState(() {
          _files = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<_TreeNode> get _driveNodes => const [
        _TreeNode(label: '本地磁盘 (C:)', path: r'C:\', kind: _TreeNodeKind.drive),
        _TreeNode(label: '本地磁盘 (D:)', path: r'D:\', kind: _TreeNodeKind.drive),
      ];

  String _normalizePath(String path) {
    var out = path.replaceAll('/', r'\').trim();
    if (out.isEmpty) return r'C:\';
    if (RegExp(r'^[A-Za-z]:$').hasMatch(out)) out = '$out\\';
    if (out.length >= 2 && out[1] == ':') {
      out = out[0].toUpperCase() + out.substring(1);
    }
    while (out.endsWith('\\') && out.length > 3) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  String _joinPath(String base, String name) {
    final b = _normalizePath(base);
    if (RegExp(r'^[A-Za-z]:\\$').hasMatch(b)) return '$b$name';
    return '$b\\$name';
  }

  String _parentPath(String path) {
    final p = _normalizePath(path);
    if (RegExp(r'^[A-Za-z]:\\$').hasMatch(p)) return p;
    final idx = p.lastIndexOf(r'\');
    if (idx <= 2) return '${p.substring(0, 2)}\\';
    return p.substring(0, idx);
  }

  bool get _canGoBack => _historyIndex > 0;
  bool get _canGoForward => _historyIndex >= 0 && _historyIndex < _history.length - 1;

  Future<void> _navigateTo(String path, {bool pushHistory = true}) async {
    final next = _normalizePath(path);
    if (next == _currentPath) return;

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
    await _navigateTo(_parentPath(_currentPath));
  }

  Future<void> _openFolder(String name) async {
    await _navigateTo(_joinPath(_currentPath, name));
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
      final items = await api.getFiles(widget.terminalId, p);
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

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow || context.isPhone;
    return Column(
      children: [
        _buildTopBar(isNarrow: isNarrow),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        '加载失败: $_error',
                        style: const TextStyle(color: Colors.red),
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
      child: isNarrow
          ? Column(
              children: [
                Row(
                  children: [
                    _buildNavIcon(
                      LucideIcons.arrowUp,
                      tooltip: '上一级',
                      enabled: true,
                      onTap: _navigateUp,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _buildAddressBar()),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(height: 36, child: _buildSearchField()),
              ],
            )
          : Row(
              children: [
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
                _buildNavIcon(
                  LucideIcons.arrowUp,
                  tooltip: '上一级',
                  enabled: true,
                  onTap: _navigateUp,
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildAddressBar()),
                const SizedBox(width: 10),
                SizedBox(width: 240, height: 34, child: _buildSearchField()),
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

  Widget _buildAddressBar() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.folderOpen, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _pathController,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (v) {
                final next = v.trim();
                if (next.isEmpty) return;
                _navigateTo(next);
              },
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _loadFiles(path: _currentPath),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
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
          SizedBox(width: 140, child: _buildHeaderCell('修改日期')),
          SizedBox(width: 80, child: _buildHeaderCell('类型')),
          SizedBox(width: 80, child: _buildHeaderCell('大小', textAlign: TextAlign.right)),
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
    final ext = file.name.split('.').last.toLowerCase();

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
              width: 140,
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
              width: 80,
              child: Text(
                file.isDirectory ? '' : _formatSize(file.size),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.right,
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
