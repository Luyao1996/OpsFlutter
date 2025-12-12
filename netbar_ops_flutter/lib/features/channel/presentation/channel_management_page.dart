import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/permission_provider.dart';
import '../data/channel_api.dart';
import '../data/channel_models.dart';

// Providers for state
final currentZoneProvider = StateProvider<String>((ref) => 'PUBLIC');
final activeModuleProvider = StateProvider<String>((ref) => 'FILES');
final currentFolderIdProvider = StateProvider<int?>((ref) => null);

// Data providers
final channelResourcesProvider = FutureProvider.autoDispose<List<ChannelFile>>((ref) async {
  final api = ref.watch(channelApiProvider);
  final zone = ref.watch(currentZoneProvider);
  final folderId = ref.watch(currentFolderIdProvider);
  final netbar = ref.watch(currentNetbarProvider);
  
  // Logic to determine effective netbar_id
  int? netbarId = netbar.id;
  // HEADQUARTERS and BRANCH usually don't need specific netbar_id for resource listing unless scoped
  if (zone == 'HEADQUARTERS' || zone == 'BRANCH') netbarId = null;

  return api.getResources(zone: zone, parentId: folderId, netbarId: netbarId);
});

final channelStartupItemsProvider = FutureProvider.autoDispose<List<StartupItem>>((ref) async {
  final api = ref.watch(channelApiProvider);
  final zone = ref.watch(currentZoneProvider);
  final netbar = ref.watch(currentNetbarProvider);
  
  int? netbarId = netbar.id;
  if (zone == 'HEADQUARTERS' || zone == 'BRANCH') netbarId = null;

  return api.getStartupItems(zone: zone, netbarId: netbarId);
});

class ChannelManagementPage extends ConsumerStatefulWidget {
  const ChannelManagementPage({super.key});

  @override
  ConsumerState<ChannelManagementPage> createState() => _ChannelManagementPageState();
}

class _ChannelManagementPageState extends ConsumerState<ChannelManagementPage> {
  Set<int> _selectedStartupIds = {};
  Set<int> _selectedFileIds = {};
  List<ChannelFile> _folderPath = [];

  int get selectionCount => ref.read(activeModuleProvider) == 'FILES' 
      ? _selectedFileIds.length 
      : _selectedStartupIds.length;

  void clearSelection() {
    setState(() {
      _selectedFileIds.clear();
      _selectedStartupIds.clear();
    });
  }

  bool _canEdit({bool showWarning = true}) {
    final zone = ref.read(currentZoneProvider);
    final netbarId = ref.read(currentNetbarProvider).id;
    final perm = ref.read(permissionProvider);
    final allowed = perm.canEditZone(zone, netbarId: netbarId);
    if (!allowed && mounted && showWarning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前来源不可编辑，需管理员/分公司或选择网吧')),
      );
    }
    return allowed;
  }

  Future<void> _uploadFile() async {
    if (!_canEdit()) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      final api = ref.read(channelApiProvider);
      final zone = ref.read(currentZoneProvider);
      final parentId = ref.read(currentFolderIdProvider);
      final netbar = ref.read(currentNetbarProvider);
      
      int? netbarId = netbar.id;
      if (zone == 'HEADQUARTERS' || zone == 'BRANCH') netbarId = null;

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开始上传...')));

      for (var file in result.files) {
        if (file.path != null) {
          try {
            await api.uploadResource(
              file: File(file.path!),
              zone: zone,
              parentId: parentId,
              netbarId: netbarId
            );
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: ${file.name}')));
          }
        }
      }
      ref.invalidate(channelResourcesProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传完成')));
    }
  }

  void _showContextMenu(TapDownDetails details, dynamic item) {
    final isFile = item is ChannelFile;
    final position = RelativeRect.fromLTRB(
      details.globalPosition.dx,
      details.globalPosition.dy,
      details.globalPosition.dx,
      details.globalPosition.dy,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: [
        if (isFile) ...[
          const PopupMenuItem(value: 'open', child: Row(children: [Icon(LucideIcons.folderOpen, size: 16), SizedBox(width: 8), Text('打开')])),
          const PopupMenuItem(value: 'rename', child: Row(children: [Icon(LucideIcons.edit3, size: 16), SizedBox(width: 8), Text('重命名')])),
        ] else ...[
          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(LucideIcons.settings, size: 16), SizedBox(width: 8), Text('编辑')])),
          const PopupMenuItem(value: 'toggle', child: Row(children: [Icon(LucideIcons.power, size: 16), SizedBox(width: 8), Text('切换状态')])),
        ],
        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(LucideIcons.trash2, size: 16, color: Colors.red), SizedBox(width: 8), Text('删除', style: TextStyle(color: Colors.red))])),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deleteItem(item);
      } else if (value == 'open' && isFile) {
        if (item.isDirectory) {
          setState(() {
            _folderPath.add(item);
            ref.read(currentFolderIdProvider.notifier).state = item.id;
            _selectedFileIds.clear();
          });
        }
      }
    });
  }

  Future<void> _deleteItem(dynamic item) async {
    if (!_canEdit()) return;
    final api = ref.read(channelApiProvider);
    try {
      if (item is ChannelFile) {
        await api.deleteResource(item.id);
        ref.invalidate(channelResourcesProvider);
      } else if (item is StartupItem) {
        await api.deleteStartupItem(item.id);
        ref.invalidate(channelStartupItemsProvider);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebarHeader(),
                _buildSidebarItem('PUBLIC', '本网吧资源', LucideIcons.globe),
                _buildSidebarItem('BRANCH', '分公司资源', LucideIcons.building2),
                _buildSidebarItem('HEADQUARTERS', '总部资源', LucideIcons.shieldAlert),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text('资源来源', style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _buildSidebarItem(String zone, String label, IconData icon) {
    final current = ref.watch(currentZoneProvider);
    final isSelected = current == zone;
    final perm = ref.watch(permissionProvider);
    final editable = perm.canEditZone(zone, netbarId: ref.read(currentNetbarProvider).id);
    return InkWell(
      onTap: () {
        ref.read(currentZoneProvider.notifier).state = zone;
        ref.read(currentFolderIdProvider.notifier).state = null;
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.iosBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 12),
            Text(
              label + (editable ? '' : '（仅查看）'),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final module = ref.watch(activeModuleProvider);
    final count = selectionCount;
    final canEdit = _canEdit(showWarning: false);

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _buildModuleTab('FILES', '文件管理', LucideIcons.folderOpen),
              const SizedBox(width: 16),
              _buildModuleTab('STARTUP', '启动项', LucideIcons.zap),
            ],
          ),
          
          if (count > 0) 
            Row(
              children: [
                Text('已选 $count 项', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(width: 12),
                if (module == 'FILES') ...[
                  _buildActionButton('复制', LucideIcons.copy, Colors.blue, () {
                    _canEdit();
                  }, enabled: canEdit),
                   const SizedBox(width: 8),
                   _buildActionButton('剪切', LucideIcons.scissors, Colors.orange, () {
                    _canEdit();
                   }, enabled: canEdit),
                   const SizedBox(width: 8),
                   _buildActionButton('删除', LucideIcons.trash2, Colors.red, () {
                    _canEdit();
                   }, enabled: canEdit),
                ] else ...[
                   _buildActionButton('启用', LucideIcons.power, Colors.green, () {
                    _canEdit();
                   }, enabled: canEdit),
                   const SizedBox(width: 8),
                   _buildActionButton('禁用', LucideIcons.powerOff, Colors.grey, () {
                    _canEdit();
                   }, enabled: canEdit),
                   const SizedBox(width: 8),
                   _buildActionButton('删除', LucideIcons.trash2, Colors.red, () {
                    _canEdit();
                   }, enabled: canEdit),
                ],
                const SizedBox(width: 12),
                IconButton(icon: const Icon(LucideIcons.x), onPressed: clearSelection),
              ]
            )
          else
            Row(
              children: [
                IconButton(icon: const Icon(LucideIcons.refreshCw), onPressed: () {
                  ref.invalidate(channelResourcesProvider);
                  ref.invalidate(channelStartupItemsProvider);
                }),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: canEdit ? _uploadFile : null,
                  icon: const Icon(LucideIcons.upload, size: 16),
                  label: const Text('上传'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.iosBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, MaterialColor color, VoidCallback onTap, {bool enabled = true}) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: enabled ? color.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: enabled ? color.shade700 : Colors.grey.shade400),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: enabled ? color.shade700 : Colors.grey.shade400, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleTab(String module, String label, IconData icon) {
    final current = ref.watch(activeModuleProvider);
    final isSelected = current == module;
    return InkWell(
      onTap: () => ref.read(activeModuleProvider.notifier).state = module,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.black87 : Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.black87 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final module = ref.watch(activeModuleProvider);
    if (module == 'FILES') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumbs(),
          Expanded(child: _buildFileBrowser()),
        ],
      );
    } else {
      return _buildStartupList();
    }
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      color: Colors.grey.shade50,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _folderPath.clear();
                  ref.read(currentFolderIdProvider.notifier).state = null;
                });
              },
              child: const Text('根目录', style: TextStyle(color: AppColors.iosBlue, fontWeight: FontWeight.w500)),
            ),
            for (var i = 0; i < _folderPath.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(LucideIcons.chevronRight, size: 14, color: Colors.grey),
              ),
              InkWell(
                onTap: () {
                  setState(() {
                    _folderPath = _folderPath.sublist(0, i + 1);
                    ref.read(currentFolderIdProvider.notifier).state = _folderPath.last.id;
                  });
                },
                child: Text(_folderPath[i].name, style: TextStyle(
                  color: i == _folderPath.length - 1 ? Colors.black87 : AppColors.iosBlue,
                  fontWeight: i == _folderPath.length - 1 ? FontWeight.bold : FontWeight.w500
                )),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildFileBrowser() {
    final resourcesAsync = ref.watch(channelResourcesProvider);
    return resourcesAsync.when(
      data: (files) => _buildFileList(files),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildFileList(List<ChannelFile> files) {
    if (files.isEmpty) return const Center(child: Text('暂无文件', style: TextStyle(color: Colors.grey)));
    
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        childAspectRatio: 0.8,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return _buildFileItem(file);
      },
    );
  }

  Widget _buildFileItem(ChannelFile file) {
    final isSelected = _selectedFileIds.contains(file.id);
    return InkWell(
      onTap: () {
        if (file.isDirectory) {
          setState(() {
            _folderPath.add(file);
            ref.read(currentFolderIdProvider.notifier).state = file.id;
            _selectedFileIds.clear();
          });
        } else {
          setState(() {
             if (_selectedFileIds.contains(file.id)) _selectedFileIds.remove(file.id);
             else _selectedFileIds.add(file.id);
          });
        }
      },
      onSecondaryTapDown: (details) => _showContextMenu(details, file),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? AppColors.iosBlue : Colors.grey.shade200, width: isSelected ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              file.isDirectory ? LucideIcons.folder : LucideIcons.file, 
              size: 48, 
              color: file.isDirectory ? Colors.amber.shade400 : Colors.blue.shade400
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                file.name, 
                maxLines: 2, 
                overflow: TextOverflow.ellipsis, 
                textAlign: TextAlign.center, 
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartupList() {
    final itemsAsync = ref.watch(channelStartupItemsProvider);
    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) return const Center(child: Text('暂无启动项', style: TextStyle(color: Colors.grey)));
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 400,
            mainAxisExtent: 180,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _buildStartupItemCard(items[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildStartupItemCard(StartupItem item) {
    final isSelected = _selectedStartupIds.contains(item.id);
    final isEnabled = item.enabled;
    final statusColor = isEnabled ? Colors.green : Colors.grey;
    final statusBgColor = isEnabled ? Colors.green.shade50 : Colors.grey.shade100;

    return InkWell(
      onTap: () {
        setState(() {
          if (_selectedStartupIds.contains(item.id)) {
            _selectedStartupIds.remove(item.id);
          } else {
            _selectedStartupIds.add(item.id);
          }
        });
      },
      onSecondaryTapDown: (details) => _showContextMenu(details, item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.iosBlue : Colors.grey.shade200,
            width: isSelected ? 2 : 1
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
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
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(LucideIcons.zap, color: statusColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              item.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Switch.adaptive(
                            value: item.enabled,
                            activeColor: AppColors.iosBlue,
                            onChanged: (val) {
                              // TODO: Update item status via API
                            },
                          ),
                        ],
                      ),
                      Text(item.path, style: TextStyle(color: Colors.grey.shade500, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                if (item.delay != null && item.delay! > 0)
                  _buildTag(LucideIcons.clock, '${item.delay}s', Colors.orange),
                if (item.args != null && item.args!.isNotEmpty)
                  _buildTag(LucideIcons.terminal, '参数', Colors.blue),
                if (item.forceRun)
                  _buildTag(LucideIcons.alertCircle, '强制', Colors.red),
                if (item.targetOs != null)
                  _buildTag(LucideIcons.monitor, item.targetOs!, Colors.purple),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.updatedAt.split(' ')[0],
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                ),
                Row(
                  children: [
                    _buildIconButton(LucideIcons.settings, () {}),
                    const SizedBox(width: 4),
                    _buildIconButton(LucideIcons.play, () {}),
                    const SizedBox(width: 4),
                    _buildIconButton(LucideIcons.trash2, () {}, color: Colors.red),
                  ],
                ),
              ],
            ),
          ],
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
          Text(label, style: TextStyle(fontSize: 10, color: color.shade700, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, {Color color = Colors.grey}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: color == Colors.red ? Colors.red.shade400 : Colors.grey.shade400),
      ),
    );
  }
}
