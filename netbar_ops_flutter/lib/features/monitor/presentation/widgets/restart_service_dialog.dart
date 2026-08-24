import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../shared/widgets/responsive_dialog_scaffold.dart';

/// 可重启的服务项（对标 Vue 端 RestartServiceDialog.vue 的 SERVICES 表）
class RestartServiceOption {
  final String type; // WS data.type
  final String name; // 服务中文名（toast / operationLog 文案用）
  final String desc;
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;

  const RestartServiceOption({
    required this.type,
    required this.name,
    required this.desc,
    required this.icon,
    required this.gradientStart,
    required this.gradientEnd,
  });
}

const List<RestartServiceOption> _kServices = [
  RestartServiceOption(
    type: 'frpc',
    name: '反代服务',
    desc: '远程通信、反向代理转发',
    icon: LucideIcons.arrowLeftRight,
    gradientStart: Color(0xFF3B82F6),
    gradientEnd: Color(0xFF6366F1),
  ),
  RestartServiceOption(
    type: 'client',
    name: '协助服务',
    desc: '远程协助、客户端代理',
    icon: LucideIcons.screenShare,
    gradientStart: Color(0xFF10B981),
    gradientEnd: Color(0xFF14B8A6),
  ),
  RestartServiceOption(
    type: 'router',
    name: '路由服务',
    desc: '网关路由转发',
    icon: LucideIcons.router,
    gradientStart: Color(0xFFF59E0B),
    gradientEnd: Color(0xFFF97316),
  ),
  RestartServiceOption(
    type: 'gamelibrary',
    name: '游戏库服务',
    desc: '游戏资源库分发',
    icon: LucideIcons.gamepad2,
    gradientStart: Color(0xFF8B5CF6),
    gradientEnd: Color(0xFFEC4899),
  ),
  RestartServiceOption(
    type: 'p2p',
    name: 'P2P服务',
    desc: 'P2P 传输加速',
    icon: LucideIcons.share2,
    gradientStart: Color(0xFF06B6D4),
    gradientEnd: Color(0xFF3B82F6),
  ),
  RestartServiceOption(
    type: 'appstore',
    name: '应用商店服务',
    desc: '应用商店本地服务',
    icon: LucideIcons.store,
    gradientStart: Color(0xFFEC4899),
    gradientEnd: Color(0xFFF43F5E),
  ),
  RestartServiceOption(
    type: 'httpserver',
    name: 'HTTP服务',
    desc: '本地 HTTP 接口服务',
    icon: LucideIcons.globe,
    gradientStart: Color(0xFF22C55E),
    gradientEnd: Color(0xFF84CC16),
  ),
];

/// 'main' 会重启服务端主程序自身，期间整机短暂离线，风险最高——
/// Web 端以 ?debug=1 隐藏该项，Flutter 以 kDebugMode 等价：release 包不暴露入口
const RestartServiceOption _kMainService = RestartServiceOption(
  type: 'main',
  name: '主程序',
  desc: '重启服务端主程序自身',
  icon: LucideIcons.power,
  gradientStart: Color(0xFFEF4444),
  gradientEnd: Color(0xFFB91C1C),
);

/// 重启服务选择弹窗（对标 Vue 端 RestartServiceDialog.vue）。
/// 点击某项 → 简单确认 → `pop(该项)`，实际下发由调用方执行（复用详情页
/// 既有的 _restartService：同网吧校验、WS 协议、操作日志都在那边）。
class RestartServiceDialog extends StatelessWidget {
  const RestartServiceDialog({super.key});

  Future<void> _handleTap(BuildContext context, RestartServiceOption svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重启${svc.name}'),
        content: Text('确认重启${svc.name}吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Navigator.of(context).pop(svc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = [
      ..._kServices,
      if (kDebugMode) _kMainService,
    ];
    return ResponsiveDialogScaffold(
      title: '重启服务',
      maxWidth: 600,
      body: LayoutBuilder(builder: (context, constraints) {
        // 对标 Web 端 2 列网格；窄屏（手机全屏页）退化为单列保证描述可读
        final twoColumns = constraints.maxWidth >= 440;
        if (!twoColumns) {
          return Column(
            children: [
              for (var i = 0; i < services.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _ServiceCard(service: services[i], onTap: _handleTap),
              ],
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < services.length; i += 2) {
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ServiceCard(service: services[i], onTap: _handleTap)),
              const SizedBox(width: 10),
              Expanded(
                child: i + 1 < services.length
                    ? _ServiceCard(service: services[i + 1], onTap: _handleTap)
                    : const SizedBox(),
              ),
            ],
          ));
          if (i + 2 < services.length) rows.add(const SizedBox(height: 10));
        }
        return Column(children: rows);
      }),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final RestartServiceOption service;
  final void Function(BuildContext context, RestartServiceOption svc) onTap;

  const _ServiceCard({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onTap(context, service),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [service.gradientStart, service.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(service.icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      service.desc,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(LucideIcons.chevronRight, size: 16, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
