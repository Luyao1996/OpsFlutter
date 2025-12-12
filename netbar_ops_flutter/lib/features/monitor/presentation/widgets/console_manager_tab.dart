import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

class ConsoleManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  const ConsoleManagerTab({super.key, required this.terminalId});

  @override
  ConsumerState<ConsoleManagerTab> createState() => _ConsoleManagerTabState();
}

class _ConsoleManagerTabState extends ConsumerState<ConsoleManagerTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  final List<String> _history = [
    'Microsoft Windows [版本 10.0.19045.3693]',
    '(c) Microsoft Corporation。保留所有权利。',
    '',
    'C:\Users\Administrator>'
  ];

  Future<void> _sendCommand() async {
    final cmd = _controller.text.trim();
    if (cmd.isEmpty) return;

    setState(() {
      _history.add('$cmd'); 
    });
    _controller.clear();
    _scrollToBottom();

    // Local commands simulation
    if (cmd.toLowerCase() == 'cls') {
      setState(() {
        _history.clear();
        _history.addAll([
            'Microsoft Windows [版本 10.0.19045.3693]',
            '(c) Microsoft Corporation。保留所有权利。',
            '',
            'C:\Users\Administrator>'
        ]);
      });
      return;
    }

    try {
      final api = ref.read(terminalApiProvider);
      // Execute command via API
      final output = await api.executeCommand(widget.terminalId, cmd);
      if (mounted) {
        setState(() {
          _history.add(output);
          _history.add('');
          _history.add('C:\Users\Administrator>');
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _history.add('Error: $e');
          _history.add('');
          _history.add('C:\Users\Administrator>');
        });
        _scrollToBottom();
      }
    }
    
    _focusNode.requestFocus();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _history.length,
              itemBuilder: (context, index) {
                return SelectableText(
                  _history[index],
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'Consolas',
                    fontSize: 14,
                    height: 1.2,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'C:\Users\Administrator>',
                style: TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontFamily: 'Consolas',
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  onSubmitted: (_) => _sendCommand(),
                  style: const TextStyle(
                    color: Color(0xFFCCCCCC),
                    fontFamily: 'Consolas',
                    fontSize: 14,
                  ),
                  cursorColor: Colors.white,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}