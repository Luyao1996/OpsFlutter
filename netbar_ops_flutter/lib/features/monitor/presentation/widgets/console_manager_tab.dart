import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../shared/providers/app_providers.dart';

/// 连接状态
enum CmdConnectionState {
  disconnected, // 未连接
  connecting, // 连接中
  connected, // 已连接（WebSocket 已建立，但未登录）
  loggedIn, // 已登录（可以执行命令）
}

/// 终端命令 Tab - 参考 Vue XtermCmdDialog.vue 实现
class ConsoleManagerTab extends ConsumerStatefulWidget {
  final int terminalId;
  final String seatId;

  const ConsoleManagerTab({
    super.key,
    required this.terminalId,
    required this.seatId,
  });

  @override
  ConsumerState<ConsoleManagerTab> createState() => _ConsoleManagerTabState();
}

class _ConsoleManagerTabState extends ConsumerState<ConsoleManagerTab> {
  // 终端输出
  final List<TerminalLine> _outputLines = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  // WebSocket 相关
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  CmdConnectionState _connectionState = CmdConnectionState.disconnected;

  // 重连相关
  int _reconnectCount = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  Timer? _reconnectTimer;

  // 命令历史
  final List<String> _cmdHistory = [];
  int _cmdHistoryIndex = -1;

  // 终端信息
  String? _terminalIp;

  @override
  void initState() {
    super.initState();
    _initTerminal();
    _connect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _scrollController.dispose();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// 初始化终端（显示欢迎信息）
  void _initTerminal() {
    _addSystemLine('╔════════════════════════════════════════════════════════════╗', color: Colors.blue);
    _addSystemLine('║         远程命令终端 - Remote CMD Terminal                  ║', color: Colors.green);
    _addSystemLine('╚════════════════════════════════════════════════════════════╝', color: Colors.blue);
    _addLine('');
    _addSystemLine('提示:', color: Colors.amber);
    _addSystemLine('  • Ctrl+C - 中断当前命令 / 复制选中文本', color: Colors.cyan);
    _addSystemLine('  • Ctrl+V - 粘贴', color: Colors.cyan);
    _addSystemLine('  • Ctrl+L - 清屏', color: Colors.cyan);
    _addSystemLine('  • ↑/↓   - 浏览历史命令', color: Colors.cyan);
    _addLine('');
    _addSystemLine('正在连接...', color: Colors.grey);
    _addLine('');
  }

  /// 构建 WebSocket URL
  String _buildWsUrl() {
    final netbar = ref.read(currentNetbarProvider);
    String domain = netbar.subdomainFull ?? '';

    // 移除协议前缀
    domain = domain.replaceAll(RegExp(r'^https?://'), '');

    // 根据当前页面协议选择 ws 或 wss
    // Flutter 桌面/移动应用默认使用 ws
    const protocol = 'ws';

    return '$protocol://$domain/ws_client';
  }

  /// 连接 WebSocket
  void _connect() {
    if (_channel != null) {
      if (_connectionState != CmdConnectionState.loggedIn) {
        _loginCmd();
      }
      return;
    }

    setState(() => _connectionState = CmdConnectionState.connecting);

    final url = _buildWsUrl();
    _addSystemLine('[系统] 正在连接 $url', color: Colors.grey);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (error) {
          _addSystemLine('[错误] 连接错误: $error', color: Colors.red);
          _handleDisconnect();
        },
        onDone: () {
          _addSystemLine('[系统] 连接已关闭', color: Colors.amber);
          _handleDisconnect();
        },
      );

      setState(() => _connectionState = CmdConnectionState.connected);
      _reconnectCount = 0;
      _addSystemLine('[系统] WebSocket 已连接', color: Colors.green);

      // 连接成功后登录
      _loginCmd();
    } catch (e) {
      _addSystemLine('[错误] WebSocket 创建失败: $e', color: Colors.red);
      _handleDisconnect();
    }
  }

  /// 处理断开连接
  void _handleDisconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    setState(() => _connectionState = CmdConnectionState.disconnected);

    // 尝试自动重连
    if (_reconnectCount < _maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  /// 计划重连
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectCount++;

    _addSystemLine(
      '[系统] ${_reconnectDelay.inSeconds}秒后尝试重连 ($_reconnectCount/$_maxReconnectAttempts)',
      color: Colors.amber,
    );

    _reconnectTimer = Timer(_reconnectDelay, () {
      if (mounted) {
        _connect();
      }
    });
  }

  /// 登录命令通道
  void _loginCmd() {
    if (_channel == null) return;
    if (_connectionState == CmdConnectionState.loggedIn) return;

    _addSystemLine('[系统] 正在登录 seat=${widget.seatId}', color: Colors.grey);

    _sendJson({
      'fun': 'cmdlogin',
      'data': {'seat': widget.seatId},
    });
  }

  /// 发送 JSON 消息
  void _sendJson(Map<String, dynamic> data) {
    if (_channel == null) {
      _addSystemLine('[错误] 未连接或未就绪', color: Colors.red);
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      _addSystemLine('[错误] 发送失败: $e', color: Colors.red);
    }
  }

  /// 处理 WebSocket 消息
  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw.toString());
    } catch (_) {
      _addLine(raw.toString());
      return;
    }

    final fun = msg['fun'];
    final code = msg['code'];
    final tip = msg['msg'];
    final data = msg['data'];

    if (fun == 'cmdlogin') {
      if (code == 0) {
        setState(() => _connectionState = CmdConnectionState.loggedIn);
        _addSystemLine('[系统] 登录成功', color: Colors.green);
        _addLine('');
        // 显示提示符
        _addPrompt();
      } else {
        setState(() => _connectionState = CmdConnectionState.connected);
        _addSystemLine('[错误] 登录失败: ${tip ?? '未知错误'}', color: Colors.red);
      }
      return;
    }

    if (fun == 'cmdRun') {
      final output = data?['msg'] ?? tip ?? '';
      if (output.toString().isNotEmpty) {
        // 处理输出，转换换行符
        final lines = output.toString().split('\n');
        for (final line in lines) {
          _addLine(line);
        }
        // 输出后显示提示符
        if (!output.toString().endsWith('>')) {
          _addPrompt();
        }
      }
      return;
    }

    if (fun == 'cmdlogon') {
      if (code == 0) {
        _addSystemLine('[系统] 已注销', color: Colors.amber);
        setState(() => _connectionState = CmdConnectionState.connected);
      } else {
        _addSystemLine('[错误] 注销失败: ${tip ?? ''}', color: Colors.red);
      }
      return;
    }

    // 其他消息
    _addSystemLine('[消息] $raw', color: Colors.grey);
  }

  /// 发送命令
  void _sendCommand(String cmd) {
    if (_connectionState != CmdConnectionState.loggedIn) {
      _addSystemLine('[错误] 未连接到远程终端', color: Colors.red);
      return;
    }

    // 显示用户输入的命令
    _addLine('${widget.seatId}>$cmd', isCommand: true);

    // 添加到历史记录
    if (cmd.trim().isNotEmpty) {
      if (_cmdHistory.isEmpty || _cmdHistory.last != cmd) {
        _cmdHistory.add(cmd);
      }
      _cmdHistoryIndex = _cmdHistory.length;
    }

    _sendJson({
      'fun': 'cmdRun',
      'data': {'seat': widget.seatId, 'cmd': cmd},
    });
  }

  /// 发送 Ctrl+C 中断
  void _sendCtrlC() {
    if (_connectionState != CmdConnectionState.loggedIn) return;

    _addLine('^C');
    _sendJson({
      'fun': 'cmdRun',
      'data': {'seat': widget.seatId, 'cmd': '\x03'},
    });
  }

  /// 清屏
  void _clearTerminal() {
    setState(() {
      _outputLines.clear();
    });
    if (_connectionState == CmdConnectionState.loggedIn) {
      _addPrompt();
    }
  }

  /// 添加普通行
  void _addLine(String text, {bool isCommand = false}) {
    setState(() {
      _outputLines.add(TerminalLine(text: text, isCommand: isCommand));
    });
    _scrollToBottom();
  }

  /// 添加系统消息行
  void _addSystemLine(String text, {Color? color}) {
    setState(() {
      _outputLines.add(TerminalLine(text: text, color: color, isSystem: true));
    });
    _scrollToBottom();
  }

  /// 添加提示符
  void _addPrompt() {
    // 提示符不单独添加行，而是在输入框前显示
  }

  /// 滚动到底部
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 处理键盘事件
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    // Ctrl+C
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _sendCtrlC();
      _inputController.clear();
      return KeyEventResult.handled;
    }

    // Ctrl+L
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyL) {
      _clearTerminal();
      return KeyEventResult.handled;
    }

    // Ctrl+V（粘贴由系统处理）

    // 上箭头 - 历史命令
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_cmdHistory.isNotEmpty && _cmdHistoryIndex > 0) {
        _cmdHistoryIndex--;
        _inputController.text = _cmdHistory[_cmdHistoryIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      }
      return KeyEventResult.handled;
    }

    // 下箭头 - 历史命令
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_cmdHistoryIndex < _cmdHistory.length - 1) {
        _cmdHistoryIndex++;
        _inputController.text = _cmdHistory[_cmdHistoryIndex];
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      } else {
        _cmdHistoryIndex = _cmdHistory.length;
        _inputController.clear();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 处理命令提交
  void _onSubmit(String value) {
    final cmd = value.trim();
    _inputController.clear();

    if (cmd.isEmpty) {
      _addLine('${widget.seatId}>');
      return;
    }

    // 本地命令处理
    if (cmd.toLowerCase() == 'cls' || cmd.toLowerCase() == 'clear') {
      _clearTerminal();
      return;
    }

    _sendCommand(cmd);
    _inputFocusNode.requestFocus();
  }

  /// 手动重连
  void _manualReconnect() {
    _reconnectCount = 0;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connect();
  }

  /// 断开连接
  void _disconnect() {
    _reconnectTimer?.cancel();
    _reconnectCount = _maxReconnectAttempts; // 阻止自动重连

    if (_connectionState == CmdConnectionState.loggedIn) {
      _sendJson({
        'fun': 'cmdlogon',
        'data': {'seat': widget.seatId},
      });
    }

    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;

    setState(() => _connectionState = CmdConnectionState.disconnected);
    _addSystemLine('[系统] 已断开连接', color: Colors.amber);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Column(
        children: [
          // 标题栏
          _buildTitleBar(),
          // 终端输出区域
          Expanded(child: _buildTerminalOutput()),
          // 输入行
          _buildInputLine(),
          // 状态栏
          _buildStatusBar(),
        ],
      ),
    );
  }

  /// 构建标题栏
  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2D2D2D), Color(0xFF1A1A1A)],
        ),
        border: Border(bottom: BorderSide(color: Color(0xFF3A3A3A))),
      ),
      child: Row(
        children: [
          // 标题
          const Text(
            '▓',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
          const SizedBox(width: 8),
          Text(
            '命令提示符 - ${widget.seatId}',
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // 连接状态
          _buildConnectionStatus(),
          const SizedBox(width: 12),
          // 清屏按钮
          _buildTitleButton(
            icon: LucideIcons.trash2,
            tooltip: '清屏 (Ctrl+L)',
            onTap: _clearTerminal,
          ),
          const SizedBox(width: 4),
          // 重连按钮
          if (_connectionState != CmdConnectionState.loggedIn)
            _buildTitleButton(
              icon: LucideIcons.refreshCw,
              tooltip: '重新连接',
              onTap: _manualReconnect,
            ),
          // 断开按钮
          if (_connectionState == CmdConnectionState.loggedIn)
            _buildTitleButton(
              icon: LucideIcons.unplug,
              tooltip: '断开连接',
              onTap: _disconnect,
            ),
        ],
      ),
    );
  }

  /// 构建连接状态指示器
  Widget _buildConnectionStatus() {
    Color dotColor;
    Color bgColor;
    String text;

    switch (_connectionState) {
      case CmdConnectionState.loggedIn:
        dotColor = const Color(0xFF4ADE80);
        bgColor = const Color(0xFF4ADE80).withOpacity(0.15);
        text = '已连接';
        break;
      case CmdConnectionState.connected:
      case CmdConnectionState.connecting:
        dotColor = const Color(0xFFFBBF24);
        bgColor = const Color(0xFFFBBF24).withOpacity(0.15);
        text = _connectionState == CmdConnectionState.connecting ? '连接中...' : '登录中...';
        break;
      case CmdConnectionState.disconnected:
        dotColor = const Color(0xFF666666);
        bgColor = const Color(0xFF333333);
        text = '未连接';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: _connectionState == CmdConnectionState.loggedIn
                  ? [BoxShadow(color: dotColor, blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: _connectionState == CmdConnectionState.loggedIn
                  ? const Color(0xFF4ADE80)
                  : _connectionState == CmdConnectionState.disconnected
                      ? const Color(0xFF888888)
                      : const Color(0xFFFBBF24),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建标题栏按钮
  Widget _buildTitleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: const Color(0xFF888888)),
        ),
      ),
    );
  }

  /// 构建终端输出区域
  Widget _buildTerminalOutput() {
    return GestureDetector(
      onTap: () => _inputFocusNode.requestFocus(),
      child: Container(
        color: const Color(0xFF0C0C0C),
        padding: const EdgeInsets.all(8),
        child: ListView.builder(
          controller: _scrollController,
          itemCount: _outputLines.length,
          itemBuilder: (context, index) {
            final line = _outputLines[index];
            return SelectableText(
              line.text,
              style: TextStyle(
                color: line.color ?? const Color(0xFFCCCCCC),
                fontFamily: 'Consolas, "Courier New", monospace',
                fontSize: 14,
                height: 1.4,
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建输入行
  Widget _buildInputLine() {
    final isConnected = _connectionState == CmdConnectionState.loggedIn;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C0C),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        children: [
          // 提示符
          Text(
            '${widget.seatId}>',
            style: const TextStyle(
              color: Color(0xFFCCCCCC),
              fontFamily: 'Consolas, "Courier New", monospace',
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          // 输入框
          Expanded(
            child: Focus(
              onKeyEvent: _handleKeyEvent,
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                enabled: isConnected,
                onSubmitted: _onSubmit,
                style: const TextStyle(
                  color: Color(0xFFCCCCCC),
                  fontFamily: 'Consolas, "Courier New", monospace',
                  fontSize: 14,
                ),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: isConnected ? '' : '未连接...',
                  hintStyle: const TextStyle(color: Color(0xFF666666)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建状态栏
  Widget _buildStatusBar() {
    final netbar = ref.watch(currentNetbarProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3A))),
      ),
      child: Row(
        children: [
          // 左侧：IP 和座位 ID
          Text(
            _terminalIp ?? '-',
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
          const SizedBox(width: 8),
          const Text('|', style: TextStyle(color: Color(0xFF444444), fontSize: 12)),
          const SizedBox(width: 8),
          Text(
            widget.seatId,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
          ),
          const Spacer(),
          // 右侧：重连次数和编码
          if (_reconnectCount > 0) ...[
            Text(
              '重连次数: $_reconnectCount',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
            ),
            const SizedBox(width: 12),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_connectionState == CmdConnectionState.loggedIn)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                _connectionState == CmdConnectionState.loggedIn ? 'UTF-8' : '未连接',
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 终端行数据
class TerminalLine {
  final String text;
  final Color? color;
  final bool isSystem;
  final bool isCommand;

  TerminalLine({
    required this.text,
    this.color,
    this.isSystem = false,
    this.isCommand = false,
  });
}
