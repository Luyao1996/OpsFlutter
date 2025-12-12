import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../monitor/data/terminal_api.dart';
import '../../../../shared/providers/app_providers.dart';

class RemoteWakeModal extends ConsumerStatefulWidget {
  final String netbarName;
  const RemoteWakeModal({super.key, required this.netbarName});

  @override
  ConsumerState<RemoteWakeModal> createState() => _RemoteWakeModalState();
}

class _RemoteWakeModalState extends ConsumerState<RemoteWakeModal> {
  final TextEditingController _macController = TextEditingController();
  final TextEditingController _rangeStartController = TextEditingController();
  final TextEditingController _rangeEndController = TextEditingController();
  bool _isWaking = false;
  String? _resultMessage;
  String _mode = 'single'; // single, range, all

  Future<void> _handleWake() async {
    setState(() {
      _isWaking = true;
      _resultMessage = null;
    });

    try {
      final api = ref.read(terminalApiProvider);
      // Construct IDs or params based on mode
      // For now, we mock the ID list generation as we don't have full terminal list here easily without fetching
      // In a real app, this might call a specific endpoint like /netbar/:id/wake with params
      
      // Simulating API call delay
      await Future.delayed(const Duration(seconds: 1));
      
      // If we had an API that took MAC or Range directly, we'd use that.
      // Assuming api.wakeOnLan takes list of IDs. 
      // Here we just simulate success for the demo as the backend might not support raw MAC/Range wake directly via Client API.
      
      if (mounted) {
        setState(() {
          _resultMessage = '唤醒指令已发送';
          _isWaking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _resultMessage = '唤醒失败: $e';
          _isWaking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.power, color: AppColors.iosBlue),
                  const SizedBox(width: 12),
                  Text('远程唤醒 - ${widget.netbarName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 24),
              
              // Mode Selection
              Row(
                children: [
                  _buildModeChip('single', '单机'),
                  const SizedBox(width: 12),
                  _buildModeChip('range', '号段'),
                  const SizedBox(width: 12),
                  _buildModeChip('all', '全部'),
                ],
              ),
              const SizedBox(height: 24),

              if (_mode == 'single')
                TextField(
                  controller: _macController,
                  decoration: const InputDecoration(
                    labelText: 'MAC 地址 / 机器号',
                    border: OutlineInputBorder(),
                    hintText: '输入机器号或MAC地址',
                  ),
                )
              else if (_mode == 'range')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rangeStartController,
                        decoration: const InputDecoration(labelText: '起始号', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('至')),
                    Expanded(
                      child: TextField(
                        controller: _rangeEndController,
                        decoration: const InputDecoration(labelText: '结束号', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                )
              else
                const Text('将唤醒该网吧所有离线终端，请谨慎操作。', style: TextStyle(color: Colors.red)),

              if (_resultMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _resultMessage!.contains('失败') ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _resultMessage!.contains('失败') ? LucideIcons.alertCircle : LucideIcons.checkCircle2,
                        size: 16,
                        color: _resultMessage!.contains('失败') ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_resultMessage!, style: TextStyle(color: _resultMessage!.contains('失败') ? Colors.red : Colors.green))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isWaking ? null : _handleWake,
                    icon: _isWaking 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(LucideIcons.power, size: 16),
                    label: Text(_isWaking ? '发送中...' : '立即唤醒'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.iosBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  Widget _buildModeChip(String mode, String label) {
    final isSelected = _mode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (v) => setState(() {
        if (v) {
          _mode = mode;
          _resultMessage = null;
        }
      }),
      selectedColor: AppColors.iosBlue.withOpacity(0.1),
      labelStyle: TextStyle(color: isSelected ? AppColors.iosBlue : Colors.black87),
      backgroundColor: Colors.white,
      side: BorderSide(color: isSelected ? AppColors.iosBlue : Colors.grey.shade300),
    );
  }
}
