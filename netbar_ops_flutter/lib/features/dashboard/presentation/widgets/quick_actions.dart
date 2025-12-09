import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/dashboard_api.dart';

class QuickActions extends ConsumerStatefulWidget {
  const QuickActions({super.key});

  @override
  ConsumerState<QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends ConsumerState<QuickActions> {
  bool _isOperating = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.sm,
        border: Border.all(color: Colors.white),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '快捷操作',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          _buildActionButton(
            context,
            title: '全部重启',
            subtitle: '重启所有离线服务',
            icon: LucideIcons.activity,
            color: Colors.blue,
            onTap: () => _handleRestartAll(context),
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            context,
            title: '网络诊断',
            subtitle: '检测节点连通性',
            icon: LucideIcons.wifi,
            color: Colors.orange,
            onTap: () => _handleNetworkDiagnose(context),
          ),

          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Colors.blue, Colors.indigo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '系统版本',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'v2.5.0 Pro',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已是最新版本',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  right: -16,
                  bottom: -16,
                  child: Icon(
                    LucideIcons.activity,
                    size: 80,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: color.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleRestartAll(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: '确认重启',
      content: '确定要重启所有离线服务吗？此操作将影响所有终端。',
      confirmText: '确认重启',
      confirmColor: Colors.blue,
    );

    if (confirmed == true && mounted) {
      setState(() => _isOperating = true);
      try {
        final api = ref.read(dashboardApiProvider);
        final response = await api.restartAll();
        if (mounted) {
          _showResultDialog(
            context,
            '操作成功',
            '${response.message}\n目标终端数: ${response.targetCount}\n预计耗时: ${response.estimatedTime}',
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isOperating = false);
      }
    }
  }

  Future<void> _handleNetworkDiagnose(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: '网络诊断',
      content: '确定要启动网络诊断吗？这将检测所有节点的连通性。',
      confirmText: '开始诊断',
      confirmColor: Colors.orange,
    );

    if (confirmed == true && mounted) {
      setState(() => _isOperating = true);
      try {
        final api = ref.read(dashboardApiProvider);
        final response = await api.networkDiagnose();
        if (mounted) {
          _showResultDialog(
            context,
            '诊断完成',
            '${response.message}\n检测节点数: ${response.nodeCount}\n检测项目: ${response.checkItems.join(', ')}\n预计耗时: ${response.estimatedTime}',
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('诊断失败: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isOperating = false);
      }
    }
  }

  Future<bool?> _showConfirmDialog(
    BuildContext context,
    {
    required String title,
    required String content,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showResultDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
