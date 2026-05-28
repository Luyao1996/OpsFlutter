import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/game_constants.dart';
import '../../data/game_models.dart';
import '../../providers/game_library_providers.dart';

/// 闲置 Tab 顶部回收策略工具条
///
/// 与 Web 端 `.gm-recycle-bar` 1:1 对齐：阈值输入 + 确定 + 自动删除开关 + 执行时间按钮。
class RecycleBar extends ConsumerStatefulWidget {
  final String subdomain;
  final VoidCallback onOpenSchedule;

  const RecycleBar({
    super.key,
    required this.subdomain,
    required this.onOpenSchedule,
  });

  @override
  ConsumerState<RecycleBar> createState() => _RecycleBarState();
}

class _RecycleBarState extends ConsumerState<RecycleBar> {
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
        widget.onOpenSchedule();
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gameLibraryNotifierProvider(widget.subdomain));
    final plan = state.recyclePlan;
    final planSaving = state.planSaving;
    _syncFromPlan(plan);
    final enabled = plan?.enabled ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF9FAFB),
        border: Border(
          top: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 阈值组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('当前盘占用大于',
                  style: TextStyle(fontSize: 12, color: Color(0xFF374151))),
              const SizedBox(width: 6),
              _numField(_freeCtrl, const ValueKey('recycle_ft')),
              const SizedBox(width: 4),
              const Text('%、',
                  style: TextStyle(fontSize: 12, color: Color(0xFF374151))),
              const SizedBox(width: 4),
              _numField(_daysCtrl, const ValueKey('recycle_rd')),
              const SizedBox(width: 4),
              const Text('天未启动过的游戏',
                  style: TextStyle(fontSize: 12, color: Color(0xFF374151))),
              const SizedBox(width: 8),
              SizedBox(
                height: 30,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.iosBlue,
                    side: const BorderSide(color: AppColors.iosBlue),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 30),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: planSaving ? null : _onConfirm,
                  child: planSaving
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确定', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          // 操作组
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 自动删除 Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('自动删除',
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF374151))),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: enabled,
                      onChanged: planSaving
                          ? null
                          : (v) => _onToggleAutoDelete(v),
                      activeColor: Colors.white,
                      activeTrackColor: AppColors.iosBlue,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 30,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFD1D5DB)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: planSaving ? null : widget.onOpenSchedule,
                  icon: const Icon(LucideIcons.calendarClock, size: 13),
                  label: const Text('执行时间',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, Key key) {
    return SizedBox(
      width: 56,
      height: 30,
      child: TextField(
        key: key,
        controller: ctrl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(4),
        ],
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}
