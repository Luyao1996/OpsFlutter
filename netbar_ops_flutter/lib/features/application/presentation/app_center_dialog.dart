import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/permission_provider.dart';
import '../../../shared/utils/adaptive_show.dart';
import '../../../shared/utils/top_notice.dart';
import '../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../data/application_models.dart';
import '../providers/application_providers.dart';
import 'policy_config_dialog.dart';

/// 应用中心弹窗（单网吧场景）。
///
/// 对齐 toolboxPage AppCenterDialog.vue：左侧分类（已添加应用/全部应用/动态分类）、
/// 搜索、应用卡片网格（添加/取消添加角标 + 已添加可「策略配置」）、分页。
/// group_id 取当前网吧所属分组（currentGroupIdProvider）。
///
/// 权限（对齐 web 调用方传入 PERMISSION_IDS）：
///   添加/取消添加 = 应用添加(22)；策略配置按钮 = 配置应用(23)。
class AppCenterDialog extends ConsumerWidget {
  final int merchantId;
  final String merchantName;

  const AppCenterDialog({
    super.key,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupIdAsync = ref.watch(currentGroupIdProvider);
    return ResponsiveDialogScaffold(
      title: merchantName.isNotEmpty ? '应用中心 - $merchantName' : '应用中心',
      maxWidth: 1100,
      scrollableBody: false,
      body: groupIdAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(48),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => _CenteredTip('获取网吧分组失败: $e'),
        data: (groupId) => groupId == null
            ? const _CenteredTip('未获取到本网吧所属分组，无法使用应用中心')
            : _AppCenterBody(
                groupId: groupId,
                merchantId: merchantId,
                merchantName: merchantName,
              ),
      ),
    );
  }
}

class _CenteredTip extends StatelessWidget {
  final String text;
  const _CenteredTip(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ),
    );
  }
}

class _AppCenterBody extends ConsumerStatefulWidget {
  final int groupId;
  final int merchantId;
  final String merchantName;

  const _AppCenterBody({
    required this.groupId,
    required this.merchantId,
    required this.merchantName,
  });

  @override
  ConsumerState<_AppCenterBody> createState() => _AppCenterBodyState();
}

class _AppCenterBodyState extends ConsumerState<_AppCenterBody> {
  static const _catAdded = 'added';
  static const _catAll = 'all';

  List<AppCategory> _categories = [];
  String _activeCat = _catAdded;

  final _keywordCtrl = TextEditingController();

  List<AppCenterItem> _apps = [];
  bool _loading = true;
  int _page = 1;
  int _size = 20;
  int _total = 0;

  /// 全量已添加：applicationId → 引用记录 id（「全部应用」tab 标记已添加用）
  final Map<int, int?> _addedMap = {};

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    final api = ref.read(applicationApiProvider);
    try {
      // 分类 + 全量引用并行拉取（引用建 addedMap，对齐 web getReferences size=1000）
      final results = await Future.wait([
        api.listCategories(),
        api.listReferences(groupId: widget.groupId, page: 1, size: 1000),
      ]);
      if (!mounted) return;
      _categories = results[0] as List<AppCategory>;
      final (refs, _) = results[1] as (List<Map<String, dynamic>>, int);
      _addedMap.clear();
      for (final raw in refs) {
        final item = AppCenterItem.fromReference(raw);
        if (item.applicationId != 0) {
          _addedMap[item.applicationId] = item.refId;
        }
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '加载应用中心失败: $e', level: NoticeLevel.error);
    }
    await _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() => _loading = true);
    final api = ref.read(applicationApiProvider);
    final keyword = _keywordCtrl.text.trim();
    try {
      if (_activeCat == _catAdded) {
        // 已添加：直接用引用列表（嵌套 application）
        final (list, total) = await api.listReferences(
          groupId: widget.groupId,
          page: _page,
          size: _size,
          keyword: keyword,
        );
        if (!mounted) return;
        setState(() {
          _apps = list.map(AppCenterItem.fromReference).toList();
          _total = total;
        });
      } else {
        // 全部 / 某分类：应用库 + addedMap 标记已添加
        final (list, total) = await api.listApplications(
          page: _page,
          size: _size,
          categoryId: _activeCat == _catAll ? null : int.tryParse(_activeCat),
          keyword: keyword,
        );
        if (!mounted) return;
        setState(() {
          _apps =
              list.map((e) => AppCenterItem.fromLibrary(e, _addedMap)).toList();
          _total = total;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '加载应用列表失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCat(String cat) {
    if (_activeCat == cat) return;
    setState(() {
      _activeCat = cat;
      _page = 1;
    });
    _loadApps();
  }

  void _handleSearch() {
    setState(() => _page = 1);
    _loadApps();
  }

  // ===== 添加 / 取消添加 =====

  Future<void> _handleAdd(AppCenterItem item) async {
    if (item.busy) return;
    setState(() => item.busy = true);
    try {
      final refId = await ref.read(applicationApiProvider).addReference(
            groupId: widget.groupId,
            applicationId: item.applicationId,
          );
      if (!mounted) return;
      showTopNotice(context, '已添加，可到「已添加应用」中配置',
          level: NoticeLevel.success);
      setState(() {
        item.added = true;
        item.refId = refId;
        _addedMap[item.applicationId] = refId;
      });
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '添加失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => item.busy = false);
    }
  }

  Future<void> _handleRemove(AppCenterItem item) async {
    if (item.busy) return;
    final refId = item.refId ?? _addedMap[item.applicationId];
    if (refId == null) {
      showTopNotice(context, '未找到引用记录，请刷新后重试',
          level: NoticeLevel.warning);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消添加'),
        content: Text('确定取消添加「${item.name}」吗？已配置的策略将一并失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => item.busy = true);
    try {
      await ref.read(applicationApiProvider).deleteReference(refId);
      if (!mounted) return;
      showTopNotice(context, '已取消添加', level: NoticeLevel.success);
      _addedMap.remove(item.applicationId);
      if (_activeCat == _catAdded) {
        // 已添加 tab：当前页只剩这一条且非第 1 页时回退一页，避免空页
        if (_apps.length == 1 && _page > 1) _page--;
        await _loadApps();
      } else {
        setState(() {
          item.added = false;
          item.refId = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotice(context, '取消添加失败: $e', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => item.busy = false);
    }
  }

  // ===== 策略配置 =====

  void _handleConfig(AppCenterItem item) {
    showAdaptive<bool>(
      context,
      (_) => PolicyConfigDialog(
        applicationId: item.applicationId,
        applicationName: item.name,
        merchantId: widget.merchantId,
        merchantName: widget.merchantName,
        groupId: widget.groupId,
      ),
      routeName: '/dialog/app-policy-config',
    );
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final isNarrow = context.isNarrow;
    if (isNarrow) {
      return Column(
        children: [
          _buildCatChips(),
          _buildToolbar(),
          Expanded(child: _buildGridArea()),
          _buildPager(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 180, child: _buildCatSidebar()),
        const VerticalDivider(width: 1, color: Color(0xFFF0F0F0)),
        Expanded(
          child: Column(
            children: [
              _buildToolbar(),
              Expanded(child: _buildGridArea()),
              _buildPager(),
            ],
          ),
        ),
      ],
    );
  }

  // 左侧分类（宽屏）
  Widget _buildCatSidebar() {
    Widget catItem(String key, String name) {
      final active = _activeCat == key;
      return InkWell(
        onTap: () => _selectCat(key),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          color: active ? const Color(0xFFEFF6FF) : null,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: active ? AppColors.iosBlue : const Color(0xFF4B5563),
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        catItem(_catAdded, '已添加应用'),
        catItem(_catAll, '全部应用'),
        const Divider(height: 16, indent: 14, endIndent: 14),
        for (final c in _categories) catItem('${c.id}', c.name),
        if (_categories.isEmpty)
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              '暂无分类',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }

  // 顶部分类 chips（窄屏）
  Widget _buildCatChips() {
    Widget chip(String key, String name) {
      final active = _activeCat == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(name, style: const TextStyle(fontSize: 12)),
          selected: active,
          onSelected: (_) => _selectCat(key),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            chip(_catAdded, '已添加应用'),
            chip(_catAll, '全部应用'),
            for (final c in _categories) chip('${c.id}', c.name),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextField(
                controller: _keywordCtrl,
                decoration: InputDecoration(
                  hintText: '输入应用名称',
                  hintStyle:
                      TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  prefixIcon: const Icon(LucideIcons.search, size: 16),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _handleSearch(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: _handleSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iosBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('查询'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridArea() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_apps.isEmpty) {
      return Center(
        child: Text(
          _activeCat == _catAdded ? '本分组暂无已添加的应用' : '暂无应用',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 168,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _apps.length,
      itemBuilder: (context, index) => _buildAppCard(_apps[index]),
    );
  }

  Widget _buildAppCard(AppCenterItem item) {
    final perm = ref.watch(permissionProvider);
    final canAdd = perm.hasDetailPermissionById(kPermNetbarAppAdd);
    final canConfig = perm.hasDetailPermissionById(kPermNetbarAppConfig);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildAppIcon(item),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          // 给右上角添加角标让位
                          padding: const EdgeInsets.only(right: 24),
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        if (item.tag.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              item.tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  item.desc.isNotEmpty ? item.desc : '暂无介绍',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
              // 已添加才可配置策略
              if (item.added && canConfig)
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: OutlinedButton(
                    onPressed: () => _handleConfig(item),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.iosBlue,
                      side: BorderSide(
                          color: AppColors.iosBlue.withValues(alpha: 0.5)),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    child:
                        const Text('策略配置', style: TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
          // 右上角：添加 / 已添加（取消）角标
          Positioned(top: 0, right: 0, child: _buildAddBadge(item, canAdd)),
        ],
      ),
    );
  }

  Widget _buildAppIcon(AppCenterItem item) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: item.icon.isNotEmpty
          ? Image.network(
              item.icon,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _iconPlaceholder(),
            )
          : _iconPlaceholder(),
    );
  }

  Widget _iconPlaceholder() {
    return Center(
      child: Icon(LucideIcons.package, size: 20, color: Colors.grey.shade400),
    );
  }

  Widget _buildAddBadge(AppCenterItem item, bool canAdd) {
    if (item.busy) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: Padding(
          padding: EdgeInsets.all(3),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!item.added) {
      // 未添加：有权限显示「＋」，无权限不显示
      if (!canAdd) return const SizedBox.shrink();
      return _badgeButton(
        icon: LucideIcons.plus,
        color: AppColors.iosBlue,
        tooltip: '添加到本分组',
        onTap: () => _handleAdd(item),
      );
    }
    // 已添加：✓ 角标；有权限可点击取消，无权限只读
    return _badgeButton(
      icon: LucideIcons.check,
      color: AppColors.green,
      tooltip: canAdd ? '取消添加' : '已添加',
      onTap: canAdd ? () => _handleRemove(item) : null,
    );
  }

  Widget _badgeButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildPager() {
    final maxPage = _total <= 0 ? 1 : ((_total + _size - 1) ~/ _size);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Text(
            '共 $_total 条',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const Spacer(),
          DropdownButton<int>(
            value: _size,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 条/页')),
              DropdownMenuItem(value: 20, child: Text('20 条/页')),
              DropdownMenuItem(value: 50, child: Text('50 条/页')),
              DropdownMenuItem(value: 100, child: Text('100 条/页')),
            ],
            onChanged: (v) {
              if (v == null || v == _size) return;
              setState(() {
                _size = v;
                _page = 1;
              });
              _loadApps();
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _page > 1
                ? () {
                    setState(() => _page--);
                    _loadApps();
                  }
                : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: '上一页',
          ),
          Text(
            '$_page / $maxPage',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          IconButton(
            onPressed: _page < maxPage
                ? () {
                    setState(() => _page++);
                    _loadApps();
                  }
                : null,
            icon: const Icon(LucideIcons.chevronRight, size: 18),
            visualDensity: VisualDensity.compact,
            tooltip: '下一页',
          ),
        ],
      ),
    );
  }
}
