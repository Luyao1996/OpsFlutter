import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/providers/app_providers.dart';

class HardwareInfoTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String seatId;
  const HardwareInfoTab({super.key, required this.terminalId, required this.seatId});

  @override
  ConsumerState<HardwareInfoTab> createState() => _HardwareInfoTabState();
}

class _HardwareInfoTabState extends ConsumerState<HardwareInfoTab> {
  List<Map<String, dynamic>> _hardware = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHardware();
  }

  Future<void> _loadHardware() async {
    debugPrint('[HardwareInfoTab] _loadHardware 开始, seatId=${widget.seatId}, terminalId=${widget.terminalId}');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(terminalApiProvider);
      final domain = ref.read(currentNetbarProvider).subdomainFull ?? '';
      debugPrint('[HardwareInfoTab] domain=$domain');
      final list = await api.getHardwareInfo(widget.seatId, domain: domain);
      debugPrint('[HardwareInfoTab] 获取到 ${list.length} 项硬件信息');
      if (mounted) {
        setState(() {
          _hardware = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[HardwareInfoTab] 加载失败: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  IconData _getIcon(String name) {
    if (name.contains('处理器') || name.contains('CPU')) return LucideIcons.cpu;
    if (name.contains('主板') || name.contains('Board'))
      return LucideIcons.layers;
    if (name.contains('内存') || name.contains('Memory') || name.contains('RAM'))
      return LucideIcons.memoryStick;
    if (name.contains('显卡') ||
        name.contains('GPU') ||
        name.contains('Graphics'))
      return LucideIcons.gamepad2;
    if (name.contains('存储') ||
        name.contains('Disk') ||
        name.contains('Storage'))
      return LucideIcons.hardDrive;
    if (name.contains('网络') || name.contains('Network'))
      return LucideIcons.network;
    return LucideIcons.box;
  }

  Widget _buildCard(Map<String, dynamic> item, {bool flexible = false}) {
    final details =
        (item['details'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final detailsContent = Column(
      children: details.map<Widget>((detail) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                detail['label'] ?? '',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Text(
                  detail['value'] ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _getIcon(item['name'] ?? ''),
                    size: 16,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  item['name'] ?? '未知硬件',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          // Details: flexible = no scroll, just expand; fixed = scroll inside
          if (flexible)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: detailsContent,
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: detailsContent,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text('加载失败: $_error', style: const TextStyle(color: Colors.red)),
      );
    }
    if (_hardware.isEmpty) return const Center(child: Text('暂无硬件信息'));

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount;
        if (width >= 1200) {
          crossAxisCount = 3;
        } else if (width >= 800) {
          crossAxisCount = 2;
        } else {
          crossAxisCount = 1;
        }

        // Mobile (single column): use ListView, cards expand to content height
        if (crossAxisCount == 1) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _hardware.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) =>
                _buildCard(_hardware[index], flexible: true),
          );
        }

        // Desktop (multi-column): use GridView with fixed aspect ratio
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.5,
          ),
          itemCount: _hardware.length,
          itemBuilder: (context, index) =>
              _buildCard(_hardware[index], flexible: false),
        );
      },
    );
  }
}
