import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/resource_api.dart' as res;

class ExeZoneOption {
  final String label;
  final String zone;
  final int? netbarId;

  const ExeZoneOption({
    required this.label,
    required this.zone,
    required this.netbarId,
  });
}

class _ExeSearchHit {
  final res.Resource resource;
  final String zone;
  final String zoneLabel;

  const _ExeSearchHit({
    required this.resource,
    required this.zone,
    required this.zoneLabel,
  });
}

class ExePickerDialog extends StatefulWidget {
  final List<ExeZoneOption> visibleZones;
  /// 是否只显示 .exe 文件，false 时显示所有文件
  final bool exeOnly;

  const ExePickerDialog({
    super.key,
    required this.visibleZones,
    this.exeOnly = true,
  });

  @override
  State<ExePickerDialog> createState() => _ExePickerDialogState();
}

class _ExePickerDialogState extends State<ExePickerDialog> {
  final res.ResourceApi _resourceApi = res.ResourceApi();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounce;
  bool _searching = false;
  List<_ExeSearchHit> _searchResults = [];

  final Map<String, List<res.Resource>> _childrenCache = {};
  final Set<String> _loadingKeys = {};
  final Set<String> _expandedKeys = {};

  // 存储每个资源的完整路径 (资源ID -> 完整路径)
  final Map<int, String> _fullPathCache = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final keyword = _searchController.text.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (keyword.isEmpty) {
        setState(() {
          _searchResults = [];
          _searching = false;
        });
      } else {
        _performSearch(keyword);
      }
    });
  }

  bool _matchFile(res.Resource r) {
    if (r.isDirectory) return false;
    if (widget.exeOnly) return r.name.toLowerCase().endsWith('.exe');
    return true;
  }

  String _cacheKey(String zone, int? netbarId, int? parentId) {
    return '$zone:${netbarId ?? 'null'}:${parentId ?? 'root'}';
  }

  Future<void> _loadChildren(ExeZoneOption option, int? parentId) async {
    final key = _cacheKey(option.zone, option.netbarId, parentId);
    if (_childrenCache.containsKey(key) || _loadingKeys.contains(key)) return;
    setState(() => _loadingKeys.add(key));
    try {
      final raw = await _resourceApi.getAll(
        zone: option.zone,
        netbarId: option.netbarId,
        parentId: parentId,
      );
      final filtered = _filterAndSort(raw);
      if (mounted) {
        setState(() => _childrenCache[key] = filtered);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _childrenCache[key] = const []);
      }
    } finally {
      if (mounted) setState(() => _loadingKeys.remove(key));
    }
  }

  List<res.Resource> _filterAndSort(List<res.Resource> items) {
    final dirs = items.where((e) => e.isDirectory).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = items.where(_matchFile).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...dirs, ...files];
  }

  Future<void> _performSearch(String keyword) async {
    setState(() {
      _searching = true;
      _searchResults = [];
    });
    try {
      final futures = widget.visibleZones.map((z) async {
        final list = await _resourceApi.search(
          keyword: keyword,
          zone: z.zone,
          netbarId: z.netbarId,
        );
        return MapEntry(z, list);
      }).toList();
      final entries = await Future.wait(futures);
      final byId = <int, _ExeSearchHit>{};
      for (final entry in entries) {
        final option = entry.key;
        for (final r in entry.value) {
          if (_matchFile(r)) {
            byId.putIfAbsent(
              r.id,
              () => _ExeSearchHit(
                resource: r,
                zone: option.zone,
                zoneLabel: option.label,
              ),
            );
          }
        }
      }
      final combined = byId.values.toList()
        ..sort((a, b) => a.resource.name.toLowerCase().compareTo(b.resource.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _searchResults = combined;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _relativePath(res.Resource r) {
    var p = r.path.replaceAll('\\', '/');
    if (p.startsWith('/')) p = p.substring(1);
    final upper = p.toUpperCase();
    const prefixes = ['HEADQUARTERS/', 'BRANCH/', 'SHARED/', 'PUBLIC/'];
    for (final pre in prefixes) {
      if (upper.startsWith(pre)) {
        p = p.substring(pre.length);
        break;
      }
    }
    return p;
  }

  String _zoneShortLabel(String zone) {
    switch (zone.toUpperCase()) {
      case 'HEADQUARTERS':
        return '总公司资源';
      case 'BRANCH':
        return '分公司资源';
      case 'SHARED':
        return '共享区资源';
      case 'PUBLIC':
        return '本网吧资源';
      default:
        return zone;
    }
  }

  String _pathWithZone(res.Resource r, {String? zoneLabel}) {
    final label = zoneLabel ?? _zoneShortLabel(r.zone);
    final rel = _relativePath(r);
    if (rel.isEmpty) return label;
    return '$label / $rel';
  }

  Widget _buildSearchArea() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Text(widget.exeOnly ? '未找到可执行文件' : '未找到文件', style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
      itemBuilder: (context, index) {
        final hit = _searchResults[index];
        final r = hit.resource;
        return ListTile(
          dense: true,
          leading: Icon(LucideIcons.file, size: 18, color: AppColors.iosBlue),
          title: Text(r.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Text(_pathWithZone(r, zoneLabel: hit.zoneLabel), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(hit.zoneLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ),
          onTap: () => Navigator.of(context).pop(r),
        );
      },
    );
  }

  /// 构建文件的完整路径
  String _buildFullPath(String parentPath, String name) {
    if (parentPath.isEmpty) return name;
    if (parentPath.endsWith('/')) return '$parentPath$name';
    return '$parentPath/$name';
  }

  /// 创建带有完整路径的 Resource 副本
  res.Resource _resourceWithFullPath(res.Resource r, String fullPath) {
    return res.Resource(
      id: r.id,
      name: r.name,
      path: fullPath,
      type: r.type,
      isDirectory: r.isDirectory,
      parentId: r.parentId,
      size: r.size,
      zone: r.zone,
      uploader: r.uploader,
      isGlobal: r.isGlobal,
      content: r.content,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    );
  }

  Widget _buildExeTile(ExeZoneOption option, res.Resource exe, int depth, String parentPath) {
    final fullPath = _buildFullPath(parentPath, exe.name);
    _fullPathCache[exe.id] = fullPath;

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0 + 40, right: 8),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(LucideIcons.file, size: 16, color: AppColors.iosBlue),
        title: Text(exe.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text(fullPath, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        onTap: () => Navigator.of(context).pop(_resourceWithFullPath(exe, fullPath)),
      ),
    );
  }

  Widget _buildFolderTile(ExeZoneOption option, res.Resource folder, int depth, String parentPath) {
    final key = _cacheKey(option.zone, option.netbarId, folder.id);
    final isExpanded = _expandedKeys.contains(key);
    final isLoading = _loadingKeys.contains(key);
    final children = _childrenCache[key] ?? const [];

    // 当前文件夹的完整路径
    final currentPath = _buildFullPath(parentPath, folder.name);
    _fullPathCache[folder.id] = currentPath;

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: ExpansionTile(
        key: PageStorageKey(key),
        initiallyExpanded: isExpanded,
        leading: Icon(LucideIcons.folder, size: 18, color: Colors.amber.shade600),
        title: Text(folder.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedKeys.add(key);
            } else {
              _expandedKeys.remove(key);
            }
          });
          if (expanded) _loadChildren(option, folder.id);
        },
        children: [
          if (isLoading)
            Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 12.0 + 40, top: 6, bottom: 6),
              child: Row(
                children: const [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('加载中...', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          if (!isLoading && children.isEmpty)
            Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 12.0 + 40, top: 4, bottom: 8),
              child: Text(widget.exeOnly ? '暂无可执行文件' : '暂无文件', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
          for (final child in children)
            if (child.isDirectory)
              _buildFolderTile(option, child, depth + 1, currentPath)
            else
              _buildExeTile(option, child, depth + 1, currentPath),
        ],
      ),
    );
  }

  Widget _buildZoneTile(ExeZoneOption option) {
    final key = _cacheKey(option.zone, option.netbarId, null);
    final isExpanded = _expandedKeys.contains(key);
    final isLoading = _loadingKeys.contains(key);
    final children = _childrenCache[key] ?? const [];

    // zone 作为路径的根，如 /HEADQUARTERS 或 /BRANCH
    final zonePath = '/${option.zone}';

    return ExpansionTile(
      key: PageStorageKey(key),
      initiallyExpanded: isExpanded,
      leading: Icon(LucideIcons.layers, size: 18, color: Colors.grey.shade700),
      title: Text(option.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      onExpansionChanged: (expanded) {
        setState(() {
          if (expanded) {
            _expandedKeys.add(key);
          } else {
            _expandedKeys.remove(key);
          }
        });
        if (expanded) _loadChildren(option, null);
      },
      children: [
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 6, bottom: 6),
            child: Row(
              children: const [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('加载中...', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        if (!isLoading && children.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4, bottom: 8),
            child: Text(widget.exeOnly ? '暂无可执行文件' : '暂无文件', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
        for (final child in children)
          if (child.isDirectory)
            _buildFolderTile(option, child, 1, zonePath)
          else
            _buildExeTile(option, child, 1, zonePath),
      ],
    );
  }

  Widget _buildTreeArea() {
    return ListView(
      children: [
        for (final option in widget.visibleZones) _buildZoneTile(option),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSearchingMode = _searchController.text.trim().isNotEmpty;
    return ResponsiveDialogScaffold(
      title: widget.exeOnly ? '选择执行程序' : '选择文件',
      maxWidth: 720,
      maxHeight: 600,
      scrollableBody: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.exeOnly ? '搜索 exe 文件...' : '搜索文件...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
                  suffixIcon: isSearchingMode
                      ? IconButton(
                          icon: Icon(LucideIcons.x, size: 16, color: Colors.grey.shade400),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: isSearchingMode ? _buildSearchArea() : _buildTreeArea(),
          ),
        ],
      ),
    );
  }
}
