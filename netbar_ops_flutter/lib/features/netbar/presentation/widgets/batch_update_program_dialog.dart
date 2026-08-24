import 'package:flutter/material.dart';
import '../../../../core/network/error_message.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../../../shared/widgets/responsive_dialog_scaffold.dart';
import '../../data/netbar_api.dart';
import 'netbar_multi_select_table.dart';

/// 更新通道选项：key 为下发给服务端的 type 值，'' 表示不改变网吧现有通道
const Map<String, String> _kUpdateTypeOptions = {
  '': '不改变',
  'debug': '内测版',
  'release': '正式版',
};

const int _kMinInterval = 0;
const int _kMaxInterval = 60;

enum _SendStatus { pending, success, fail }

/// 单家网吧的下发结果，逐家下发过程中由各自的响应回调就地改写
class _SendResult {
  final int id;
  final String name;
  _SendStatus status;
  String msg;

  _SendResult({required this.id, required this.name})
      : status = _SendStatus.pending,
        msg = '';
}

/// 批量更新程序对话框
/// 对标 Vue 端 BatchProgramUpdateDialog.vue
class BatchUpdateProgramDialog extends StatefulWidget {
  const BatchUpdateProgramDialog({super.key});

  @override
  State<BatchUpdateProgramDialog> createState() => _BatchUpdateProgramDialogState();
}

class _BatchUpdateProgramDialogState extends State<BatchUpdateProgramDialog> {
  List<Netbar> _netbars = [];
  List<GroupBrief> _groups = [];
  List<int> _selectedIds = [];
  bool _loading = true;

  /// 单家下发（一次性请求）进行中
  bool _submitting = false;

  /// 多家「按节拍逐家下发」进行中
  bool _sending = false;
  bool _cancelRequested = false;

  String _updateType = '';
  int _intervalSeconds = 3;

  int _done = 0;
  int _total = 0;
  String _current = '';
  final List<_SendResult> _results = [];

  void _log(String level, String contextId, String msg) {
    final ts = DateTime.now().toIso8601String();
    debugPrint('[$ts][$level][netbar][batchUpdate][$contextId] $msg');
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final api = NetbarApi();
      final result = await api.getListFull();
      if (!mounted) return;
      setState(() {
        _netbars = result.merchants;
        _groups = result.groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showTopNotice(context, '加载网吧列表失败：$e', level: NoticeLevel.error);
    }
  }

  List<_SendResult> get _failList =>
      _results.where((r) => r.status == _SendStatus.fail).toList();

  int get _successCount =>
      _results.where((r) => r.status == _SendStatus.success).length;

  /// 预计耗时：只有 N-1 个间隔，且至少显示 1 分钟（对齐 Web 端文案口径）
  int get _estimatedMinutes {
    final gaps = (_selectedIds.length - 1) * _intervalSeconds;
    final minutes = (gaps / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  void _setInterval(int v) {
    final clamped = v < _kMinInterval
        ? _kMinInterval
        : (v > _kMaxInterval ? _kMaxInterval : v);
    if (clamped == _intervalSeconds) return;
    setState(() => _intervalSeconds = clamped);
  }

  Future<void> _handleConfirm() async {
    if (_submitting || _sending || _selectedIds.isEmpty) return;
    if (_selectedIds.length == 1) {
      await _confirmSingle();
    } else {
      await _confirmSequential();
    }
  }

  /// 单选：保持一次性下发行为
  Future<void> _confirmSingle() async {
    setState(() => _submitting = true);
    final ids = List<int>.from(_selectedIds);
    try {
      _log('INFO', '${ids.first}', 'single send type=${_updateType.isEmpty ? 'keep' : _updateType}');
      await NetbarApi().batchProgramUpdate(merchantIds: ids, type: _updateType);
      if (!mounted) return;
      showTopNotice(context, '更新指令已下发', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      _log('ERROR', '${ids.first}', 'single send fail err=$e');
      if (!mounted) return;
      showTopNotice(context, '操作失败：${friendlyErrorMessage(e)}', level: NoticeLevel.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 发一家。故意不让异常逃逸：调用方不 await 它，逃逸的异常会变成未捕获错误
  Future<void> _sendOne(NetbarApi api, _SendResult item) async {
    try {
      await api.batchProgramUpdate(merchantIds: [item.id], type: _updateType);
      item.status = _SendStatus.success;
      _log('INFO', '${item.id}', 'send ok name=${item.name}');
    } catch (e) {
      item.status = _SendStatus.fail;
      // ApiClient 把后端 code!=0 也抛成 ApiError，业务失败与网络异常在这里合流
      item.msg = friendlyErrorMessage(e);
      _log('ERROR', '${item.id}', 'send fail name=${item.name} err=${item.msg}');
    } finally {
      if (mounted) {
        setState(() => _done += 1);
      } else {
        _done += 1;
      }
    }
  }

  /// 多选：严格按固定节拍每 N 秒发出 1 家，不等上一家响应回来——
  /// 避免所有网吧同时下载更新包把出口带宽打满；同一时刻可能多家请求在飞，各自回包后更新自己那行
  Future<void> _confirmSequential() async {
    final queue = List<int>.from(_selectedIds);
    final nameMap = {
      for (final n in _netbars) n.id: n.name.isEmpty ? '网吧${n.id}' : n.name
    };

    setState(() {
      _sending = true;
      _cancelRequested = false;
      _done = 0;
      _total = queue.length;
      _current = '';
      _results
        ..clear()
        ..addAll(queue.map((id) => _SendResult(id: id, name: nameMap[id] ?? '网吧$id')));
    });
    _log('INFO', 'batch', 'sequential start total=${queue.length} '
        'interval=${_intervalSeconds}s type=${_updateType.isEmpty ? 'keep' : _updateType}');

    final api = NetbarApi();
    final pending = <Future<void>>[];
    for (var i = 0; i < queue.length; i++) {
      if (_cancelRequested) break;
      final item = _results[i];
      if (mounted) setState(() => _current = item.name);
      pending.add(_sendOne(api, item));
      if (i < queue.length - 1 && !_cancelRequested) {
        await Future.delayed(Duration(seconds: _intervalSeconds));
      }
    }

    // 节拍跑完/被停止后，已发出的请求可能还没回包，等它们全部落定再收尾；
    // 逐个 await 并吞掉异常，避免任何一个失败打断收尾流程
    for (final p in pending) {
      try {
        await p;
      } catch (_) {}
    }

    final stopped = _cancelRequested;
    final failCount = _failList.length;
    final successCount = _successCount;
    if (mounted) {
      setState(() {
        _sending = false;
        _current = '';
      });
    }
    _log('INFO', 'batch', 'sequential end done=$_done/$_total '
        'success=$successCount fail=$failCount stopped=$stopped');
    if (!mounted) return;

    // 只有全部成功才自动关窗；有失败或中途停止时必须留在弹窗里，
    // 否则「成功/失败汇总」和失败列表一关就再也看不到了
    if (stopped) {
      showTopNotice(context, '已停止：完成 $_done/$_total 家', level: NoticeLevel.info);
    } else if (failCount > 0) {
      showTopNotice(context, '下发结束：成功 $successCount 家，失败 $failCount 家',
          level: NoticeLevel.warning);
    } else {
      showTopNotice(context, '全部 $_total 家下发完成', level: NoticeLevel.success);
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 逐家下发过程中禁止关闭：关掉页面后节拍循环失去 UI，进度与失败列表全丢
      canPop: !_sending,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _sending) {
          showTopNotice(context, '正在逐家下发中，请先点击"停止下发"',
              level: NoticeLevel.warning);
        }
      },
      child: ResponsiveDialogScaffold(
        title: '批量更新程序',
        maxWidth: 1080,
        maxHeight: 900,
        scrollableBody: false,
        showCloseButton: !_sending,
        // scrollableBody=false 时骨架不会套 bodyPadding，内边距得自己加，
        // 否则表格和进度区会顶到弹窗左右边缘
        body: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: NetbarMultiSelectTable(
                        netbars: _netbars,
                        groups: _groups,
                        showSelectedCount: false,
                        onSelectionChanged: (ids) => setState(() => _selectedIds = ids),
                      ),
                    ),
                    if (!_sending && _selectedIds.isNotEmpty) _buildSelectionHint(),
                    if (_total > 0) _buildProgressArea(),
                  ],
                ),
        ),
        footer: _sending ? _buildSendingFooter() : _buildIdleFooter(),
      ),
    );
  }

  Widget _buildSelectionHint() {
    final n = _selectedIds.length;
    final text = n > 1
        ? '已选择 $n 家网吧。将按每 $_intervalSeconds 秒 1 家依次下发，预计约 $_estimatedMinutes 分钟。'
        : '已选择 $n 家网吧。';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
    );
  }

  Widget _buildProgressArea() {
    final percent = _total > 0 ? _done / _total : 0.0;
    final fails = _failList;
    final color = _sending
        ? AppColors.iosBlue
        : (fails.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFF59E0B));

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${(percent * 100).round()}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _sending
                ? '正在下发 $_done / $_total${_current.isEmpty ? '' : '，当前：$_current'}'
                : '已结束：成功 $_successCount，失败 ${fails.length}，未下发 ${_total - _done}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (fails.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 72),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: fails
                      .map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '${f.name}（${f.msg}）',
                              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSendingFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton(
          onPressed: _cancelRequested
              ? null
              : () {
                  _log('WARN', 'batch', 'stop requested at $_done/$_total');
                  setState(() => _cancelRequested = true);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF59E0B),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFFE5E7EB),
            disabledForegroundColor: Colors.grey.shade500,
          ),
          child: Text(_cancelRequested ? '正在停止…' : '停止下发'),
        ),
      ],
    );
  }

  Widget _buildIdleFooter() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildUpdateTypeSegment(),
            Text('间隔（$_kMinInterval~$_kMaxInterval秒）',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            _buildIntervalStepper(),
            Text('秒/家', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: (_submitting || _selectedIds.isEmpty) ? null : _handleConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.iosBlue,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('确认更新'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUpdateTypeSegment() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _kUpdateTypeOptions.entries.map((e) {
          final selected = _updateType == e.key;
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _updateType = e.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: selected
                  ? BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    )
                  : null,
              child: Text(
                e.value,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? AppColors.iosBlue : Colors.grey.shade600,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIntervalStepper() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(Icons.remove, _intervalSeconds > _kMinInterval,
              () => _setInterval(_intervalSeconds - 1)),
          SizedBox(
            width: 30,
            child: Text('$_intervalSeconds',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
          ),
          _stepperButton(Icons.add, _intervalSeconds < _kMaxInterval,
              () => _setInterval(_intervalSeconds + 1)),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Icon(icon,
            size: 16, color: enabled ? Colors.grey.shade700 : Colors.grey.shade300),
      ),
    );
  }
}
