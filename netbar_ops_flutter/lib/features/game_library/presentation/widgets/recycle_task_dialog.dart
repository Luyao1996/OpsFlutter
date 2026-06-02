import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/adaptive_show.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/game_constants.dart';
import '../../data/game_models.dart';
import '../../providers/game_library_providers.dart';
import 'recycle_schedule_dialog.dart';

/// 闲置游戏「清理任务」设置弹窗。
///
/// 由「任务」按钮唤起，纵向排列「自动清理条件 / 自动删除 / 执行时间」三块，
/// 取代原先内联在列表上方、横向挤一行会溢出的 RecycleBar。
class RecycleTaskDialog extends ConsumerStatefulWidget {
  final String subdomain;

  const RecycleTaskDialog({super.key, required this.subdomain});

  static Future<void> show(BuildContext context, String subdomain) {
    return showAdaptive<void>(
      context,
      (_) => RecycleTaskDialog(subdomain: subdomain),
    );
  }

  @override
  ConsumerState<RecycleTaskDialog> createState() => _RecycleTaskDialogState();
}

class _RecycleTaskDialogState extends ConsumerState<RecycleTaskDialog> {
  final _freeCtrl = TextEditingController();
  final _daysCtrl = TextEditingController();
  // 缓存上次同步过的后端值，避免每帧 setText 打断用户输入
  int? _lastSyncedFree;
  int? _lastSyncedDays;

  @override
  void dispose() {
    _freeCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  /// 用后端最新值同步输入框文案：只在「后端值真的变了」且与当前输入不同时才覆盖，
  /// 否则会把用户正在键入的中间值清掉。
  void _syncFromPlan(RecyclePlan? plan) {
    final ft = plan?.freeThresholdUi;
    final rd = plan?.retainDays;
    if (ft != _lastSyncedFree) {
      _lastSyncedFree = ft;
      final s = ft?.toString() ?? '';
      if (_freeCtrl.text != s) _freeCtrl.text = s;
    }
    if (rd != _lastSyncedDays) {
      _lastSyncedDays = rd;
      final s = rd?.toString() ?? '';
      if (_daysCtrl.text != s) _daysCtrl.text = s;
    }
  }

  void _toast(String msg, {bool warn = false, bool error = false}) {
    if (!mounted) return;
    final bg = error
        ? AppColors.red
        : (warn ? const Color(0xFFB45309) : Colors.black87);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  ({int? free, int? days, String? error}) _parseThresholds() {
    final ftRaw = _freeCtrl.text.trim();
    final rdRaw = _daysCtrl.text.trim();
    if (ftRaw.isEmpty) return (free: null, days: null, error: '请填写盘占用阈值');
    if (rdRaw.isEmpty) return (free: null, days: null, error: '请填写天数');
    final ft = int.tryParse(ftRaw);
    final rd = int.tryParse(rdRaw);
    if (ft == null || ft < 0 || ft > 100) {
      return (free: null, days: null, error: '盘占用阈值需要在 0 - 100 之间');
    }
    if (rd == null || rd < 0) {
      return (free: null, days: null, error: '天数需要 ≥ 0');
    }
    return (free: ft, days: rd, error: null);
  }

  Future<void> _onConfirm() async {
    final p = _parseThresholds();
    if (p.error != null) {
      _toast(p.error!, warn: true);
      return;
    }
    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomain).notifier);
    final r = await notifier.confirmThresholds(
      freeThresholdUi: p.free!,
      retainDays: p.days!,
    );
    if (!mounted) return;
    if (r.ok) {
      _toast('已保存筛选条件');
    } else {
      _toast('保存失败：${r.error ?? "未知错误"}', error: true);
    }
  }

  Future<void> _onToggleAutoDelete(bool target) async {
    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomain).notifier);
    if (target) {
      final p = _parseThresholds();
      if (p.error != null) {
        _toast(p.error!, warn: true);
        return;
      }
      // 先把阈值同步到后端（与 Web 端 onToggleAutoDelete 行为一致：缺则不让开）
      final plan =
          ref.read(gameLibraryNotifierProvider(widget.subdomain)).recyclePlan;
      final weekdays = plan?.weekdays ?? const <int>[];
      if (weekdays.isEmpty) {
        // 缺周天 → 弹「执行时间」让用户补齐，不立刻开
        await _openSchedule();
        return;
      }
      final r = await notifier.toggleAutoDelete(true);
      if (!mounted) return;
      if (!r.ok) _toast('开启失败：${r.error ?? "未知错误"}', error: true);
    } else {
      final r = await notifier.toggleAutoDelete(false);
      if (!mounted) return;
      if (!r.ok) _toast('关闭失败：${r.error ?? "未知错误"}', error: true);
    }
  }

  Future<void> _openSchedule() async {
    final state = ref.read(gameLibraryNotifierProvider(widget.subdomain));
    final cur = state.recyclePlan;
    final res = await RecycleScheduleDialog.show(
      context,
      weekdays: List<int>.from(cur?.weekdays ?? const <int>[]),
      time: cur?.time ?? RecycleDefaults.time,
    );
    if (res == null || !mounted) return;
    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomain).notifier);
    final r = await notifier.confirmSchedule(
      weekdays: res.weekdays,
      time: res.time,
    );
    if (!mounted) return;
    if (!r.ok) {
      _toast('保存失败：${r.error ?? "未知错误"}', error: true);
    } else {
      _toast('已保存自动清理策略');
    }
  }

  /// 删除任务：二次确认后向后端发送空值清空设定，并把本地状态置空。
  Future<void> _onDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除清理任务'),
        content: const Text('将清空已设定的盘占用阈值、天数、执行时间，并停止自动删除。确定删除？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final notifier =
        ref.read(gameLibraryNotifierProvider(widget.subdomain).notifier);
    final r = await notifier.deletePlan();
    if (!mounted) return;
    if (r.ok) {
      _toast('已删除清理任务');
    } else {
      _toast('删除失败：${r.error ?? "未知错误"}', error: true);
    }
  }

  /// 执行时间摘要：未设置周天显示"未设置"，否则"周一 周三 … HH:mm"
  String _scheduleSummary(List<int> weekdays, String time) {
    if (weekdays.isEmpty) return '未设置';
    const names = ['日', '一', '二', '三', '四', '五', '六'];
    final sorted = [...weekdays]..sort();
    final label = sorted.map((w) => '周${names[w % 7]}').join(' ');
    return '$label $time';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameLibraryNotifierProvider(widget.subdomain));
    final plan = state.recyclePlan;
    final planSaving = state.planSaving;
    _syncFromPlan(plan);
    final enabled = plan?.enabled ?? false;
    final weekdays = plan?.weekdays ?? const <int>[];
    final time = plan?.time ?? RecycleDefaults.time;
    final hasPlan = enabled ||
        weekdays.isNotEmpty ||
        plan?.freeThresholdUi != null ||
        plan?.retainDays != null;

    return ResponsiveDialogScaffold(
      title: '闲置游戏清理任务',
      maxWidth: 480,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ============ 自动清理条件 ============
          _sectionTitle('自动清理条件'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('当前盘占用大于',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151))),
              const SizedBox(width: 8),
              _numField(_freeCtrl),
              const SizedBox(width: 6),
              const Text('%',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _numField(_daysCtrl),
              const SizedBox(width: 8),
              const Text('天未启动过的游戏',
                  style: TextStyle(fontSize: 13, color: Color(0xFF374151))),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              height: 34,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.iosBlue,
                  side: const BorderSide(color: AppColors.iosBlue),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 34),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: planSaving ? null : _onConfirm,
                child: planSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存条件', style: TextStyle(fontSize: 13)),
              ),
            ),
          ),
          const _SectionDivider(),
          // ============ 自动删除 ============
          Row(
            children: [
              const Text('自动删除',
                  style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const Spacer(),
              Switch(
                value: enabled,
                onChanged: planSaving ? null : (v) => _onToggleAutoDelete(v),
                activeColor: Colors.white,
                activeTrackColor: AppColors.iosBlue,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const _SectionDivider(),
          // ============ 执行时间 ============
          Row(
            children: [
              const Text('执行时间',
                  style: TextStyle(fontSize: 14, color: Color(0xFF374151))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _scheduleSummary(weekdays, time),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 34,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 34),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: planSaving ? null : _openSchedule,
                  icon: const Icon(LucideIcons.calendarClock, size: 14),
                  label: const Text('设置', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          // ============ 删除任务（仅已有设定时显示）============
          if (hasPlan) ...[
            const _SectionDivider(),
            Center(
              child: TextButton(
                onPressed: planSaving ? null : _onDelete,
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('删除此任务', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.iosBlue),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成', style: TextStyle(fontSize: 15)),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF111827),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl) {
    return SizedBox(
      width: 64,
      height: 34,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// 分区分隔线（上下留白）
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: Color(0xFFE5E7EB)),
    );
  }
}
