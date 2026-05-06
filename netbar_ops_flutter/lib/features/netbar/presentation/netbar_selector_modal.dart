import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/top_notice.dart';
import '../data/netbar_api.dart';
import '../data/netbar_pinyin_matcher.dart';
import 'group_picker.dart';
import 'edit_netbar_modal.dart';

/// 网吧列表 Provider（返回完整响应，包含 merchants + groups）
final netbarListProvider = FutureProvider.autoDispose<NetbarListResponse>((ref) async {
  final api = NetbarApi();
  return api.getListFull();
});

/// 网吧选择弹窗 - 对应 Vue 的 NetbarSelectorModal.vue
class NetbarSelectorModal extends ConsumerStatefulWidget {
  final int? selectedId;
  final Function(int id, String name, String status, {String? subdomainFull, String? groupName})? onSelect;
  final bool isMobile;

  const NetbarSelectorModal({
    super.key,
    this.selectedId,
    this.onSelect,
    this.isMobile = false,
  });

  @override
  ConsumerState<NetbarSelectorModal> createState() => _NetbarSelectorModalState();
}

class _NetbarSelectorModalState extends ConsumerState<NetbarSelectorModal> {
  String _searchQuery = '';
  String _selectedGroup = '全部分组';
  String _sortKey = 'id';
  bool _sortAsc = true;

  @override
  void initState() {
    super.initState();
    // 监听 Esc 关闭
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  void _handleSelect(Netbar netbar) {
    widget.onSelect?.call(netbar.id, netbar.name, netbar.status, subdomainFull: netbar.subdomainFull, groupName: netbar.group);
    Navigator.of(context).pop();
  }

  void _handleEdit(Netbar netbar) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (context) => EditNetbarModal(
        netbar: netbar,
        onSaved: () => ref.invalidate(netbarListProvider),
      ),
    );
  }

  List<Netbar> _filterAndSort(List<Netbar> netbars) {
    var result = netbars.where((n) {
      if (_selectedGroup != '全部分组' && n.group != _selectedGroup) return false;
      return NetbarMatcher.match(n, _searchQuery);
    }).toList();

    result.sort((a, b) {
      int cmp = 0;
      switch (_sortKey) {
        case 'id':
          cmp = a.id.compareTo(b.id);
        case 'name':
          cmp = a.name.compareTo(b.name);
        case 'terminalCount':
          cmp = a.terminalCount.compareTo(b.terminalCount);
        case 'status':
          cmp = a.status.compareTo(b.status);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final responseAsync = ref.watch(netbarListProvider);
    final netbarsAsync = responseAsync.whenData((r) => r.merchants);
    final size = MediaQuery.of(context).size;

    if (widget.isMobile) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: _buildMobileFilter(responseAsync),
              ),
              Expanded(
                child: _buildMobileList(netbarsAsync),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width * 0.05,
        vertical: size.height * 0.05,
      ),
      child: Container(
        width: size.width * 0.9,
        height: size.height * 0.9,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.xl,
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildToolbar(),
            Expanded(child: _buildContent(netbarsAsync)),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('切换网吧', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (!widget.isMobile)
                  Text(
                    '选择您要管理的网吧终端，或点击编辑按钮修改网吧信息',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, size: 20, color: Colors.grey.shade400),
            hoverColor: Colors.grey.shade100,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 12),
          GroupPicker(
            selectedGroup: _selectedGroup,
            onSelect: (group) => setState(() => _selectedGroup = group),
            label: '分组',
          ),
          const SizedBox(width: 12),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return ElevatedButton.icon(
      onPressed: _handleAdd,
      icon: const Icon(LucideIcons.plus, size: 16),
      label: const Text('新增网吧'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iosBlue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }

  void _handleAdd() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (context) => EditNetbarModal(
        onSaved: () => ref.invalidate(netbarListProvider),
      ),
    );
  }

  Widget _buildMobileFilter(AsyncValue<NetbarListResponse> responseAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(),
        const SizedBox(height: 8),
        _buildGroupChips(responseAsync),
      ],
    );
  }

  Widget _buildGroupChips(AsyncValue<NetbarListResponse> responseAsync) {
    return responseAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (response) {
        final groupNames = response.groups.map((g) => g.name).toList();
        final allGroups = ['全部分组', ...groupNames];
        return SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: allGroups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final group = allGroups[index];
              final isSelected = _selectedGroup == group;
              return GestureDetector(
                onTap: () => setState(() => _selectedGroup = group),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.iosBlue : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    group,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: '搜索网吧名称...',
          hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          prefixIcon: Icon(LucideIcons.search, size: 16, color: Colors.grey.shade400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _buildMobileList(AsyncValue<List<Netbar>> netbarsAsync) {
    return netbarsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _buildError(err.toString()),
      data: (netbars) {
        final filtered = _filterAndSort(netbars);
        if (filtered.isEmpty) return _buildEmpty(noAccess: netbars.isEmpty);
        return ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
          itemBuilder: (context, index) {
            final netbar = filtered[index];
            final isSelected = netbar.id == widget.selectedId;
            return ListTile(
              title: Text(
                netbar.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.iosBlue : Colors.black,
                ),
              ),
              onTap: () => _handleSelect(netbar),
            );
          },
        );
      },
    );
  }

  Widget _buildContent(AsyncValue<List<Netbar>> netbarsAsync) {
    return netbarsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _buildError(err.toString()),
      data: (netbars) {
        final filtered = _filterAndSort(netbars);
        if (filtered.isEmpty) {
          return _buildEmpty(noAccess: netbars.isEmpty);
        }
        return _buildTable(filtered);
      },
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.alertTriangle, size: 28, color: Colors.red.shade400),
          ),
          const SizedBox(height: 16),
          Text('加载失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => ref.invalidate(netbarListProvider),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('重新加载'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty({required bool noAccess}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            noAccess ? LucideIcons.shieldOff : LucideIcons.search,
            size: 48,
            color: Colors.grey.shade200,
          ),
          const SizedBox(height: 16),
          Text(
            noAccess ? '暂无可访问网吧' : '未找到匹配的网吧',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
          if (noAccess) ...[
            const SizedBox(height: 6),
            Text(
              '请联系管理员将账号加入该网吧的分组',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable(List<Netbar> netbars) {
    if (widget.isMobile) {
      return ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: netbars.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final netbar = netbars[index];
          return ListTile(
            title: Text(netbar.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            onTap: () => _handleSelect(netbar),
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          // 表头
          _buildTableHeader(),
          // 列表
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: netbars.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade50),
              itemBuilder: (context, index) => _buildTableRow(netbars[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50.withValues(alpha: 0.9),
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          _buildHeaderCell('网吧名称 / ID', flex: 3, sortKey: 'id'),
          _buildHeaderCell('在线数/终端数', flex: 1, sortKey: 'terminalCount'),
          _buildHeaderCell('状态', flex: 1, sortKey: 'status'),
          _buildHeaderCell('所属分组', flex: 2),
          _buildHeaderCell('管理员', flex: 2),
          _buildHeaderCell('创建时间', flex: 2),
          _buildHeaderCell('Token', flex: 2),
          _buildHeaderCell('编辑', flex: 1),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String title, {int flex = 1, String? sortKey}) {
    final isActive = sortKey != null && _sortKey == sortKey;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: sortKey != null ? () {
          setState(() {
            if (_sortKey == sortKey) {
              _sortAsc = !_sortAsc;
            } else {
              _sortKey = sortKey;
              _sortAsc = true;
            }
          });
        } : null,
        child: MouseRegion(
          cursor: sortKey != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.iosBlue : Colors.grey.shade500,
                  letterSpacing: 0.5,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 4),
                Icon(
                  _sortAsc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                  size: 12,
                  color: AppColors.iosBlue,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableRow(Netbar netbar) {
    final isSelected = netbar.id == widget.selectedId;
    return _HoverableRow(
      isSelected: isSelected,
      onTap: () => _handleSelect(netbar),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // 网吧名称 / ID
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        netbar.id.toString(),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      netbar.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 在线数 / 终端数
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(LucideIcons.monitor, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      children: [
                        TextSpan(
                          text: netbar.terminalOnline.toString(),
                          style: TextStyle(
                            color: netbar.terminalOnline > 0
                                ? const Color(0xFF15803D)
                                : Colors.grey.shade400,
                          ),
                        ),
                        TextSpan(
                          text: '/${netbar.terminalCount}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 状态
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  _buildStatusBadge(netbar.status),
                ],
              ),
            ),
            // 分组
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      netbar.group,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            // 管理员
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(LucideIcons.users, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      netbar.admin,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // 创建时间
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(LucideIcons.clock, size: 12, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(netbar.createTime, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            // Token
            Expanded(
              flex: 2,
              child: _buildTokenCell(netbar.code),
            ),
            // 编辑按钮
            Expanded(
              flex: 1,
              child: Center(
                child: _EditButton(onTap: () => _handleEdit(netbar)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final isOnline = status == 'online';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isOnline ? const Color(0xFFDCFCE7) : Colors.grey.shade100, // green-100
        borderRadius: BorderRadius.circular(9999), // rounded-full
        border: Border.all(
          color: isOnline ? const Color(0xFFBBF7D0) : Colors.grey.shade200, // green-200
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOnline ? LucideIcons.checkCircle2 : LucideIcons.xCircle,
            size: 12,
            color: isOnline ? const Color(0xFF15803D) : Colors.grey.shade500, // green-700
          ),
          const SizedBox(width: 6),
          Text(
            isOnline ? '在线' : '离线',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isOnline ? const Color(0xFF15803D) : Colors.grey.shade600, // green-700
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenCell(String token) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: token));
        showTopNotice(
          context,
          'Token 已复制',
          level: NoticeLevel.success,
          duration: const Duration(seconds: 1),
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  token,
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.copy, size: 12, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.plus, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text('点击新增按钮添加网吧', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(width: 16),
          Icon(LucideIcons.edit2, size: 12, color: Colors.grey.shade400),
          const SizedBox(width: 6),
          Text('点击编辑按钮修改网吧信息', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const Spacer(),
          Text('Esc 关闭', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

/// 可悬停的行
class _HoverableRow extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Widget child;

  const _HoverableRow({
    required this.isSelected,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverableRow> createState() => _HoverableRowState();
}

class _HoverableRowState extends State<_HoverableRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: widget.isSelected
              ? AppColors.iosBlue.withValues(alpha: 0.1)
              : _isHovered
                  ? Colors.blue.shade50.withValues(alpha: 0.5)
                  : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 编辑按钮
class _EditButton extends StatefulWidget {
  final VoidCallback onTap;

  const _EditButton({required this.onTap});

  @override
  State<_EditButton> createState() => _EditButtonState();
}

class _EditButtonState extends State<_EditButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovered ? AppColors.iosBlue : const Color(0xFFEFF6FF), // blue-50
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? Colors.transparent : const Color(0xFFDBEAFE), // blue-100
            ),
            boxShadow: AppShadows.sm,
          ),
          child: Icon(
            LucideIcons.edit2,
            size: 16,
            color: _isHovered ? Colors.white : AppColors.iosBlue,
          ),
        ),
      ),
    );
  }
}
