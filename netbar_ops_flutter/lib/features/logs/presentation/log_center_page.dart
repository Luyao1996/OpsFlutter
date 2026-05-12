import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_theme.dart';
import 'operation_log_view.dart';
import 'system_logs_page.dart';

/// 日志中心 —— 业务操作日志（默认） + 系统日志 的 Tab 容器。
///
/// 子路由：
/// - `/log-center/operation` → 操作日志
/// - `/log-center/system`    → 系统日志
class LogCenterPage extends StatefulWidget {
  /// 'operation' 或 'system'，默认 'operation'
  final String initialTab;

  const LogCenterPage({super.key, this.initialTab = 'operation'});

  @override
  State<LogCenterPage> createState() => _LogCenterPageState();
}

class _LogCenterPageState extends State<LogCenterPage> {
  static const _tabs = <_TabSpec>[
    _TabSpec(key: 'operation', label: '操作日志', icon: LucideIcons.scrollText),
    _TabSpec(key: 'system', label: '系统日志', icon: LucideIcons.fileText),
  ];

  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = _indexOf(widget.initialTab);
  }

  @override
  void didUpdateWidget(covariant LogCenterPage old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) {
      setState(() => _currentIndex = _indexOf(widget.initialTab));
    }
  }

  int _indexOf(String key) {
    final i = _tabs.indexWhere((t) => t.key == key);
    return i < 0 ? 0 : i;
  }

  void _select(int i) {
    if (i == _currentIndex) return;
    setState(() => _currentIndex = i);
    // 同步 URL（避免 import go_router 造成耦合，这里仅本地状态切换；
    // 路由层会把 /log-center/<key> 都映射到本页面并设置 initialTab）。
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = context.isPhone;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isPhone ? 12 : 24,
              vertical: isPhone ? 12 : 16,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: isPhone
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        '日志中心',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSwitcher(expand: true)),
                    ],
                  )
                : Row(
                    children: [
                      const Text(
                        '日志中心',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 24),
                      _buildSwitcher(),
                    ],
                  ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                OperationLogView(),
                SystemLogsPage(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [expand]=true 时每个按钮 Expanded 平分宽度（手机端整行场景）；
  /// 否则 mainAxisSize.min，胶囊仅占按钮内容宽度（PC 端贴在标题右侧）。
  Widget _buildSwitcher({bool expand = false}) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: List.generate(_tabs.length, (i) {
          final t = _tabs[i];
          final selected = i == _currentIndex;
          final btn = _PillButton(
            label: t.label,
            icon: t.icon,
            selected: selected,
            expand: expand,
            onTap: () => _select(i),
          );
          return expand ? Expanded(child: btn) : btn;
        }),
      ),
    );
  }
}

class _TabSpec {
  final String key;
  final String label;
  final IconData icon;
  const _TabSpec({required this.key, required this.label, required this.icon});
}

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool expand;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        // expand=true 时让胶囊背景撑满 Expanded 宽度
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.iosBlue : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.iosBlue : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
