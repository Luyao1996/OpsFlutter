import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../data/terminal_api.dart';

class ChatWindowTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String terminalName;

  const ChatWindowTab({super.key, required this.terminalId, required this.terminalName});

  @override
  ConsumerState<ChatWindowTab> createState() => _ChatWindowTabState();
}

class _ChatWindowTabState extends ConsumerState<ChatWindowTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<TerminalChatMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(terminalApiProvider);
      final list = await api.getChatMessages(widget.terminalId);
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Optimistic update
    final newMessage = TerminalChatMessage(
      content: text,
      sender: 'admin',
      time: '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );
    setState(() {
      _messages.add(newMessage);
    });
    _controller.clear();
    _scrollToBottom();

    try {
      final api = ref.read(terminalApiProvider);
      await api.sendChatMessage(widget.terminalId, text);
      // Ideally re-fetch or confirm sent
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Chat History
        Expanded(
          child: Container(
            color: Colors.grey.shade50,
            child: _loading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isAdmin = msg.sender == 'admin';
                    return _buildMessageBubble(msg.content, msg.time, isAdmin);
                  },
                ),
          ),
        ),
        // Input Area
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () {}, 
                icon: Icon(LucideIcons.image, size: 20, color: Colors.grey.shade500),
                tooltip: '发送图片',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: '输入消息...',
                    hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sendMessage,
                icon: const Icon(LucideIcons.send, size: 20, color: Colors.blue),
                tooltip: '发送',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(String text, String time, bool isAdmin) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isAdmin ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isAdmin) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey.shade300,
              child: const Icon(LucideIcons.user, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isAdmin ? Colors.blue : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isAdmin ? const Radius.circular(16) : const Radius.circular(2),
                  bottomRight: isAdmin ? const Radius.circular(2) : const Radius.circular(16),
                ),
                boxShadow: [
                  if (!isAdmin)
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 14, color: isAdmin ? Colors.white : Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(fontSize: 10, color: isAdmin ? Colors.white.withOpacity(0.7) : Colors.grey.shade400),
                  ),
                ],
              ),
            ),
          ),

          if (isAdmin) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(LucideIcons.shieldCheck, size: 16, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}