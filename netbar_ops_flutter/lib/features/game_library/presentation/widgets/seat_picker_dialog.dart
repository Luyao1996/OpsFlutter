import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../monitor/data/terminal_api.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/game_constants.dart';
import '../../data/game_models.dart';

/// 选机号子对话框：用户点"下载"后弹出
class SeatPickerDialog extends ConsumerStatefulWidget {
  final int merchantId;
  final GameItem row;

  const SeatPickerDialog({
    super.key,
    required this.merchantId,
    required this.row,
  });

  /// 返回用户选择的座位 id；null 表示取消
  static Future<String?> show(
    BuildContext context, {
    required int merchantId,
    required GameItem row,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SeatPickerDialog(merchantId: merchantId, row: row),
    );
  }

  @override
  ConsumerState<SeatPickerDialog> createState() => _SeatPickerDialogState();
}

class _SeatPickerDialogState extends ConsumerState<SeatPickerDialog> {
  static const _prefsKeyPrefix = 'gameLibrary:lastSeat:';

  List<Terminal> _seats = [];
  bool _loading = true;
  String? _selectedSeatId;
  String? _lastSeatHint;
  final _manualController = TextEditingController();
  bool _useManual = false;

  String get _prefsKey => '$_prefsKeyPrefix${widget.merchantId}';

  @override
  void initState() {
    super.initState();
    _loadLastSeat();
    _fetchSeats();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _loadLastSeat() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final last = sp.getString(_prefsKey);
      if (mounted && last != null && last.isNotEmpty) {
        setState(() {
          _lastSeatHint = last;
          _selectedSeatId = last;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveLastSeat(String seatId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsKey, seatId);
    } catch (_) {}
  }

  Future<void> _fetchSeats() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(terminalApiProvider);
      final list = await api.getAll(merchantId: widget.merchantId);
      if (!mounted) return;
      // 只保留客户端机（mode != 1/2 视为客户端），server 不发起游戏下载
      final clients = list.where((t) {
        final mode = t.mode;
        return mode != 1 && mode != 2;
      }).toList();
      setState(() {
        _seats = clients;
        _loading = false;
        // 只有 1 个座位则默认选中（未命中"上次"时）
        if (_selectedSeatId == null && clients.length == 1) {
          _selectedSeatId = clients.first.seatId;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _confirm() {
    final id = _useManual
        ? _manualController.text.trim()
        : (_selectedSeatId ?? '');
    if (id.isEmpty) return;
    // 只把"真实机号"持久化到 lastSeat；工具箱身份不入持久化（避免被当机号显示）
    if (id != kToolboxSeat) {
      _saveLastSeat(id);
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择目标机号',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '选一个机号发起下载；该机号若在下别的游戏会自动切换。',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('游戏：', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                      Expanded(
                        child: Text(
                          row.name ?? row.gid.toString(),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: platformAccentSoft(row.platform),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          kPlatformLabel[row.platform] ?? row.platform,
                          style: TextStyle(
                            fontSize: 11,
                            color: platformAccent(row.platform),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_useManual)
                    TextField(
                      controller: _manualController,
                      decoration: const InputDecoration(
                        hintText: '手动输入机号',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    _buildSeatList(),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    onPressed: () => setState(() => _useManual = !_useManual),
                    icon: Icon(
                      _useManual ? LucideIcons.list : LucideIcons.edit2,
                      size: 12,
                    ),
                    label: Text(
                      _useManual ? '从列表选择' : '手动输入机号',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_lastSeatHint != null && _lastSeatHint!.isNotEmpty && !_useManual)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSeatId = _lastSeatHint;
                          });
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.history,
                                size: 13,
                                color: AppColors.iosBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '上次使用：$_lastSeatHint',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.iosBlue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _canConfirm() ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('确定下载'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canConfirm() {
    if (_useManual) return _manualController.text.trim().isNotEmpty;
    // 真实机号选中或选了"工具箱身份"均视为可确认
    return _selectedSeatId != null && _selectedSeatId!.isNotEmpty;
  }

  /// 「工具箱身份（不选机号）」独立项
  /// 不受 _seats 拉取失败/为空影响；选中后 _selectedSeatId = kToolboxSeat
  Widget _buildToolboxOption() {
    final selected = _selectedSeatId == kToolboxSeat;
    return InkWell(
      onTap: () => setState(() => _selectedSeatId = kToolboxSeat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade100),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: 14,
              color: selected ? AppColors.iosBlue : Colors.grey.shade400,
            ),
            const SizedBox(width: 8),
            Icon(
              LucideIcons.package,
              size: 13,
              color: selected ? AppColors.iosBlue : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '工具箱身份（不选机号，可并发下载）',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.iosBlue : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '不占用任何客户端机号；多任务同时下载不冲突',
                    style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeatList() {
    // 工具箱身份独立项：不受 _loading / _seats 为空影响，始终渲染在最顶部
    final toolboxTile = _buildToolboxOption();

    Widget body;
    if (_loading) {
      body = const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_seats.isEmpty) {
      body = Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: const Text(
          '暂无客户端机号，可使用工具箱身份或手动输入',
          style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      );
    } else {
      body = Column(
        children: [
          for (final s in _seats)
            InkWell(
              onTap: () => setState(() => _selectedSeatId = s.seatId),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: _selectedSeatId == s.seatId
                      ? const Color(0xFFEFF6FF)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade100),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectedSeatId == s.seatId
                          ? LucideIcons.checkCircle2
                          : LucideIcons.circle,
                      size: 14,
                      color: _selectedSeatId == s.seatId
                          ? AppColors.iosBlue
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.seatId,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      s.status > 0 ? '● 在线' : '○ 离线',
                      style: TextStyle(
                        fontSize: 11,
                        color: s.status > 0 ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            toolboxTile,
            body,
          ],
        ),
      ),
    );
  }
}
