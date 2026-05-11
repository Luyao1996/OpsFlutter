import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/icon_loader.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/netbar_tabs_provider.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/utils/top_notice.dart';
import '../../monitor/data/terminal_api.dart';
import '../data/desktop_api.dart';
import '../data/desktop_model.dart';
import 'widgets/desktop_toolbar.dart';
import 'widgets/icon_edit_dialog.dart';
import 'widgets/copy_layout_dialog.dart';

class DesktopManagementPageImpl extends ConsumerStatefulWidget {
  const DesktopManagementPageImpl({super.key});

  @override
  ConsumerState<DesktopManagementPageImpl> createState() => _DesktopManagementPageImplState();
}

class _DesktopManagementPageImplState extends ConsumerState<DesktopManagementPageImpl> {
  // APIs
  final DesktopApi _desktopApi = DesktopApi();
  final IconApi _iconApi = IconApi();
  final ScreenshotApi _screenshotApi = ScreenshotApi();

  // State
  bool _loading = true;
  String? _error;

  // Filters
  List<NetbarOption> _netbarOptions = []; // 用于复制布局时选择其他网吧
  List<SeatOption> _seatOptions = [];
  int? _selectedGroupId;
  int? _selectedNetbarId;
  String? _selectedNetbarDomain;
  String? _selectedSeatId;

  // Screenshot
  bool _screenshotLoading = false;
  Uint8List? _screenshotBytes;
  String? _screenshotUrl;
  String? _justScreenshotResolution;

  // Layout
  List<DesktopLayout> _layouts = [];
  List<String> _resolutionOptions = [];
  String? _currentResolution;
  List<DesktopIcon> _desktopIcons = [];
  DesktopLayout? _currentLayout;
  List<DesktopIcon>? _layoutBackup;

  // Icon interaction
  String? _activeIconId;
  String? _draggingId;
  Offset? _dragOffset;

  // 桌面画布的 key，用于坐标计算
  final GlobalKey _canvasKey = GlobalKey();

  // 拖拽位置通知器，用于优化性能
  final ValueNotifier<Offset?> _dragPositionNotifier = ValueNotifier(null);

  // User
  int? _currentUserGroupId;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _dragPositionNotifier.dispose();
    super.dispose();
  }

  /// 监听标签页变化
  void _setupTabListener() {
    ref.listen<NetbarTabsState>(netbarTabsProvider, (previous, next) {
      final prevTabId = previous?.activeTab?.id;
      final nextTabId = next.activeTab?.id;
      // 如果活动标签页变化了，重新加载数据
      if (prevTabId != nextTabId && nextTabId != null) {
        _onTabChanged(next.activeTab!);
      }
    });
  }

  void _onTabChanged(OpenedNetbarTab tab) {
    setState(() {
      _selectedNetbarId = tab.id;
      _selectedNetbarDomain = tab.subdomainFull;
      // 清空当前状态
      _layouts = [];
      _desktopIcons = [];
      _resolutionOptions = [];
      _currentResolution = null;
      _currentLayout = null;
      _screenshotBytes = null;
      _screenshotUrl = null;
      _justScreenshotResolution = null;
      _seatOptions = [];
      _selectedSeatId = null;
      _layoutBackup = null;
    });
    _loadLayouts();
    if (tab.id != null) {
      _loadSeats(tab.id!);
    }
  }

  Future<void> _initData() async {
    setState(() => _loading = true);

    try {
      // Get current user
      final user = TokenStore.getUser();
      _currentUserGroupId = user?['group_id'] as int?;

      // 从当前标签页获取网吧信息
      final tabsState = ref.read(netbarTabsProvider);
      final activeTab = tabsState.activeTab;
      if (activeTab != null) {
        _selectedNetbarId = activeTab.id;
        _selectedNetbarDomain = activeTab.subdomainFull;
      }

      // Load snapshots from localStorage (用于复制布局时选择其他网吧)
      await _loadSnapshots();

      // Load layouts
      await _loadLayouts();

      // 加载机号列表（走中央 HTTP /terminals）
      if (_selectedNetbarId != null) {
        await _loadSeats(_selectedNetbarId!);
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadSnapshots() async {
    // Load merchants snapshot (用于复制布局时选择其他网吧)
    final merchantsSnapshot = TokenStore.getString('merchants_snapshot');
    if (merchantsSnapshot != null) {
      try {
        final merchants = jsonDecode(merchantsSnapshot) as List;
        _netbarOptions = merchants.map((m) => NetbarOption(
          id: m['id'] as int?,
          name: (m['name'] ?? '网吧${m['id']}').toString().trim(),
          domain: m['subdomain_full']?.toString(),
        )).toList();
      } catch (_) {}
    }
  }

  Future<void> _loadLayouts() async {
    final params = <String, int>{};
    if (_currentUserGroupId == 0 && _selectedGroupId != null) {
      params['groupId'] = _selectedGroupId!;
    } else if (_currentUserGroupId != 0 && _currentUserGroupId != null) {
      params['groupId'] = _currentUserGroupId!;
    }
    if (_selectedNetbarId != null) {
      params['netbarId'] = _selectedNetbarId!;
    }

    final layouts = await _desktopApi.getLayouts(
      netbarId: params['netbarId'],
      groupId: params['groupId'],
    );

    _layouts = layouts;

    // Extract resolution options
    final resolutions = layouts
        .map((l) => l.resolution)
        .where((r) => r.isNotEmpty)
        .toSet()
        .toList();

    setState(() {
      _resolutionOptions = resolutions;
      if (resolutions.isNotEmpty) {
        if (_currentResolution == null || !resolutions.contains(_currentResolution)) {
          _currentResolution = resolutions.first;
        }
        _loadLayoutForResolution(_currentResolution!);
      } else {
        _currentResolution = null;
        _desktopIcons = [];
        _currentLayout = null;
      }
    });

    // Also load icons
    await _loadIcons();
  }

  Future<void> _loadIcons() async {
    try {
      final params = <String, int>{};
      if (_currentUserGroupId == 0 && _selectedGroupId != null) {
        params['groupId'] = _selectedGroupId!;
      } else if (_currentUserGroupId != 0 && _currentUserGroupId != null) {
        params['groupId'] = _currentUserGroupId!;
      }
      if (_selectedNetbarId != null) {
        params['netbarId'] = _selectedNetbarId!;
      }

      final icons = await _iconApi.getIcons(
        groupId: params['groupId'],
        netbarId: params['netbarId'],
      );

      // Merge with existing icons
      _mergeIcons(icons);
    } catch (e) {
      debugPrint('加载图标列表失败: $e');
    }
  }

  void _mergeIcons(List<DesktopIcon> newIcons) {
    final existingIds = _desktopIcons.map((i) => i.id).toSet();

    for (final newIcon in newIcons) {
      if (existingIds.contains(newIcon.id)) {
        // Update existing icon's config
        final idx = _desktopIcons.indexWhere((i) => i.id == newIcon.id);
        if (idx != -1) {
          final existing = _desktopIcons[idx];
          existing.config = newIcon.config;
          existing.iconUrl = newIcon.iconUrl ?? existing.iconUrl;
        }
      } else {
        // Add new icon with default position
        final index = _desktopIcons.length;
        final settings = _currentResolution != null
            ? ResolutionSettings.fromResolution(_currentResolution!)
            : const ResolutionSettings(width: 1920, height: 1080);
        final defaultPos = settings.getDefaultPosition(index);

        newIcon.positions[_currentResolution ?? '1920 x 1080'] = defaultPos;
        _desktopIcons.add(newIcon);
      }
    }

    setState(() {});
  }

  void _loadLayoutForResolution(String resolution, {bool isScreenshot = false}) {
    final layout = _layouts.firstWhere(
      (l) => l.resolution == resolution,
      orElse: () => DesktopLayout(
        name: '新布局',
        resolution: resolution,
        background: BackgroundConfig(),
        icons: [],
      ),
    );

    _currentLayout = layout;
    _desktopIcons = layout.icons.map((i) => i.copyWith()).toList();

    // Set background from layout if not screenshot
    if (!isScreenshot && layout.fileUrl != null && layout.fileUrl!.isNotEmpty) {
      _screenshotUrl = _desktopApi.getBackgroundUrl(layout.fileUrl);
      _screenshotBytes = null;
    } else if (!isScreenshot && _justScreenshotResolution != resolution) {
      _screenshotUrl = null;
      _screenshotBytes = null;
    }

    setState(() {});
  }

  Future<void> _loadSeats(int merchantId) async {
    try {
      final terminalApi = ref.read(terminalApiProvider);
      final terminals = await terminalApi.getAll(merchantId: merchantId);
      final seats = terminals
          .map((t) => SeatOption(
                id: t.seatId.isNotEmpty ? t.seatId : t.id.toString(),
                name: t.name.isNotEmpty
                    ? t.name
                    : (t.seatId.isNotEmpty ? t.seatId : '${t.id}号机'),
              ))
          .toList();
      setState(() => _seatOptions = seats);
    } catch (e) {
      debugPrint('加载机号列表失败: $e');
      setState(() => _seatOptions = []);
    }
  }

  void _onSeatChanged(String? seatId) {
    setState(() => _selectedSeatId = seatId);
  }

  Future<void> _onScreenshot() async {
    if (_selectedSeatId == null) {
      showTopNotice(context, '请先选择机号', level: NoticeLevel.warning);
      return;
    }

    if (_selectedNetbarDomain == null || _selectedNetbarDomain!.isEmpty) {
      showTopNotice(context, '网吧域名缺失，无法请求截图', level: NoticeLevel.error);
      return;
    }

    setState(() => _screenshotLoading = true);

    try {
      final result = await _screenshotApi.requestScreenshot(
        domain: _selectedNetbarDomain!,
        seatId: _selectedSeatId!,
      );

      if (!result.isSuccess) {
        showTopNotice(context, result.error ?? '截图失败', level: NoticeLevel.error);
        return;
      }

      // Handle different result types
      Uint8List? bytes;
      int? width, height;

      switch (result.type) {
        case ScreenshotResultType.bytes:
          bytes = result.bytes;
          // Get dimensions from image
          final dims = await _getImageDimensions(bytes!);
          width = dims.width.toInt();
          height = dims.height.toInt();
          break;
        case ScreenshotResultType.base64:
          bytes = base64Decode(result.base64Data!.replaceAll(RegExp(r'^data:[^;]+;base64,'), ''));
          width = result.width;
          height = result.height;
          if (width == null || height == null) {
            final dims = await _getImageDimensions(bytes);
            width = dims.width.toInt();
            height = dims.height.toInt();
          }
          break;
        case ScreenshotResultType.url:
          // For URL, we set the URL directly
          setState(() {
            _screenshotUrl = result.url;
            _screenshotBytes = null;
          });
          width = result.width;
          height = result.height;
          break;
        default:
          return;
      }

      if (bytes != null) {
        setState(() {
          _screenshotBytes = bytes;
          _screenshotUrl = null;
        });
      }

      // Add resolution if new
      if (width != null && height != null) {
        final newRes = '$width x $height';
        _handleNewResolution(newRes, width, height);
      }

      showTopNotice(context, '截图成功', level: NoticeLevel.success);
    } catch (e) {
      showTopNotice(context, '截图异常: $e', level: NoticeLevel.error);
    } finally {
      setState(() => _screenshotLoading = false);
    }
  }

  Future<ui.Size> _getImageDimensions(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
  }

  void _handleNewResolution(String resolution, int width, int height) {
    if (!_resolutionOptions.contains(resolution)) {
      _resolutionOptions.add(resolution);

      // Add default positions for all icons
      final settings = ResolutionSettings(
        width: width,
        height: height,
        columns: (width / 120).floor(),
      );

      for (var i = 0; i < _desktopIcons.length; i++) {
        if (!_desktopIcons[i].positions.containsKey(resolution)) {
          _desktopIcons[i].positions[resolution] = settings.getDefaultPosition(i);
        }
      }

      showTopNotice(context, '已添加新分辨率: $resolution', level: NoticeLevel.success);
    }

    setState(() {
      _currentResolution = resolution;
      _justScreenshotResolution = resolution;
    });
  }

  void _onResolutionChanged(String resolution) {
    setState(() => _currentResolution = resolution);
    _loadLayoutForResolution(resolution, isScreenshot: _justScreenshotResolution == resolution);
  }

  Future<void> _onResolutionDelete(String resolution) async {
    final layout = _layouts.firstWhere(
      (l) => l.resolution == resolution,
      orElse: () => DesktopLayout(name: '', resolution: '', background: BackgroundConfig(), icons: []),
    );

    if (layout.id == null) {
      // Just remove from local list
      setState(() {
        _resolutionOptions.remove(resolution);
        if (_currentResolution == resolution) {
          _currentResolution = _resolutionOptions.isNotEmpty ? _resolutionOptions.first : null;
        }
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除布局'),
        content: Text('确定要删除 $resolution 的布局吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _desktopApi.deleteLayout(layout.id!);
      showTopNotice(context, '已删除布局', level: NoticeLevel.success);
      await _loadLayouts();
    } catch (e) {
      showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onAddIcon() async {
    final result = await showAdaptive<IconEditResult>(
      context,
      (context) => IconEditDialog(
        groupId: _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId,
        netbarId: _selectedNetbarId,
      ),
      routeName: '/dialog/icon-edit',
    );

    if (result == null) return;

    // Save icon to server
    try {
      final response = await _iconApi.saveIcon(
        groupFileId: result.config.groupFileId ?? '',
        fileId: result.config.fileId,
        iconFile: result.iconFile,
        iconFileName: result.iconFileName,
        type: result.config.type,
        name: result.config.name,
        parameter: result.config.parameter,
        groupId: _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId,
        netbarId: _selectedNetbarId,
      );

      final newId = response?['id']?.toString() ?? DateTime.now().toIso8601String();
      final iconUrl = response?['url']?.toString() ?? result.config.iconUrl;

      // Add to local list
      final settings = _currentResolution != null
          ? ResolutionSettings.fromResolution(_currentResolution!)
          : const ResolutionSettings(width: 1920, height: 1080);
      final defaultPos = settings.getDefaultPosition(_desktopIcons.length);

      final newIcon = DesktopIcon(
        id: newId,
        label: result.config.name,
        iconUrl: iconUrl,
        positions: {_currentResolution ?? '1920 x 1080': defaultPos},
        config: result.config.copyWith(iconUrl: iconUrl),
      );

      setState(() => _desktopIcons.add(newIcon));
      showTopNotice(context, '图标已添加', level: NoticeLevel.success);
    } catch (e) {
      showTopNotice(context, '保存图标失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onEditIcon(DesktopIcon icon) async {
    final result = await showAdaptive<IconEditResult>(
      context,
      (context) => IconEditDialog(
        initialIcon: icon,
        groupId: _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId,
        netbarId: _selectedNetbarId,
      ),
      routeName: '/dialog/icon-edit',
    );

    if (result == null) return;

    try {
      final response = await _iconApi.saveIcon(
        id: icon.id,
        groupFileId: result.config.groupFileId ?? '',
        fileId: result.config.fileId,
        iconFile: result.iconFile,
        iconFileName: result.iconFileName,
        type: result.config.type,
        name: result.config.name,
        parameter: result.config.parameter,
        groupId: _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId,
        netbarId: _selectedNetbarId,
      );

      final iconUrl = response?['url']?.toString() ?? result.config.iconUrl;

      setState(() {
        final idx = _desktopIcons.indexWhere((i) => i.id == icon.id);
        if (idx != -1) {
          _desktopIcons[idx] = icon.copyWith(
            label: result.config.name,
            iconUrl: iconUrl,
            config: result.config.copyWith(iconUrl: iconUrl),
          );
        }
      });

      showTopNotice(context, '图标已更新', level: NoticeLevel.success);
    } catch (e) {
      showTopNotice(context, '保存图标失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onDeleteIcon(DesktopIcon icon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除图标'),
        content: Text('确定要删除 ${icon.label} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _iconApi.deleteIcon(icon.id);
      setState(() => _desktopIcons.removeWhere((i) => i.id == icon.id));
      showTopNotice(context, '图标已删除', level: NoticeLevel.success);
    } catch (e) {
      showTopNotice(context, '删除失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onSave() async {
    if (_currentResolution == null) {
      showTopNotice(context, '请先获取截图或选择分辨率', level: NoticeLevel.warning);
      return;
    }

    try {
      // Build layout
      final groupId = _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId;

      final layout = DesktopLayout(
        id: _currentLayout?.id,
        netbarId: _selectedNetbarId,
        groupId: groupId,
        name: _currentLayout?.name ?? '桌面布局',
        resolution: _currentResolution!,
        background: BackgroundConfig(),
        icons: _desktopIcons,
        lockIcons: false,
      );

      // 只有当前是新截图且对应当前分辨率时，才上传背景图片
      Uint8List? backgroundFile;
      if (_justScreenshotResolution == _currentResolution && _screenshotBytes != null) {
        backgroundFile = _screenshotBytes;
      }

      if (layout.id != null) {
        await _desktopApi.updateLayout(layout, backgroundFile: backgroundFile);
      } else {
        await _desktopApi.createLayout(layout, backgroundFile: backgroundFile);
      }

      setState(() {
        _layoutBackup = null;
        _justScreenshotResolution = null;
      });

      showTopNotice(context, '保存成功', level: NoticeLevel.success);
      await _loadLayouts();
    } catch (e) {
      showTopNotice(context, '保存失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onForceUpdate() async {
    if (_selectedNetbarId == null) {
      showTopNotice(context, '请先选择网吧', level: NoticeLevel.warning);
      return;
    }

    // Save first
    await _onSave();

    try {
      await _desktopApi.forceUpdateDesktop(netbarId: _selectedNetbarId!);
      showTopNotice(context, '强制更新成功', level: NoticeLevel.success);
    } catch (e) {
      showTopNotice(context, '强制更新失败: $e', level: NoticeLevel.error);
    }
  }

  Future<void> _onCopyLayout() async {
    if (_screenshotBytes == null && _screenshotUrl == null) {
      showTopNotice(context, '请先获取截图或设置背景，才能进行复制操作', level: NoticeLevel.warning);
      return;
    }

    final layout = await showAdaptive<DesktopLayout>(
      context,
      (context) => CopyLayoutDialog(
        currentNetbarId: _selectedNetbarId,
        groupId: _currentUserGroupId == 0 ? _selectedGroupId : _currentUserGroupId,
      ),
      routeName: '/dialog/copy-layout',
    );

    if (layout == null) return;

    // Backup current icons
    _layoutBackup ??= _desktopIcons.map((i) => i.copyWith()).toList();

    // Copy layout
    int updatedCount = 0;
    int addedCount = 0;

    for (final srcIcon in layout.icons) {
      final existingIdx = _desktopIcons.indexWhere((i) =>
          i.id == srcIcon.id ||
          i.config.groupFileId == srcIcon.config.groupFileId ||
          i.config.name == srcIcon.config.name);

      final srcPos = srcIcon.getPosition(layout.resolution);

      if (existingIdx != -1) {
        // Update position
        _desktopIcons[existingIdx].positions[_currentResolution!] = srcPos.copyWith();
        updatedCount++;
      } else {
        // Add new icon
        final newIcon = srcIcon.copyWith();
        newIcon.positions[_currentResolution!] = srcPos.copyWith();
        _desktopIcons.add(newIcon);
        addedCount++;
      }
    }

    setState(() {});
    showTopNotice(
      context,
      '已从 ${layout.resolution} 复制: 新增 $addedCount 个, 更新 $updatedCount 个位置',
      level: NoticeLevel.success,
    );
  }

  void _onIconDragStart(DesktopIcon icon, Offset globalPosition, Offset localPosition) {
    final pos = icon.getPosition(_currentResolution ?? '');
    _draggingId = icon.id;
    _dragOffset = localPosition;
    _dragPositionNotifier.value = Offset(pos.x, pos.y);
    setState(() {}); // 显示拖拽预览，原图标变淡
  }

  void _onIconDragUpdate(Offset globalPosition, BoxConstraints constraints) {
    if (_draggingId == null) return;

    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPos = renderBox.globalToLocal(globalPosition);
    final newX = (localPos.dx - (_dragOffset?.dx ?? 0)).clamp(0.0, constraints.maxWidth - 78);
    final newY = (localPos.dy - (_dragOffset?.dy ?? 0)).clamp(0.0, constraints.maxHeight - 96);

    _dragPositionNotifier.value = Offset(newX, newY); // 只更新预览位置，不触发 setState
  }

  void _onIconDragEnd() {
    if (_draggingId != null && _currentResolution != null) {
      final pos = _dragPositionNotifier.value;
      if (pos != null) {
        // 拖拽结束，更新图标真实位置
        final icon = _desktopIcons.firstWhere((i) => i.id == _draggingId);
        icon.positions[_currentResolution!] = IconPosition(x: pos.dx, y: pos.dy);
      }
    }
    _draggingId = null;
    _dragOffset = null;
    _dragPositionNotifier.value = null;
    setState(() {}); // 隐藏拖拽预览，更新图标位置
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('操作提示'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• 获取不同分辨率电脑的桌面截图，该截图用于布局背景，方便添加桌标拖放位置'),
            SizedBox(height: 8),
            Text('• 点击图标可进行编辑或删除'),
            SizedBox(height: 8),
            Text('• 拖拽图标可调整位置'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听标签页变化
    _setupTabListener();

    if (context.isPhone) {
      return _buildMobileNotSupported();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: Column(
        children: [
          // Toolbar
          DesktopToolbar(
            onBack: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
            seatOptions: _seatOptions,
            selectedSeatId: _selectedSeatId,
            onSeatChanged: _onSeatChanged,
            screenshotLoading: _screenshotLoading,
            onScreenshot: _onScreenshot,
            resolutionOptions: _resolutionOptions,
            currentResolution: _currentResolution,
            onResolutionChanged: _onResolutionChanged,
            onResolutionDelete: _onResolutionDelete,
            onAddIcon: _onAddIcon,
            onSave: _onSave,
            onForceUpdate: _onForceUpdate,
            onCopyLayout: _onCopyLayout,
            onHelp: _showHelp,
          ),

          // Content
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : _buildDesktopArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNotSupported() {
    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.monitor, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                '桌面管理仅支持电脑端',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '请在电脑浏览器（Chrome）或桌面端使用该功能',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/dashboard'),
                child: const Text('返回概览'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade600),
          ),
          const SizedBox(height: 6),
          Text(_error ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _initData,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopArea() {
    if (_currentResolution == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.image, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '请先选择网吧和机号，然后点击"获取电脑截图"',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final settings = ResolutionSettings.fromResolution(_currentResolution!);

    return Stack(
      children: [
        // Desktop canvas
        Positioned.fill(
          child: Container(
            color: const Color(0xFFF0F1F2),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildDesktopCanvas(settings),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopCanvas(ResolutionSettings settings) {
    return Container(
      key: _canvasKey,
      width: settings.width.toDouble(),
      height: settings.height.toDouble(),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        image: _buildBackgroundImage(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: () => setState(() => _activeIconId = null), // 点击空白处取消选中
            behavior: HitTestBehavior.translucent,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Grid dots (使用 RepaintBoundary 避免重绘)
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: const _GridPainter(),
                  ),
                ),

                // Icons - 所有图标都保持在原位
                ..._desktopIcons.map((icon) {
                  final isActive = _activeIconId == icon.id;
                  final isDragging = _draggingId == icon.id;
                  final pos = icon.getPosition(_currentResolution!);

                  return Positioned(
                    left: pos.x,
                    top: pos.y,
                    child: Opacity(
                      opacity: isDragging ? 0.3 : 1.0, // 拖拽时原图标变淡
                      child: RepaintBoundary(
                        child: _buildDraggableIcon(icon, constraints, isActive: isActive, isDragging: false),
                      ),
                    ),
                  );
                }),

                // 拖拽中的浮动图标 - 只有这个跟随鼠标
                if (_draggingId != null)
                  ValueListenableBuilder<Offset?>(
                    valueListenable: _dragPositionNotifier,
                    builder: (context, dragPos, child) {
                      if (dragPos == null) return const SizedBox.shrink();
                      return Positioned(
                        left: dragPos.dx,
                        top: dragPos.dy,
                        child: child!,
                      );
                    },
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: _buildDragPreview(),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDraggableIcon(DesktopIcon icon, BoxConstraints constraints, {bool isActive = false, bool isDragging = false}) {
    final iconWidget = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_activeIconId != icon.id) {
            setState(() => _activeIconId = icon.id);
          }
        },
        onPanStart: (details) => _onIconDragStart(icon, details.globalPosition, details.localPosition),
        onPanUpdate: (details) => _onIconDragUpdate(details.globalPosition, constraints),
        onPanEnd: (_) => _onIconDragEnd(),
        child: _buildDesktopIcon(icon, isActive: isActive, isDragging: isDragging),
      ),
    );

    if (!isActive) {
      return iconWidget;
    }

    // 有操作按钮时使用 Stack
    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        // 操作按钮
        Positioned(
          left: -36,
          top: 4,
          child: _buildIconActions(icon),
        ),
      ],
    );
  }

  Widget _buildIconActions(DesktopIcon icon) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        elevation: 2,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _onDeleteIcon(icon),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: const Icon(LucideIcons.trash2, size: 14, color: Colors.red),
                ),
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: () => _onEditIcon(icon),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.settings, size: 14, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建拖拽预览图标
  Widget _buildDragPreview() {
    if (_draggingId == null) return const SizedBox.shrink();

    final icon = _desktopIcons.firstWhere(
      (i) => i.id == _draggingId,
      orElse: () => _desktopIcons.first,
    );

    return Opacity(
      opacity: 0.85,
      child: Container(
        width: 78,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.iosBlue, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: _buildIconImage(icon),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              icon.label.isNotEmpty ? icon.label : icon.config.name,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  DecorationImage? _buildBackgroundImage() {
    if (_screenshotBytes != null) {
      return DecorationImage(
        image: MemoryImage(_screenshotBytes!),
        fit: BoxFit.cover,
      );
    }
    if (_screenshotUrl != null && _screenshotUrl!.isNotEmpty) {
      return DecorationImage(
        image: NetworkImage(
          _screenshotUrl!,
          headers: DesktopApi.getAuthHeaders(),
        ),
        fit: BoxFit.cover,
      );
    }
    return null;
  }

  Widget _buildDesktopIcon(DesktopIcon icon, {bool isActive = false, bool isDragging = false}) {
    return Container(
      width: 78,
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? AppColors.iosBlue : Colors.grey.shade300,
                width: isActive ? 2 : 1,
              ),
              boxShadow: isDragging
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _buildIconImage(icon),
            ),
          ),

          const SizedBox(height: 4),

          // Label
          Text(
            icon.label.isNotEmpty ? icon.label : icon.config.name,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 2),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildIconImage(DesktopIcon icon) {
    final iconUrl = icon.iconUrl ?? icon.config.iconUrl;

    if (iconUrl != null && iconUrl.isNotEmpty) {
      // 使用 DesktopApi.getBackgroundUrl 处理 URL，避免重复 /api
      final url = _desktopApi.getBackgroundUrl(iconUrl);

      if (url.isEmpty) {
        return _buildDefaultIcon(icon);
      }

      // 使用支持 ICO 格式的 NetworkIconImage
      return NetworkIconImage(
        url: url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('图标加载失败 ${icon.label}: $error');
          return _buildDefaultIcon(icon);
        },
      );
    }

    return _buildDefaultIcon(icon);
  }

  Widget _buildDefaultIcon(DesktopIcon icon) {
    // Get first letter of label
    final letter = icon.label.isNotEmpty ? icon.label[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.iosBlue.withOpacity(0.8),
            AppColors.iosBlue,
          ],
        ),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE7E9EC)
      ..style = PaintingStyle.fill;

    const gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      for (double y = 0; y < size.height; y += gridSize) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
