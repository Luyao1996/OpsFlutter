import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/responsive/responsive.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/search_field.dart';
import '../data/netbar_api.dart';
import '../data/netbar_pinyin_matcher.dart';
import 'widgets/create_netbar_modal.dart';
import 'widgets/netbar_list_view.dart';
import 'widgets/netbar_grid_view.dart';

final netbarListProvider = FutureProvider.autoDispose<List<Netbar>>((
  ref,
) async {
  final api = NetbarApi();
  return api.getList();
});

class NetbarListPage extends ConsumerStatefulWidget {
  const NetbarListPage({super.key});

  @override
  ConsumerState<NetbarListPage> createState() => _NetbarListPageState();
}

class _NetbarListPageState extends ConsumerState<NetbarListPage> {
  String _searchQuery = '';
  final String _selectedGroup = '全部分组';
  bool _isListView = true;

  @override
  Widget build(BuildContext context) {
    final netbarsAsync = ref.watch(netbarListProvider);
    final isNarrow = context.isNarrow;
    final padding = context.isPhone ? 16.0 : 24.0;

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
                      _buildViewToggle(),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SearchField(
                        hintText: '搜索名称、ID、拼音或Token...',
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildViewToggle(),
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
              error: (err, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('加载失败: $err'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.refresh(netbarListProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
              data: (netbars) {
                // Filter logic: 三级匹配 (name → pinyin_full → pinyin) + id/token/group 兜底
                final filtered = netbars
                    .where((n) => NetbarMatcher.match(n, _searchQuery))
                    .toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('未找到匹配的网吧'));
                }

                return _isListView
                    ? NetbarListView(
                        netbars: filtered,
                        onRefresh: () => ref.refresh(netbarListProvider),
                      )
                    : NetbarGridView(
                        netbars: filtered,
                        onRefresh: () => ref.refresh(netbarListProvider),
                      );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTitle(AsyncValue<List<Netbar>> netbarsAsync) {
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
          data: (netbars) {
            final online = netbars.where((n) => n.status == 'online').length;
            final offline = netbars.length - online;
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        const SizedBox(width: 12),
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
