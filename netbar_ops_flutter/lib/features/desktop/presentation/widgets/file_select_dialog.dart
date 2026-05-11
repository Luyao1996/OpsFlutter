import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/desktop_api.dart';

/// 文件选择弹窗
class FileSelectDialog extends StatefulWidget {
  final int? initialFileId;
  final String? initialPath;
  final bool onlyFile;

  const FileSelectDialog({
    super.key,
    this.initialFileId,
    this.initialPath,
    this.onlyFile = false,
  });

  @override
  State<FileSelectDialog> createState() => _FileSelectDialogState();
}

class _FileSelectDialogState extends State<FileSelectDialog> {
  final FileApi _fileApi = FileApi();
  final TextEditingController _searchController = TextEditingController();

  List<ServerFile> _fileList = [];
  Map<int, List<ServerFile>> _childrenMap = {};
  Set<int> _expandedIds = {};
  List<_BreadcrumbItem> _pathStack = [_BreadcrumbItem(id: null, name: '根目录')];
  int? _currentParentId;
  ServerFile? _selected;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles({int? parentId, String? keyword}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final files = await _fileApi.getFiles(parentId: parentId, keyword: keyword);
      setState(() {
        if (parentId == null) {
          _fileList = files;
        } else {
          _childrenMap[parentId] = files;
        }
        _currentParentId = parentId;
        _selected = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<_FlatFileItem> get _flatList {
    final result = <_FlatFileItem>[];

    void walk(List<ServerFile> items, int level) {
      for (final item in items) {
        result.add(_FlatFileItem(file: item, level: level));
        if (item.isFolder && _expandedIds.contains(item.id)) {
          final children = _childrenMap[item.id] ?? [];
          walk(children, level + 1);
        }
      }
    }

    walk(_fileList, 0);
    return result;
  }

  Future<void> _toggleExpand(ServerFile file) async {
    if (!file.isFolder) return;

    if (_expandedIds.contains(file.id)) {
      setState(() => _expandedIds.remove(file.id));
      return;
    }

    // Load children if not loaded
    if (!_childrenMap.containsKey(file.id)) {
      await _loadFiles(parentId: file.id);
    }

    setState(() => _expandedIds.add(file.id));
  }

  void _selectFile(ServerFile file) {
    setState(() {
      if (_selected?.id == file.id) {
        _selected = null;
      } else {
        _selected = file;
      }
    });
  }

  void _handleRowTap(ServerFile file) {
    if (widget.onlyFile && file.isFolder) {
      _toggleExpand(file);
    } else {
      _selectFile(file);
    }
  }

  void _handleRowDoubleTap(ServerFile file) {
    if (file.isFolder && !widget.onlyFile) {
      _toggleExpand(file);
    }
  }

  void _handleBreadcrumbClick(int index) {
    if (index == _pathStack.length - 1) return;

    final target = _pathStack[index];
    setState(() {
      _pathStack = _pathStack.sublist(0, index + 1);
      // Keep only expanded items in path
      final idsInPath = _pathStack.map((c) => c.id).where((id) => id != null).toSet();
      _expandedIds.removeWhere((id) => !idsInPath.contains(id));
    });
  }

  void _handleSearch() {
    final keyword = _searchController.text.trim();
    _loadFiles(parentId: _currentParentId, keyword: keyword.isEmpty ? null : keyword);
  }

  void _confirm() {
    if (_selected == null) return;
    if (widget.onlyFile && _selected!.isFolder) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择具体文件，不能选择文件夹')),
      );
      return;
    }
    Navigator.pop(context, _selected);
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '选择文件',
      maxWidth: 680,
      maxHeight: 480,
      scrollableBody: false,
      bodyPadding: const EdgeInsets.all(16),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumb(),
          const SizedBox(height: 12),
          _buildSearchBar(),
          const SizedBox(height: 12),
          Expanded(child: _buildFileList()),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            ),
            child: const Text('取消'),
          ),
          const SizedBox(width: 60),
          ElevatedButton(
            onPressed: _selected != null ? _confirm : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _pathStack.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == _pathStack.length - 1;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                ),
              InkWell(
                onTap: isLast ? null : () => _handleBreadcrumbClick(index),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                      color: isLast ? const Color(0xFF303133) : const Color(0xFF606266),
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '文件名搜索',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
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
            onSubmitted: (_) => _handleSearch(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: ElevatedButton(
            onPressed: _handleSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              foregroundColor: Colors.grey.shade700,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: const Text('搜索', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  Widget _buildFileList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 36, color: Colors.red.shade300),
            const SizedBox(height: 8),
            Text('加载失败', style: TextStyle(color: Colors.red.shade600)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadFiles(parentId: _currentParentId),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final flatItems = _flatList;
    if (flatItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.folderOpen, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('暂无文件', style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDCE1EC)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F4FB),
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 3, child: Text('文件名', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                SizedBox(width: 80, child: Text('大小', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                SizedBox(width: 100, child: Text('版本', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                SizedBox(width: 140, child: Text('修改时间', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ],
            ),
          ),

          // Table body
          Expanded(
            child: ListView.builder(
              itemCount: flatItems.length,
              itemBuilder: (context, index) {
                final item = flatItems[index];
                final isSelected = _selected?.id == item.file.id;

                return InkWell(
                  onTap: () => _handleRowTap(item.file),
                  onDoubleTap: () => _handleRowDoubleTap(item.file),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFE9F3FF) : Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              SizedBox(width: item.level * 18.0),
                              if (item.file.isFolder)
                                InkWell(
                                  onTap: () => _toggleExpand(item.file),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(
                                      _expandedIds.contains(item.file.id)
                                          ? LucideIcons.minus
                                          : LucideIcons.plus,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 18),
                              const SizedBox(width: 4),
                              Icon(
                                item.file.isFolder ? LucideIcons.folder : LucideIcons.file,
                                size: 16,
                                color: item.file.isFolder ? Colors.amber : Colors.grey.shade600,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  item.file.name,
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(LucideIcons.check, size: 14, color: Colors.green.shade600),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            item.file.size ?? '',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: Text(
                            item.file.version ?? '',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: Text(
                            item.file.modified ?? '',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BreadcrumbItem {
  final int? id;
  final String name;

  _BreadcrumbItem({this.id, required this.name});
}

class _FlatFileItem {
  final ServerFile file;
  final int level;

  _FlatFileItem({required this.file, required this.level});
}
