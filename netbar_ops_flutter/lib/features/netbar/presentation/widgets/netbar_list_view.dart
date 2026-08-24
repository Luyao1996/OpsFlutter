import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/providers/permission_provider.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/edition_meta.dart';
import '../../data/netbar_api.dart';
import '../edit_netbar_modal.dart';
import 'remote_wake_modal.dart';
import 'update_edition_dialog.dart';

class NetbarListView extends StatelessWidget {
  final List<Netbar> netbars;
  final Future<void> Function() onRefresh;

  const NetbarListView({
    super.key,
    required this.netbars,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              _buildHeaderCell('网吧名称 / ID', flex: 3),
              _buildHeaderCell('终端', flex: 1),
              _buildHeaderCell('状态', flex: 1),
              _buildHeaderCell('远程状态', flex: 2),
              _buildHeaderCell('所属分组', flex: 1),
              _buildHeaderCell('管理员', flex: 1),
              _buildHeaderCell('创建时间', flex: 2),
              _buildHeaderCell('Access Token', flex: 2),
              _buildHeaderCell('操作', flex: 1, alignment: Alignment.centerRight),
            ],
          ),
        ),
        // List Body
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: netbars.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, indent: 24, endIndent: 24),
            itemBuilder: (context, index) {
              final netbar = netbars[index];
              return _NetbarListRow(netbar: netbar, onRefresh: onRefresh);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(
    String text, {
    int flex = 1,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500,
          ),
        ),
      ),
    );
  }
}

// 行内需要按权限显隐「更新程序」按钮，改成 ConsumerWidget 就地 watch，
// 免得往 NetbarListView 的公开构造里穿参
class _NetbarListRow extends ConsumerWidget {
  final Netbar netbar;
  final Future<void> Function() onRefresh;

  const _NetbarListRow({required this.netbar, required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perm = ref.watch(permissionProvider);
    return InkWell(
      onTap: () {
        // TODO: Implement Wake/Monitor action on row tap
      },
      hoverColor: Colors.blue.withOpacity(0.02),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Name / ID
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      netbar.id.toString(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      netbar.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // web 名称旁展示 vX.X；此前 Flutter 行内没有版本号，
                  // 补上才能给版本类型徽章一个"版本号附近"的锚点
                  if (netbar.version != null && netbar.version!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      'v${netbar.version}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                  if (netbar.edition != null && netbar.edition!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _editionBadge(netbar.edition),
                  ],
                ],
              ),
            ),
            // Terminal Count
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.monitor,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    netbar.terminalCount.toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            // Status
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: netbar.status == 'online'
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: netbar.status == 'online'
                        ? Colors.green.shade200
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      netbar.status == 'online'
                          ? LucideIcons.checkCircle2
                          : LucideIcons.xCircle,
                      size: 12,
                      color: netbar.status == 'online'
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      netbar.status == 'online' ? '在线' : '离线',
                      style: TextStyle(
                        fontSize: 12,
                        color: netbar.status == 'online'
                            ? Colors.green.shade700
                            : Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Remote Status
            Expanded(
              flex: 2,
              child: netbar.remoteStatus?.isActive == true
                  ? Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.cast,
                                size: 12,
                                color: Colors.purple.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '正在远程',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Icon(
                          LucideIcons.history,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          netbar.remoteStatus?.lastSession?.time.split(
                                ' ',
                              )[0] ??
                              '-',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
            ),
            // Group
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  netbar.group,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Admin
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.users,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      netbar.admin,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Create Time
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.clock,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    netbar.createTime,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade900),
                  ),
                ],
              ),
            ),
            // Token
            Expanded(
              flex: 2,
              child: InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: netbar.code));
                  showTopNotice(
                    context,
                    'Token已复制',
                    level: NoticeLevel.success,
                    duration: const Duration(seconds: 1),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.transparent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          netbar.code,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        LucideIcons.copy,
                        size: 12,
                        color: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Actions
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ActionButton(
                    icon: LucideIcons.monitorPlay,
                    onTap: () {
                      showAdaptive<void>(
                        context,
                        (context) =>
                            RemoteWakeModal(netbarName: netbar.name),
                        routeName: '/dialog/remote-wake',
                      );
                    },
                    tooltip: '控制台',
                  ),
                  // 权限点对齐 web canUpdate（与「批量更新程序」「更新记录」同一权限点）
                  if (perm.hasDetailPermission('更新')) ...[
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: LucideIcons.refreshCw,
                      onTap: () => runUpdateProgramFlow(
                        context,
                        netbar,
                        isTopManager: perm.isTopManager,
                      ),
                      tooltip: '更新程序',
                    ),
                  ],
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: LucideIcons.moreHorizontal,
                    onTap: () async {
                      final changed = await showAdaptive<bool>(
                        context,
                        (context) => EditNetbarModal(netbar: netbar),
                        routeName: '/dialog/edit-netbar',
                      );
                      // 等待刷新落地，消除"保存后重开仍旧值"竞态
                      if (changed == true) await onRefresh();
                    },
                    tooltip: '更多',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 版本类型小徽章，画法对齐 netbar_multi_select_table 的 _statusBadge
  Widget _editionBadge(String? edition) {
    final color = editionTagColor(edition);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        editionLabel(edition),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _ActionButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Icon(icon, size: 16, color: Colors.grey.shade600),
        ),
      ),
    );
  }
}
