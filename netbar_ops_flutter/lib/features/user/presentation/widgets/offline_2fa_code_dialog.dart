import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/security/builtin_totp_seed.dart';
import '../../../../core/security/server_clock.dart';
import '../../../../core/security/totp.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../../monitor/data/offline_2fa_audit.dart';

/// 离线 2FA 动态码。
///
/// 码由内置种子在本地算出（与终端无关，是通用码），每 [builtinSeedPeriod] 秒
/// 滚动一次。打开即自动写入剪贴板，跨时间窗后同步更新，保证用户在终端上粘贴时
/// 拿到的始终是当前有效的那个。
class Offline2faCodeDialog extends StatefulWidget {
  const Offline2faCodeDialog({super.key});

  @override
  State<Offline2faCodeDialog> createState() => _Offline2faCodeDialogState();
}

class _Offline2faCodeDialogState extends State<Offline2faCodeDialog> {
  Timer? _timer;
  String? _code;
  int _counter = -1;
  int _remain = 0;
  bool _seedFailed = false;

  @override
  void initState() {
    super.initState();
    _compute();
    if (_seedFailed) return;

    unawaited(_writeClipboard());
    // 审计只在打开时记一条：记的是「谁在什么时候生成过码」这个行为本身，
    // 不该随 30 秒一次的滚动刷屏
    unawaited(Offline2faAudit.record(at: ServerClock.instance.now()));

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final prev = _code;
      _compute();
      if (!mounted) return;
      setState(() {});
      if (_code != prev) unawaited(_writeClipboard());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _compute() {
    final seed = builtinTotpSeed();
    if (seed == null) {
      _seedFailed = true;
      return;
    }
    // 必须用服务端校准过的时间：本机时钟一旦偏出容错窗，算出的码看起来完全正常，
    // 实际必然被拒，用户无从判断问题在哪
    final unix = ServerClock.instance.now().millisecondsSinceEpoch ~/ 1000;
    final counter = unix ~/ builtinSeedPeriod;
    _remain = builtinSeedPeriod - (unix % builtinSeedPeriod);
    if (counter != _counter) {
      _counter = counter;
      _code = Totp.generateForCounter(
        seed: seed,
        counter: counter,
        digits: builtinSeedDigits,
      );
    }
  }

  Future<void> _writeClipboard() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
  }

  Future<void> _handleManualCopy() async {
    final code = _code;
    if (code == null) return;
    await _writeClipboard();
    if (!mounted) return;
    showTopNotice(context, '已复制：$code', level: NoticeLevel.success);
  }

  /// 六位码分成两组显示，便于照着念/输入
  String get _grouped {
    final code = _code;
    if (code == null || code.length != 6) return code ?? '——';
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveDialogScaffold(
      title: '2FA 动态码',
      maxWidth: 380,
      body: _seedFailed ? _buildFailed() : _buildCode(),
    );
  }

  Widget _buildFailed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Icon(Icons.error_outline, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          '无法在本地生成动态码',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '请恢复网络后重试',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCode() {
    final progress = _remain / builtinSeedPeriod;
    // 最后 5 秒转红，提示该等下一个码了
    final urgent = _remain <= 5;
    final color = urgent ? AppColors.red : AppColors.iosBlue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // 码本体，点击即复制
        InkWell(
          onTap: _handleManualCopy,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            child: Text(
              _grouped,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w600,
                letterSpacing: 4,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$_remain 秒后自动更新',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: _handleManualCopy,
            icon: const Icon(LucideIcons.copy, size: 18),
            label: const Text('复制到剪贴板'),
          ),
        ),
        const SizedBox(height: 12),
        _buildHint(
          Icons.info_outline,
          '离线本地生成，已自动复制到剪贴板；码每 $builtinSeedPeriod 秒更新一次，'
          '更新后剪贴板会同步替换。',
          Colors.grey.shade600,
        ),
        // 从未校准过服务端时间时，本机时钟准不准全凭运气，必须显式提醒
        if (!ServerClock.instance.hasSynced) ...[
          const SizedBox(height: 8),
          _buildHint(
            Icons.warning_amber_rounded,
            '尚未与服务器校准过时间。若解锁失败，请先确认本机时间准确。',
            AppColors.orange,
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildHint(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.5, color: color),
          ),
        ),
      ],
    );
  }
}
