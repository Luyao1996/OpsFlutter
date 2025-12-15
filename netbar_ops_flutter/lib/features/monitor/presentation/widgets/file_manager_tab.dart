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
  String _searchQuery = '';
  String? _selectedFileId;
  List<TerminalFile> _files = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final list = await api.getFiles(widget.terminalId, _currentPath);
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

  void _navigateUp() {
    // Simple Windows path navigation logic
    if (_currentPath.endsWith(r'\')) {
       _currentPath = _currentPath.substring(0, _currentPath.length - 1);
    }
    final lastSlash = _currentPath.lastIndexOf(r'\');
    if (lastSlash > 0) {
      setState(() {
        _currentPath = _currentPath.substring(0, lastSlash + 1); // Keep trailing slash if it's root drive
        if (_currentPath.endsWith(':')) _currentPath += r'\';
      });
      _loadFiles();
    } else if (_currentPath.length > 3) {
       // Handle C:\Users -> C:\
       setState(() => _currentPath = r'C:\');
       _loadFiles();
    }
  }

  void _openFolder(String name) {
    setState(() {
      if (!_currentPath.endsWith(r'\')) _currentPath += r'\';
      _currentPath += name;
    });
    _loadFiles();
  }

  List<TerminalFile> get _filteredFiles {
    if (_searchQuery.isEmpty) return _files;
    return _files.where((f) => f.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow || context.isPhone;
    return Column(
      children: [
        // Top Bar
        _buildTopBar(isNarrow: isNarrow),
        // Main Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('加载失败: $_error', style: const TextStyle(color: Colors.red)))
                  : _buildFileList(isNarrow: isNarrow),
        ),
      ],
    );
  }

  Widget _buildTopBar({required bool isNarrow}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: isNarrow
          ? Column(
              children: [
                Row(
                  children: [
                    _buildNavButton(LucideIcons.arrowUp, onPressed: _navigateUp),
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
                _buildNavButton(LucideIcons.arrowUp, onPressed: _navigateUp),
                const SizedBox(width: 12),
                // Address Bar
                Expanded(child: _buildAddressBar()),
                const SizedBox(width: 12),
                // Search Bar
                SizedBox(
                  width: 200,
                  height: 32,
                  child: _buildSearchField(),
                ),
              ],
            ),
    );
  }

  Widget _buildAddressBar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.monitor, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentPath,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _loadFiles,
            child: Icon(LucideIcons.refreshCw, size: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (v) => setState(() => _searchQuery = v),
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        prefixIcon: Icon(LucideIcons.search, size: 14, color: Colors.grey.shade400),
        hintText: '搜索...',
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.iosBlue),
        ),
      ),
    );
  }

  Widget _buildNavButton(IconData icon, {VoidCallback? onPressed}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed ?? () {},
        borderRadius: BorderRadius.circular(4),
        hoverColor: Colors.grey.shade200,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildFileList({required bool isNarrow}) {
    if (isNarrow) {
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

    return Column(
      children: [
        _buildFileListHeader(),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredFiles.length,
            padding: const EdgeInsets.all(4),
            itemBuilder: (context, index) {
              final file = _filteredFiles[index];
              final isSelected = _selectedFileId == file.path; // Assuming path is unique ID
              return _buildFileListItem(file, isSelected);
            },
          ),
        ),
        _buildStatusBar(),
      ],
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
        : '${file.updatedAt} · ${(file.size / 1024).toStringAsFixed(1)} KB · ${ext.toUpperCase()}';

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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
      textAlign: textAlign,
    );
  }

  Widget _buildFileListItem(TerminalFile file, bool isSelected) {
    IconData icon;
    Color iconColor;
    final ext = file.name.split('.').last.toLowerCase();

    if (file.isDirectory) {
      icon = LucideIcons.folder;
      iconColor = Colors.amber;
    } else if (['docx', 'txt'].contains(ext)) {
      icon = LucideIcons.fileText;
      iconColor = Colors.blue;
    } else if (['png', 'jpg', 'jpeg'].contains(ext)) {
      icon = LucideIcons.image;
      iconColor = Colors.purple;
    } else if (['exe'].contains(ext)) {
      icon = LucideIcons.appWindow;
      iconColor = Colors.grey.shade600;
    } else {
      icon = LucideIcons.file;
      iconColor = Colors.grey.shade400;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedFileId = file.path),
      onDoubleTap: () {
         if (file.isDirectory) {
            _openFolder(file.name);
         }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(icon, size: 18, color: iconColor),
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
                file.isDirectory ? '文件夹' : '${ext.toUpperCase()} 文件',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                file.isDirectory ? '' : '${(file.size / 1024).toStringAsFixed(1)} KB',
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text('${_filteredFiles.length} 个项目', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(width: 16),
          if (_selectedFileId != null)
             Text('选中 1 个项目', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
