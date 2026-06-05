import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../data/netbar_api.dart';
import '../edit_netbar_modal.dart';
import 'remote_wake_modal.dart';

class NetbarGridView extends StatelessWidget {
  final List<Netbar> netbars;
  final Future<void> Function() onRefresh;

  const NetbarGridView({
    super.key,
    required this.netbars,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Adjust grid columns based on width
        int crossAxisCount = 1;
        if (width >= 1600) {
          crossAxisCount = 5;
        } else if (width >= 1300) {
          crossAxisCount = 4;
        } else if (width >= 1000) {
          crossAxisCount = 3;
        } else if (width >= 700) {
          crossAxisCount = 2;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: 0.7, // Adjust as needed
          ),
          itemCount: netbars.length,
          itemBuilder: (context, index) {
            return _NetbarGridCard(
              netbar: netbars[index],
              onRefresh: onRefresh,
            );
          },
        );
      },
    );
  }
}

class _NetbarGridCard extends StatelessWidget {
  final Netbar netbar;
  final Future<void> Function() onRefresh;

  const _NetbarGridCard({required this.netbar, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isOnline = netbar.status == 'online';

    return InkWell(
      onTap: () {
        // TODO: Implement Wake/Monitor action
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isOnline ? Colors.grey.shade100 : Colors.grey.shade200,
          ),
          boxShadow: isOnline ? AppShadows.apple : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Image / Placeholder
            Expanded(
              flex: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (netbar.screenshotUrl != null &&
                      netbar.screenshotUrl!.isNotEmpty)
                    Image.network(
                      netbar.screenshotUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  else
                    _buildPlaceholder(),

                  // Status Badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOnline
                            ? Colors.green.withOpacity(0.9)
                            : Colors.grey.shade800.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnline
                              ? Colors.green.shade400
                              : Colors.grey.shade700,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isOnline
                                ? LucideIcons.checkCircle2
                                : LucideIcons.xCircle,
                            size: 12,
                            color: isOnline
                                ? Colors.white
                                : Colors.grey.shade300,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isOnline
                                  ? Colors.white
                                  : Colors.grey.shade300,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (netbar.remoteStatus?.isActive == true)
                    Positioned(
                      top: 12,
                      right:
                          12, // Adjusted to right or center based on Vue design
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 6,
                              height: 6,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '正在远程: ${netbar.remoteStatus?.currentOperator ?? ''}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Info
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                netbar.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '#${netbar.id}',
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                netbar.group,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${netbar.terminalCount} 终端',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Resource Bars
                        _buildResourceBar(
                          LucideIcons.cpu,
                          netbar.serverMetrics?.cpuUsage ?? 0,
                        ),
                        const SizedBox(height: 6),
                        _buildResourceBar(
                          LucideIcons.hardDrive,
                          netbar.serverMetrics?.ramUsage ?? 0,
                        ),
                      ],
                    ),

                    // Bottom Row
                    Column(
                      children: [
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (netbar.remoteStatus?.isActive == true)
                                  Text(
                                    '远程中: ${netbar.remoteStatus?.currentOperator}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.purple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                else
                                  Text(
                                    '上次远程: ${netbar.remoteStatus?.lastSession?.time.split(' ')[0] ?? '-'}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                              ],
                            ),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final changed = await showAdaptive<bool>(
                                      context,
                                      (context) =>
                                          EditNetbarModal(netbar: netbar),
                                      routeName: '/dialog/edit-netbar',
                                    );
                                    // 等待刷新落地，消除"保存后重开仍旧值"竞态
                                    if (changed == true) await onRefresh();
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      LucideIcons.settings,
                                      size: 16,
                                      color: Colors.grey.shade400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                InkWell(
                                  onTap: () {
                                    showAdaptive<void>(
                                      context,
                                      (context) => RemoteWakeModal(
                                        netbarName: netbar.name,
                                      ),
                                      routeName: '/dialog/remote-wake',
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      LucideIcons.monitorPlay,
                                      size: 16,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: Icon(LucideIcons.signal, size: 32, color: Colors.grey.shade600),
    );
  }

  Widget _buildResourceBar(IconData icon, int percentage) {
    Color color = Colors.blue;
    if (percentage >= 90) {
      color = Colors.red;
    } else if (percentage >= 70)
      color = Colors.orange;

    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percentage / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 24,
          child: Text(
            '$percentage%',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
