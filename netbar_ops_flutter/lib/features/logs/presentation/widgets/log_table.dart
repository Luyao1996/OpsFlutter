import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/log_types.dart';

class LogTable extends StatelessWidget {
  final List<LogEntry> logs;
  final ValueChanged<LogEntry> onViewDetail;

  const LogTable({
    super.key,
    required this.logs,
    required this.onViewDetail,
  });

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.monitor, size: 48, color: Colors.grey.shade200),
            const SizedBox(height: 16),
            Text('暂无符合条件的日志记录', style: TextStyle(color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50.withOpacity(0.5),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: _buildHeaderCell('时间 / ID')),
                Expanded(flex: 3, child: _buildHeaderCell('操作人')),
                Expanded(flex: 2, child: _buildHeaderCell('模块')),
                Expanded(flex: 4, child: _buildHeaderCell('操作内容')),
                Expanded(flex: 2, child: _buildHeaderCell('状态')),
                SizedBox(width: 60, child: _buildHeaderCell('操作', align: TextAlign.right)),
              ],
            ),
          ),
          // List
          Expanded(
            child: ListView.separated(
              itemCount: logs.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
              itemBuilder: (context, index) {
                final log = logs[index];
                return _buildRow(log);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildRow(LogEntry log) {
    return InkWell(
      onTap: () => onViewDetail(log),
      hoverColor: Colors.grey.shade50.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Time / ID
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.timestamp, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87, fontFamily: 'monospace')),
                  const SizedBox(height: 2),
                  Text(log.id, style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontFamily: 'monospace')),
                ],
              ),
            ),
            // User
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.grey.shade200, Colors.grey.shade300],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      log.user.name.isNotEmpty ? log.user.name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.user.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87)),
                      Text(log.user.role, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                ],
              ),
            ),
            // Module
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    moduleLabels[log.module] ?? '',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
                  ),
                ),
              ),
            ),
            // Content
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log.action, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.black87), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(log.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Status
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildStatusBadge(log.level),
              ),
            ),
            // Action
            SizedBox(
              width: 60,
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => onViewDetail(log),
                  icon: const Icon(LucideIcons.eye, size: 18),
                  color: Colors.grey.shade400,
                  tooltip: '查看详情',
                  style: IconButton.styleFrom(
                    hoverColor: AppColors.iosBlue.withOpacity(0.1),
                    foregroundColor: AppColors.iosBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(LogLevel level) {
    final config = levelConfig[level]!;
    final color = config['color'] as Color;
    final bg = config['bg'] as Color;
    final label = config['label'] as String;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}
