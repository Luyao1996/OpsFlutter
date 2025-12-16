import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../core/storage/token_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../data/desktop_api.dart';
import '../data/desktop_model.dart';
import 'widgets/add_icon_dialog.dart';
import 'widgets/desktop_background_dialog.dart';
import 'widgets/desktop_icon_widget.dart';
import 'widgets/desktop_toolbar.dart';

class DesktopManagementPageImpl extends StatefulWidget {
  const DesktopManagementPageImpl({super.key});

  @override
  State<DesktopManagementPageImpl> createState() =>
      _DesktopManagementPageImplState();
}

class _DesktopManagementPageImplState extends State<DesktopManagementPageImpl> {
  String _resolution = '1920*1080';
  bool _lockIcons = false;
  DesktopLayout? _currentLayout;
  List<DesktopLayout> _layouts = [];
  bool _loading = true;
  String? _error;
  final TransformationController _transformationController =
      TransformationController();
  double _scale = 0.6;
  final DesktopApi _desktopApi = DesktopApi();
  String? _hoveredIconId;
  int? _activeNetbarId;

  final Set<String> _selectedIconIds = {};

  @override
  void initState() {
    super.initState();
    _activeNetbarId = _readCurrentNetbarId();
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
      final layouts = await _desktopApi.getLayouts(netbarId: _activeNetbarId);
      final layout = _pickLayout(layouts);
      if (layout != null) {
        _resolution = layout.resolution;
        _normalizeLayoutAssets(layout);
      }
      setState(() {
        _layouts = layouts;
        _currentLayout = layout ??
            DesktopLayout(
              name: '默认桌面',
              resolution: _resolution,
              background: BackgroundConfig(url: '', mode: 'center'),
              icons: [],
            );
        _lockIcons = _currentLayout!.lockIcons;
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

  int? _readCurrentNetbarId() {
    final netbar = TokenStore.getCurrentNetbar();
    final raw = netbar?['id'];
    if (raw is int) return raw;
    return int.tryParse('$raw');
  }

  DesktopLayout? _pickLayout(List<DesktopLayout> layouts) {
    if (layouts.isEmpty) return null;

    final current = _currentLayout;
    final netbarId = _activeNetbarId;

    if (current != null) {
      // Prefer the same record id when possible.
      if (current.id != null) {
        for (final layout in layouts) {
          if (layout.id == current.id) return layout;
        }
      }

      // Netbar mode: if current is a global template, prefer its override.
      if (netbarId != null && current.netbarId == null && current.id != null) {
        for (final layout in layouts) {
          if (layout.netbarId == netbarId && layout.baseLayoutId == current.id) {
            return layout;
          }
        }
      }

      // If current is an override, prefer matching by baseLayoutId.
      if (netbarId != null &&
          current.netbarId == netbarId &&
          current.baseLayoutId != null) {
        for (final layout in layouts) {
          if (layout.netbarId == netbarId &&
              layout.baseLayoutId == current.baseLayoutId) {
            return layout;
          }
        }
      }
    }

    // Fallback: keep the current resolution selection.
    for (final layout in layouts) {
      if (layout.resolution == _resolution) return layout;
    }
    return layouts.first;
  }

  void _onZoom(double scaleFactor) {
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final newScale = (currentScale * scaleFactor).clamp(0.1, 4.0);

    final viewportWidth = MediaQuery.of(context).size.width;
    final viewportHeight = MediaQuery.of(context).size.height - 64;
    final center = Offset(viewportWidth / 2, viewportHeight / 2);

    final x = -currentMatrix.getTranslation().x;
    final y = -currentMatrix.getTranslation().y;
    final scenePointX = (center.dx + x) / currentScale;
    final scenePointY = (center.dy + y) / currentScale;

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
      icon.x += delta.dx;
      icon.y += delta.dy;
    });
  }

  void _alignGrid() {
    if (_currentLayout == null) return;
    setState(() {
      for (final icon in _currentLayout!.icons) {
        icon.x = (icon.x / 90).round() * 90.0;
        icon.y = (icon.y / 110).round() * 110.0;
      }
    });
  }

  Future<void> _handleAddIcon() async {
    if (_currentLayout == null) return;
    final config = await showDialog<DesktopIconConfig>(
      context: context,
      builder: (context) => const AddIconDialog(),
    );
    if (config == null) return;
    final scenePoint = _scenePointAtViewportCenter();
    const iconWidth = 88.0;
    const iconHeight = 96.0;
    setState(() {
      _currentLayout!.icons.add(
        DesktopIcon(
          id: DateTime.now().toIso8601String(),
          name: config.name,
          config: config,
          x: (scenePoint.dx - iconWidth / 2).clamp(0, double.infinity),
          y: (scenePoint.dy - iconHeight / 2).clamp(0, double.infinity),
        ),
      );
    });
  }

  Future<void> _handleBackgroundSettings() async {
    if (_currentLayout == null) return;
    final config = await showDialog<BackgroundConfig>(
      context: context,
      builder: (context) =>
          DesktopBackgroundDialog(initialConfig: _currentLayout!.background),
    );
    if (config == null) return;
    setState(() {
      _currentLayout!.background.url = config.url;
      _currentLayout!.background.mode = config.mode;
      _currentLayout!.background.delay = config.delay;
      _currentLayout!.background.locked = config.locked;
    });
  }

  Future<void> _handleEditIcon(DesktopIcon icon) async {
    final edited = await showDialog<DesktopIconConfig>(
      context: context,
      builder: (context) => AddIconDialog(initialIcon: icon),
    );
    if (edited == null) return;
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

  Offset _scenePointAtViewportCenter() {
    final matrix = _transformationController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();
    final size = MediaQuery.of(context).size;
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
    if (url.startsWith('data:')) return NetworkImage(url);
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final full = _appendToken(url, token);
      return NetworkImage(full);
    }

    final base = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    final fullPath = url.startsWith('/') ? '$base$url' : '$base/$url';
    final full = _appendToken(fullPath, token);
    return NetworkImage(full);
  }

  String _appendToken(String url, String? token) {
    if (token == null || url.contains('token=')) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}token=$token';
  }

  void _normalizeLayoutAssets(DesktopLayout layout) {
    if (layout.background.url.startsWith('file:') ||
        layout.background.url.contains(':\\')) {
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
      final base = AppConfig.baseUrl.endsWith('/')
          ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
          : AppConfig.baseUrl;
      if (out.startsWith(base)) {
        out = out.substring(base.length);
      }
      final idx = out.indexOf('?');
      if (idx > -1) out = out.substring(0, idx);
      return out;
    }

    final clonedIcons = src.icons
        .map(
          (i) => DesktopIcon(
            id: i.id,
            name: i.name,
            config: DesktopIconConfig(
              exePath: i.config.exePath,
              name: i.config.name,
              args: i.config.args,
              workDir: i.config.workDir,
              iconPath: i.config.iconPath != null
                  ? sanitize(i.config.iconPath!)
                  : null,
            ),
            x: i.x,
            y: i.y,
          ),
        )
        .toList();

    return DesktopLayout(
      id: src.id,
      netbarId: src.netbarId,
      baseLayoutId: src.baseLayoutId,
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

  void _centerCanvas(
    double viewportWidth,
    double viewportHeight,
    double contentWidth,
    double contentHeight,
  ) {
    const scale = 0.6;
    final x = (viewportWidth - contentWidth * scale) / 2;
    final y = (viewportHeight - contentHeight * scale) / 2;
    _transformationController.value = Matrix4.identity()
      ..translate(x, y)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    final latestNetbarId = _readCurrentNetbarId();
    if (latestNetbarId != _activeNetbarId) {
      _activeNetbarId = latestNetbarId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadLayouts();
      });
    }

    if (context.isPhone) {
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

    final parts = _resolution.split('*');
    final resW = double.parse(parts[0]);
    final resH = double.parse(parts[1]);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F7),
      body: Column(
        children: [
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
                if (_currentLayout != null) _currentLayout!.resolution = v;
              });
              final parts = v.split('*');
              final w = double.parse(parts[0]);
              final h = double.parse(parts[1]);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _centerCanvas(
                  MediaQuery.of(context).size.width,
                  MediaQuery.of(context).size.height,
                  w,
                  h,
                );
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
            onResetZoom: () => _centerCanvas(
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height,
              resW,
              resH,
            ),
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
                    ? _buildError()
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

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertTriangle, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(
            '加载桌面布局失败',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadLayouts,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重试'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.iosBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                image: _resolveBackgroundImage(
                  _currentLayout?.background.url,
                  _currentLayout?.background.mode,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: CustomPaint(painter: GridPainter())),
                  if (_currentLayout != null)
                    ..._currentLayout!.icons.map((icon) {
                      final isSelected = _selectedIconIds.contains(icon.id);
                      return Positioned(
                        left: icon.x,
                        top: icon.y,
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hoveredIconId = icon.id),
                          onExit: (_) => setState(() => _hoveredIconId = null),
                          child: GestureDetector(
                            onPanUpdate: (details) =>
                                _updateIconPosition(icon.id, details.delta),
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
                                setState(() => _currentLayout!.icons.remove(icon));
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
    if (_activeNetbarId != null && _currentLayout?.netbarId == null) {
      if (mounted) {
        showTopNotice(
          context,
          '当前为网吧模式，不能删除全局模板；如需恢复默认，请删除“网吧覆盖”配置',
          level: NoticeLevel.warning,
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除布局'),
        content: Text('确定删除布局 ${_currentLayout!.name} 吗？'),
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
      final wasOverride = _activeNetbarId != null && _currentLayout?.netbarId != null;
      final deletedName = _currentLayout?.name ?? '';
      await _desktopApi.deleteLayout(_currentLayout!.id!);
      await _loadLayouts();
      if (mounted) {
        showTopNotice(
          context,
          wasOverride ? '已恢复为全局模板' : '已删除 $deletedName',
          level: NoticeLevel.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showTopNotice(context, '删除失败：$e', level: NoticeLevel.error);
      }
    }
  }

  Future<void> _handleSave() async {
    if (_currentLayout == null) return;
    try {
      if (_currentLayout!.name.isEmpty) _currentLayout!.name = '桌面布局';
      final netbarId = _activeNetbarId;
      final base = _cloneLayoutForSave(_currentLayout!);

      DesktopLayout request = base;

      // 网吧模式：对全局模板采用“写时复制”生成覆盖；覆盖更新自身
      final canCreateOverride = netbarId != null && base.netbarId == null && base.id != null;
      final creatingOverrideFromGlobal = canCreateOverride;
      if (creatingOverrideFromGlobal) {
        request = DesktopLayout(
          id: null,
          netbarId: netbarId,
          baseLayoutId: base.id,
          name: base.name,
          resolution: base.resolution,
          background: base.background,
          icons: base.icons,
          lockIcons: base.lockIcons,
        );
      } else if (netbarId != null && base.netbarId == null) {
        // 网吧模式但没有全局模板可覆盖：创建网吧自定义布局
        request = DesktopLayout(
          id: base.id,
          netbarId: netbarId,
          baseLayoutId: null,
          name: base.name,
          resolution: base.resolution,
          background: base.background,
          icons: base.icons,
          lockIcons: base.lockIcons,
        );
      } else if (netbarId != null) {
        // 覆盖更新：强制带上当前网吧 id（避免脏数据）
        request.netbarId = netbarId;
      }

      final updated = await (request.id == null
          ? _desktopApi.createLayout(request)
          : _desktopApi.updateLayout(request));

      setState(() {
        _currentLayout = updated;
        _lockIcons = updated.lockIcons;

        final nextLayouts = [..._layouts];
        final updatedId = updated.id;

        if (creatingOverrideFromGlobal) {
          final baseId = base.id;
          if (baseId != null) {
            final idx = nextLayouts.indexWhere((l) => l.id == baseId);
            if (idx != -1) {
              nextLayouts[idx] = updated;
            } else {
              nextLayouts.insert(0, updated);
            }
          } else {
            nextLayouts.insert(0, updated);
          }
        } else if (updatedId != null) {
          final idx = nextLayouts.indexWhere((l) => l.id == updatedId);
          if (idx != -1) {
            nextLayouts[idx] = updated;
          } else {
            nextLayouts.add(updated);
          }
        }

        _layouts = nextLayouts;
      });

      if (mounted) {
        showTopNotice(
          context,
          netbarId != null ? '已保存网吧配置' : '保存成功',
          level: NoticeLevel.success,
        );
      }
    } catch (e) {
      if (mounted) showTopNotice(context, '保存失败：$e', level: NoticeLevel.error);
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
