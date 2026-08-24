import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/providers/permission_provider.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/search_field.dart';
import '../../../../shared/widgets/app_error_view.dart';
import '../data/edition_meta.dart';
import '../data/netbar_api.dart';
import '../data/netbar_list_provider.dart';
import '../data/netbar_pinyin_matcher.dart';
import '../data/version_compare.dart';
import 'widgets/create_netbar_modal.dart';
import 'widgets/netbar_list_view.dart';
import 'widgets/netbar_grid_view.dart';
import 'widgets/update_record_dialog.dart';

class NetbarListPage extends ConsumerStatefulWidget {
  const NetbarListPage({super.key});

  @override
  ConsumerState<NetbarListPage> createState() => _NetbarListPageState();
}

class _NetbarListPageState extends ConsumerState<NetbarListPage> {
  String _searchQuery = '';
  final String _selectedGroup = '全部分组';
  /// 版本号筛选，null = 全部
  String? _filterVersion;
  /// 版本类型（更新通道）筛选，null = 全部，对齐 web form.edition
  String? _filterEdition;
  bool _isListView = true;

  @override
  Widget build(BuildContext context) {
    final netbarsAsync = ref.watch(netbarListProvider);
    final isNarrow = context.isNarrow;
    final padding = context.isPhone ? 16.0 : 24.0;
    // 版本号选项依赖异步数据；加载中/失败时给空列表，下拉退化成只有「全部」且不可点
    final versionOptions = netbarsAsync.maybeWhen(
      data: _collectVersions,
      orElse: () => const <String>[],
    );
    // 刷新后原先选中的版本可能已经不在数据里，统一回落到「全部」，
    // 避免下拉显示「全部」而列表还在按一个消失了的版本过滤
    final activeVersion =
        versionOptions.contains(_filterVersion) ? _filterVersion : null;

    return Scaffold(
      backgroundColor: AppColors.iosBg,
      body: Column(
        children: [
          // Header Section
          Container(
            padding: EdgeInsets.all(padding),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Title & Stats
                if (!isNarrow)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildHeaderTitle(netbarsAsync),
                      _buildHeaderActions(),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderTitle(netbarsAsync),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [_buildHeaderActions()],
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                // Bottom Row: Search & Filters
                if (!isNarrow)
                  Row(
                    children: [
                      Expanded(
                        child: SearchField(
                          hintText: '搜索名称、ID、拼音或Token...',
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 140,
                        child: _buildVersionFilter(versionOptions, activeVersion),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 140,
                        child: _buildEditionFilter(),
                      ),
                      const SizedBox(width: 16),
                      _buildViewToggle(),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 视图切换挪到搜索框同行，下一行整行让给两个筛选下拉等分，
                      // 否则 版本号+版本类型+切换 三件套挤一行窄屏必溢出
                      Row(
                        children: [
                          Expanded(
                            child: SearchField(
                              hintText: '搜索名称、ID、拼音或Token...',
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _buildViewToggle(),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildVersionFilter(
                                versionOptions, activeVersion),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: _buildEditionFilter()),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // List Content
          Expanded(
            child: netbarsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => AppErrorView(
                error: err,
                onRetry: () => ref.invalidate(netbarListProvider),
              ),
              data: (response) {
                // Filter logic: 三级匹配 (name → pinyin_full → pinyin) + id/token/group 兜底
                final filtered = response.merchants
                    .where((n) =>
                        NetbarMatcher.match(n, _searchQuery) &&
                        (activeVersion == null || n.version == activeVersion) &&
                        (_filterEdition == null ||
                            n.edition == _filterEdition))
                    .toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('未找到匹配的网吧'));
                }

                return _isListView
                    ? NetbarListView(
                        netbars: filtered,
                        // await .future 等刷新完成，确保重新打开编辑显示新值
                        onRefresh: () => ref.refresh(netbarListProvider.future),
                      )
                    : NetbarGridView(
                        netbars: filtered,
                        onRefresh: () => ref.refresh(netbarListProvider.future),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 去重收集版本号，按语义化版本降序（"1.10" 要排在 "1.2" 前面，不能按字符串排）
  List<String> _collectVersions(NetbarListResponse response) {
    final set = <String>{};
    for (final n in response.merchants) {
      final v = n.version;
      if (v != null && v.isNotEmpty) set.add(v);
    }
    final list = set.toList();
    list.sort((a, b) => compareVersion(a, b, desc: true));
    return list;
  }

  Widget _buildVersionFilter(List<String> options, String? value) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('全部版本', style: TextStyle(fontSize: 14)),
        ),
        ...options.map((v) => DropdownMenuItem<String?>(
              value: v,
              child: Text('v$v',
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: options.isEmpty
          ? null
          : (v) => setState(() => _filterVersion = v),
    );
  }

  /// 版本类型（更新通道）筛选，做法复用 _buildVersionFilter；
  /// 选项本地写死（对齐 web EDITION_OPTIONS），不依赖异步数据，
  /// 空值项文案带"类型"限定，避免与旁边"全部版本"混淆
  Widget _buildEditionFilter() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return DropdownButtonFormField<String?>(
      value: _filterEdition,
      isExpanded: true,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.iosBlue, width: 2),
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('全部类型', style: TextStyle(fontSize: 14)),
        ),
        ...kEditionOptions.map((m) => DropdownMenuItem<String?>(
              value: m.value,
              child: Text(m.label, style: const TextStyle(fontSize: 14)),
            )),
      ],
      onChanged: (v) => setState(() => _filterEdition = v),
    );
  }

  Widget _buildHeaderTitle(AsyncValue<NetbarListResponse> netbarsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '网吧管理',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        netbarsAsync.maybeWhen(
          data: (response) {
            final summary = response.summary;
            final online = summary?.onlineCount ??
                response.merchants.where((n) => n.status == 'online').length;
            final offline =
                summary?.offlineCount ?? (response.merchants.length - online);
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildStatusBadge(Colors.green, '$online 在线'),
                _buildStatusBadge(Colors.grey, '$offline 离线'),
              ],
            );
          },
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildHeaderActions() {
    final perm = ref.watch(permissionProvider);
    // 三个按钮窄屏一行放不下，Row 不折行会溢出，改 Wrap 自动换行
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        // 权限条件对齐 web NetbarPage 的 canUpdate（与「批量更新程序」入口同一权限点）
        if (perm.hasDetailPermission('更新'))
          ElevatedButton.icon(
            onPressed: () {
              showAdaptive<void>(
                context,
                (context) => const UpdateRecordDialog(),
                routeName: '/dialog/update-record',
              );
            },
            icon: const Icon(LucideIcons.history, size: 16),
            label: const Text('更新记录'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              foregroundColor: Colors.black87,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ElevatedButton.icon(
          onPressed: () {
            // TODO: Implement Export
          },
          icon: const Icon(LucideIcons.download, size: 16),
          label: const Text('导出CSV'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade100,
            foregroundColor: Colors.black87,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () {
            showAdaptive<bool>(
              context,
              (context) => const CreateNetbarModal(),
              routeName: '/dialog/create-netbar',
            ).then((created) {
              if (created == true) {
                ref.refresh(netbarListProvider);
              }
            });
          },
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('新增网吧'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewToggleButton(true, LucideIcons.list),
          _buildViewToggleButton(false, LucideIcons.layoutGrid),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(Color color, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton(bool isList, IconData icon) {
    final isSelected = _isListView == isList;
    return InkWell(
      onTap: () => setState(() => _isListView = isList),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppColors.primary : Colors.grey.shade500,
        ),
      ),
    );
  }
}
