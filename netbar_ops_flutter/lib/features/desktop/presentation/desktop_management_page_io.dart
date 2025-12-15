import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/storage/token_store.dart';
import '../data/desktop_model.dart';
import '../data/desktop_api.dart';
import 'widgets/desktop_toolbar.dart';
import 'widgets/desktop_icon_widget.dart';
import 'widgets/add_icon_dialog.dart';
import 'widgets/desktop_background_dialog.dart';

class DesktopManagementPage extends StatefulWidget {
  const DesktopManagementPage({super.key});

  @override
  State<DesktopManagementPage> createState() => _DesktopManagementPageState();
}

class _DesktopManagementPageState extends State<DesktopManagementPage> {
  // State
  String _resolution = '1920*1080';
  bool _lockIcons = false;
  DesktopLayout? _currentLayout;
  List<DesktopLayout> _layouts = [];
  bool _loading = true;
  String? _error;
  final TransformationController _transformationController = TransformationController();
  double _scale = 0.6;
  final DesktopApi _desktopApi = DesktopApi();
  String? _hoveredIconId;
  
  // Selection
  final Set<String> _selectedIconIds = {};

  @override
  void initState() {
    super.initState();
    _loadLayouts();
    _transformationController.addListener(_onTransformationChanged);
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _onTransformationChanged() {
    final newScale = _transformationController.value.getMaxScaleOnAxis();
    if ((newScale - _scale).abs() > 0.01) {
      setState(() => _scale = newScale);
    }
  }

  Future<void> _loadLayouts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final layouts = await _desktopApi.getLayouts();
      DesktopLayout layout;
      if (layouts.isNotEmpty) {
        // Prefer matching resolution, else first
        layout = layouts.firstWhere(
          (l) => l.resolution == _resolution,
          orElse: () => layouts.first,
        );
        _resolution = layout.resolution;
        _normalizeLayoutAssets(layout);
      } else {
        layout = DesktopLayout(
          name: '默认桌面',
          resolution: _resolution,
          background: BackgroundConfig(url: '', mode: 'center'),
          icons: [],
        );
      }
      setState(() {
        _layouts = layouts;
        _currentLayout = layout;
        _lockIcons = layout.lockIcons;
        _selectedIconIds.clear();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onZoom(double scaleFactor) {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final newScale = (currentScale * scaleFactor).clamp(0.1, 4.0);

    // Approximate viewport center (screen center minus headers/sidebars if any)
    // For better precision, we could store the actual LayoutBuilder constraints.
    // Here we use the center of the InteractiveViewer's coordinate space (which is the screen space for the transformation)
    // The transformation is applied at (0,0) of the InteractiveViewer.
    // We want to scale around the center of the visible area.
    
    // Simple approach: calculate the point in the scene currently at the center of the viewport
    final viewportWidth = MediaQuery.of(context).size.width;
    final viewportHeight = MediaQuery.of(context).size.height - 64; // Approx minus header
    
    final center = Offset(viewportWidth / 2, viewportHeight / 2);
    
    // Invert the current transform to find the point in the scene
    final x = -currentMatrix.getTranslation().x;
    final y = -currentMatrix.getTranslation().y;
    
    final scenePointX = (center.dx + x) / currentScale;
    final scenePointY = (center.dy + y) / currentScale;
    
    // Calculate new translation to keep scenePoint at center
    final newX = center.dx - scenePointX * newScale;
    final newY = center.dy - scenePointY * newScale;
    
    _transformationController.value = Matrix4.identity()
      ..translate(newX, newY)
      ..scale(newScale);
  }

  void _updateIconPosition(String id, Offset delta) {
    if (_lockIcons || _currentLayout == null) return;
    
    setState(() {
      final icon = _currentLayout!.icons.firstWhere((i) => i.id == id);
      // Fix: GestureDetector inside InteractiveViewer already provides local coordinates
      // or Flutter handles the transform. Removing division by scale.
      icon.x += delta.dx;
      icon.y += delta.dy;
    });
  }

  void _alignGrid() {
    if (_currentLayout == null) return;
    setState(() {
      for (var icon in _currentLayout!.icons) {
        icon.x = (icon.x / 90).round() * 90.0;
        icon.y = (icon.y / 110).round() * 110.0;
      }
    });
  }

  void _handleAddIcon() async {
    if (_currentLayout == null) return;
    
    final config = await showDialog<DesktopIconConfig>(
      context: context,
      builder: (context) => const AddIconDialog(),
    );

    if (config != null) {
      final scenePoint = _scenePointAtViewportCenter();
      final iconWidth = 88.0;
      final iconHeight = 96.0;
      setState(() {
        _currentLayout!.icons.add(DesktopIcon(
          id: DateTime.now().toString(),
          name: config.name,
          config: config,
          x: (scenePoint.dx - iconWidth / 2).clamp(0, double.infinity),
          y: (scenePoint.dy - iconHeight / 2).clamp(0, double.infinity),
        ));
      });
    }
  }

  void _handleBackgroundSettings() async {
    if (_currentLayout == null) return;

    final config = await showDialog<BackgroundConfig>(
      context: context,
      builder: (context) => DesktopBackgroundDialog(initialConfig: _currentLayout!.background),
    );

    if (config != null) {
      setState(() {
        _currentLayout!.background.url = config.url;
        _currentLayout!.background.mode = config.mode;
        _currentLayout!.background.delay = config.delay;
        _currentLayout!.background.locked = config.locked;
      });
    }
  }

  void _handleEditIcon(DesktopIcon icon) async {
    final edited = await showDialog<DesktopIconConfig>(
      context: context,
      builder: (context) => AddIconDialog(initialIcon: icon),
    );

    if (edited != null) {
      setState(() {
        final idx = _currentLayout!.icons.indexWhere((i) => i.id == icon.id);
        if (idx != -1) {
          _currentLayout!.icons[idx] = DesktopIcon(
            id: icon.id,
            name: edited.name,
            config: edited,
            x: icon.x,
            y: icon.y,
          );
        }
      });
    }
  }

  /// 将视口中心转换为场景坐标，便于在当前视图中央放置/定位图标
  Offset _scenePointAtViewportCenter() {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final size = MediaQuery.of(context).size;
    // 扣掉顶部工具栏和常规内边距的高度估算
    final viewport = Size(size.width, size.height - 120);
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sceneX = (center.dx - translation.x) / scale;
    final sceneY = (center.dy - translation.y) / scale;
    return Offset(sceneX, sceneY);
  }

  DecorationImage? _resolveBackgroundImage(String? url, String? mode) {
    if (url == null || url.isEmpty) return null;
    final provider = _buildImageProvider(url);
    if (provider == null) return null;
    return DecorationImage(
      image: provider,
      fit: mode == 'stretch'
          ? BoxFit.fill
          : mode == 'tile'
              ? BoxFit.none
              : BoxFit.contain,
      repeat: mode == 'tile' ? ImageRepeat.repeat : ImageRepeat.noRepeat,
    );
  }

  ImageProvider? _buildImageProvider(String url) {
    final token = TokenStore.getToken();
    // data URL
    if (url.startsWith('data:')) return NetworkImage(url);
    // absolute http/https
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final full = _appendToken(url, token);
      return NetworkImage(full, headers: token != null ? {'Authorization': 'Bearer $token'} : null);
    }
    // absolute file path (only valid on non-web with actual file)
    final isDrivePath = RegExp(r'^[A-Za-z]:[\\\\/]').hasMatch(url);
    if (!kIsWeb && (url.startsWith('/') || url.contains('\\') || isDrivePath)) {
      if (File(url).existsSync()) return FileImage(File(url));
      return null; // skip invalid local path
    }
    // relative path -> use baseUrl
    final base = AppConfig.baseUrl.endsWith('/') ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1) : AppConfig.baseUrl;
    final fullPath = url.startsWith('/') ? '$base$url' : '$base/$url';
    final full = _appendToken(fullPath, token);
    return NetworkImage(full, headers: token != null ? {'Authorization': 'Bearer $token'} : null);
  }

  String _appendToken(String url, String? token) {
    if (token == null || url.contains('token=')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}token=$token';
  }

  void _normalizeLayoutAssets(DesktopLayout layout) {
    // 将相对路径保留，渲染时拼 baseUrl。此处仅确保字段非空，不做重写。
    // 可在此处清理掉本地磁盘路径，避免保存错误数据。
    if (layout.background.url.startsWith('file:') || layout.background.url.contains(':\\')) {
      layout.background.url = '';
    }
    for (final icon in layout.icons) {
      final path = icon.config.iconPath;
      if (path != null && path.contains(':\\')) {
        icon.config.iconPath?.replaceAll('\\', '/');
      }
    }
  }

  DesktopLayout _cloneLayoutForSave(DesktopLayout src) {
    String sanitize(String p) {
      if (p.isEmpty) return p;
      var out = p;
      // strip baseUrl
      final base = AppConfig.baseUrl.endsWith('/')
          ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
          : AppConfig.baseUrl;
      if (out.startsWith(base)) {
        out = out.substring(base.length);
      }
      // strip token query
      final idx = out.indexOf('?');
      if (idx > -1) {
        out = out.substring(0, idx);
      }
      return out;
    }

    final clonedIcons = src.icons
        .map((i) => DesktopIcon(
              id: i.id,
              name: i.name,
              config: DesktopIconConfig(
                exePath: i.config.exePath,
                name: i.config.name,
                args: i.config.args,
                workDir: i.config.workDir,
                iconPath: i.config.iconPath != null ? sanitize(i.config.iconPath!) : null,
              ),
              x: i.x,
              y: i.y,
            ))
        .toList();

    return DesktopLayout(
      id: src.id,
      name: src.name,
      resolution: src.resolution,
      background: BackgroundConfig(
        url: sanitize(src.background.url),
        delay: src.background.delay,
        mode: src.background.mode,
        locked: src.background.locked,
      ),
      icons: clonedIcons,
      lockIcons: src.lockIcons,
    );
  }

  void _centerCanvas(double viewportWidth, double viewportHeight, double contentWidth, double contentHeight) {
    // Only center if first load (or reset)
    // Scale 0.6 to fit comfortably
    final scale = 0.6;
    final x = (viewportWidth - contentWidth * scale) / 2;
    final y = (viewportHeight - contentHeight * scale) / 2;
    _transformationController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    if (!isDesktopPlatform) {
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
                const Text('桌面管理仅支持桌面端',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('请在 Windows/macOS/Linux 上使用该功能',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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

    // Parse resolution
    final parts = _resolution.split('*');
    final resW = double.parse(parts[0]);
    final resH = double.parse(parts[1]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
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
            layouts: _layouts,
            currentLayout: _currentLayout,
            onLayoutChanged: (layout) {
              if (layout == null) return;
              setState(() {
                _currentLayout = layout;
                _resolution = layout.resolution;
                _lockIcons = layout.lockIcons;
                _selectedIconIds.clear();
              });
            },
            onDeleteLayout: _handleDeleteLayout,
            resolution: _resolution,
            onResolutionChanged: (v) {
              setState(() {
                _resolution = v;
                if (_currentLayout != null) {
                  _currentLayout!.resolution = v;
                }
              });
              // Do NOT reload layout. Keep current icons/background.
              // _loadLayout(); 
              
              // Re-center canvas on resolution change
              final parts = v.split('*');
              final w = double.parse(parts[0]);
              final h = double.parse(parts[1]);
              // Use slight delay to ensure layout updates
              WidgetsBinding.instance.addPostFrameCallback((_) {
                 _centerCanvas(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height, w, h);
              });
            },
            lockIcons: _lockIcons,
            onLockIconsChanged: (v) => setState(() {
              _lockIcons = v;
              if (_currentLayout != null) _currentLayout!.lockIcons = v;
            }),
            scale: _scale,
            onZoomIn: () => _onZoom(1.1),
            onZoomOut: () => _onZoom(0.9),
            onResetZoom: () {
               _centerCanvas(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height, resW, resH);
            },
            onAlignGrid: _alignGrid,
            onAddIcon: _handleAddIcon,
            onBackgroundSettings: _handleBackgroundSettings,
            onSave: _handleSave,
            onRefresh: _loadLayouts,
          ),
          
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(resW, resH)
                    : Container(
                        color: const Color(0xFFF0F1F2),
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: _buildCanvas(resW, resH),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(double resW, double resH) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text('加载桌面布局失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade600)),
          const SizedBox(height: 6),
          Text(_error ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadLayouts,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(double resW, double resH) {
    return GestureDetector(
      onTap: () => setState(() => _selectedIconIds.clear()),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (_transformationController.value.isIdentity()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _centerCanvas(constraints.maxWidth, constraints.maxHeight, resW, resH);
            });
          }

          return InteractiveViewer(
            transformationController: _transformationController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.1,
            maxScale: 4.0,
            constrained: false,
            panEnabled: true,
            scaleEnabled: true,
            child: Container(
              width: resW,
              height: resH,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 8)),
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                ],
                image: _resolveBackgroundImage(_currentLayout?.background.url, _currentLayout?.background.mode),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GridPainter(),
                    ),
                  ),
                  if (_currentLayout != null)
                    ..._currentLayout!.icons.map((icon) {
                      final isSelected = _selectedIconIds.contains(icon.id);
                      return Positioned(
                        left: icon.x,
                        top: icon.y,
                        child: MouseRegion(
                          onEnter: (_) => setState(() {
                            _hoveredIconId = icon.id;
                          }),
                          onExit: (_) => setState(() {
                            _hoveredIconId = null;
                          }),
                          child: GestureDetector(
                            onPanUpdate: (details) => _updateIconPosition(icon.id, details.delta),
                            onTapDown: (_) => setState(() {
                              _selectedIconIds
                                ..clear()
                                ..add(icon.id);
                            }),
                            child: DesktopIconWidget(
                              icon: icon,
                              isSelected: isSelected,
                              showActions: _hoveredIconId == icon.id,
                              isLocked: _lockIcons,
                              onEdit: () => _handleEditIcon(icon),
                              onDelete: () {
                                setState(() {
                                  _currentLayout!.icons.remove(icon);
                                });
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDeleteLayout() async {
    if (_currentLayout?.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除布局'),
        content: Text('确定删除布局 ${_currentLayout!.name} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
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
      await _desktopApi.deleteLayout(_currentLayout!.id!);
      await _loadLayouts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${_currentLayout?.name ?? ''}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleSave() async {
    if (_currentLayout == null) return;
    try {
      if (_currentLayout!.name.isEmpty) {
        _currentLayout!.name = '桌面布局';
      }
      final layoutForSave = _cloneLayoutForSave(_currentLayout!);
      final updated = await (layoutForSave.id == null
          ? _desktopApi.createLayout(layoutForSave)
          : _desktopApi.updateLayout(layoutForSave));
      setState(() {
        _currentLayout = updated;
        _lockIcons = updated.lockIcons;
        // 如果是新建，重新加载列表以包含新布局
        if (_layouts.every((l) => l.id != updated.id)) {
          _loadLayouts();
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class GridPainter extends CustomPainter {
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
