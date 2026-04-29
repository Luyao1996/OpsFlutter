import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/network/task_ws.dart';
import '../../../../core/network/task_ws_provider.dart';
import '../../../../features/logs/data/operation_log_api.dart';
import '../../../../shared/providers/app_providers.dart';

/// 连接状态
enum CmdConnectionState {
  disconnected, // 未连接
  connecting, // 连接中
  connected, // 已连接（WebSocket 已建立，但未登录）
  loggedIn, // 已登录（可以执行命令）
}

/// 终端命令 Tab —— 走全局 WebSocket 任务通道（[TaskWs]）。
///
/// 与 toolboxPage `XtermCmdDialog.vue` 对齐：
/// - `cmdlogin` 通过 [TaskWs.requestStream] 拿到主流，承载后续所有命令输出
/// - `cmdRun` / `cmdlogout` 走 [TaskWs.fireAndForget]（服务端不会用同 id 单回包）
/// - 命令输出事件名兼容 `cmdRun` 与 `cmdReply`
/// - 注销通过 `cmdlogon code=0` 表示流终止（已在 [TaskWsClient._isStreamEnd] 处理）
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

  // CMD 主流订阅（cmdlogin 流：承载所有 cmdRun/cmdReply/cmdlogon 事件）
  StreamSubscription<dynamic>? _cmdSub;
  CmdConnectionState _connectionState = CmdConnectionState.disconnected;

  // CMD 会话 id：cmdlogin/cmdRun/Ctrl+C/cmdlogout 必须复用同一个 id，
  // 否则后端找不到对应 CMD session 返回 `code:2 没有找到对应的CMD执行接口`。
  // 与 toolboxPage `XtermCmdDialog.vue:137-140` 的 wsSessionId 协议对齐。
  // 每次 _loginCmd 重新生成（重连等价于新会话）。
  String? _cmdSessionId;

  // 命令历史
  final List<String> _cmdHistory = [];
  int _cmdHistoryIndex = -1;

  // 终端信息
  String? _terminalIp;

  // WS 全局状态监听器
  ProviderSubscription<AsyncValue<TaskWsState>>? _wsStateSub;

  // 是否已上报 connect 操作日志（避免重连时重复上报）
  bool _connectLogReported = false;

  // 在 initState 阶段缓存 OperationLogApi 实例：
  // dispose 完成后 ref 会被标记为 disposed，此时若再调 ref.read 会抛 StateError。
  // 缓存到 final 字段后，dispose 内部仍可安全使用。
  late final OperationLogApi _operationLogApi;

  TaskWs get _ws => ref.read(taskWsProvider);
  int? get _merchantId => ref.read(currentNetbarProvider).id;

  @override
  void initState() {
    super.initState();
    _operationLogApi = ref.read(operationLogApiProvider);
    _initTerminal();
    // 监听全局 WS 状态：ready 后若尚未登录则自动重 cmdlogin
    _wsStateSub = ref.listenManual<AsyncValue<TaskWsState>>(
      taskWsStateProvider,
      (prev, next) {
        next.whenData((s) {
          if (s == TaskWsState.ready &&
              _connectionState != CmdConnectionState.loggedIn) {
            _loginCmd();
          } else if (s == TaskWsState.closed ||
              s == TaskWsState.authFailed) {
            if (mounted &&
                _connectionState == CmdConnectionState.loggedIn) {
              setState(
                  () => _connectionState = CmdConnectionState.disconnected);
              _addSystemLine('[系统] 通道断开，等待自动重连',
                  color: Colors.amber);
            }
          }
        });
      },
    );
    _connect();
  }

  @override
  void dispose() {
    _wsStateSub?.close();
    _cmdSub?.cancel();
    // 上报断开（不 await；不阻塞 dispose）
    // 必须用缓存的 _operationLogApi，不能再 ref.read（此时 ref 已 disposed）
    if (_connectLogReported) {
      _operationLogApi.add(
        event: 'command.disconnect',
        description: '断开远程CMD: ${widget.seatId}',
      );
    }
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

  /// 建立 CMD 通道：先确保全局 WS 就绪，再发 cmdlogin 拿主流
  Future<void> _connect() async {
    if (mounted) {
      setState(() => _connectionState = CmdConnectionState.connecting);
    }
    try {
      await _ws.ensureConnected();
      if (!mounted) return;
      setState(() => _connectionState = CmdConnectionState.connected);
      _addSystemLine('[系统] 任务通道已就绪', color: Colors.green);
      _loginCmd();
    } catch (e) {
      if (!mounted) return;
      setState(() => _connectionState = CmdConnectionState.disconnected);
      _addSystemLine('[错误] 通道连接失败: $e', color: Colors.red);
    }
  }

  /// 发送 cmdlogin，并订阅服务端在该 id 上推回的所有事件
  void _loginCmd() {
    final mid = _merchantId;
    if (mid == null) {
      _addSystemLine('[错误] 当前网吧 id 为空，无法登录命令通道',
          color: Colors.red);
      return;
    }
    if (_connectionState == CmdConnectionState.loggedIn) return;

    _addSystemLine('[系统] 正在登录 seat=${widget.seatId}',
        color: Colors.grey);

    _cmdSub?.cancel();
    // 每次登录都生成新的 sessionId（重连等价于新会话），与 toolboxPage 一致
    _cmdSessionId = _ws.generateSessionId();
    final stream = _ws.requestStream(
      fun: 'cmdlogin',
      seat: widget.seatId,
      merchantId: mid,
      data: const {},
      sessionId: _cmdSessionId,
    );
    _cmdSub = stream.listen(
      _onCmdEvent,
      onError: (Object e) {
        if (!mounted) return;
        _addSystemLine('[错误] 命令通道异常: $e', color: Colors.red);
        setState(() => _connectionState = CmdConnectionState.disconnected);
      },
      onDone: () {
        if (!mounted) return;
        if (_connectionState == CmdConnectionState.loggedIn) {
          _addSystemLine('[系统] 命令通道已关闭', color: Colors.amber);
        }
        setState(() => _connectionState = CmdConnectionState.disconnected);
      },
    );
  }

  /// 处理 cmdlogin 主流上推回的所有事件
  void _onCmdEvent(dynamic msg) {
    if (msg is! Map) return;
    final fun = msg['fun'];
    final code = msg['code'];
    final tip = msg['msg'];
    final data = msg['data'];

    if (fun == 'cmdlogin') {
      if (code == 0 || code == '0') {
        if (!mounted) return;
        setState(() => _connectionState = CmdConnectionState.loggedIn);
        _addSystemLine('[系统] 登录成功', color: Colors.green);
        _addLine('');
        _addPrompt();
        // 仅首次登录时上报 connect（重连不重复上报）
        if (!_connectLogReported) {
          _connectLogReported = true;
          _operationLogApi.add(
            event: 'command.connect',
            description: '远程CMD: ${widget.seatId}',
          );
        }
      } else {
        if (!mounted) return;
        setState(() => _connectionState = CmdConnectionState.connected);
        _addSystemLine('[错误] 登录失败: ${tip ?? '未知错误'}',
            color: Colors.red);
      }
      return;
    }

    // 命令输出：兼容 cmdRun（toolboxPage frp 模式）/ cmdReply（后端转发模式）
    if (fun == 'cmdRun' || fun == 'cmdReply') {
      final output = (data is Map ? data['msg'] : null) ?? tip ?? '';
      final outStr = output.toString();
      if (outStr.isNotEmpty) {
        for (final line in outStr.split('\n')) {
          _addLine(line);
        }
      }
      return;
    }

    if (fun == 'cmdlogon') {
      if (code == 0 || code == '0') {
        if (!mounted) return;
        _addSystemLine('[系统] 已注销', color: Colors.amber);
        setState(() => _connectionState = CmdConnectionState.connected);
      } else {
        if (!mounted) return;
        _addSystemLine('[错误] 注销失败: ${tip ?? ''}', color: Colors.red);
      }
      return;
    }

    // 其他消息
    _addSystemLine('[消息] $msg', color: Colors.grey);
  }

  /// 发送命令（fire-and-forget；输出从 cmdlogin 主流回）
  void _sendCommand(String cmd) {
    if (_connectionState != CmdConnectionState.loggedIn) {
      _addSystemLine('[错误] 未连接到远程终端', color: Colors.red);
      return;
    }
    final mid = _merchantId;
    if (mid == null) return;

    _addLine('${widget.seatId}>$cmd', isCommand: true);

    if (cmd.trim().isNotEmpty) {
      if (_cmdHistory.isEmpty || _cmdHistory.last != cmd) {
        _cmdHistory.add(cmd);
      }
      _cmdHistoryIndex = _cmdHistory.length;
    }

    _ws.fireAndForget(
      fun: 'cmdRun',
      seat: widget.seatId,
      merchantId: mid,
      data: {'cmd': cmd},
      sessionId: _cmdSessionId, // 复用 cmdlogin 的会话 id
    ).catchError((Object e) {
      if (!mounted) return;
      _addSystemLine('[错误] 发送失败: $e', color: Colors.red);
    });
  }

  /// 发送 Ctrl+C 中断
  void _sendCtrlC() {
    if (_connectionState != CmdConnectionState.loggedIn) return;
    final mid = _merchantId;
    if (mid == null) return;
    _addLine('^C');
    _ws.fireAndForget(
      fun: 'cmdRun',
      seat: widget.seatId,
      merchantId: mid,
      data: {'cmd': '\x03'},
      sessionId: _cmdSessionId, // 复用 cmdlogin 的会话 id
    ).catchError((Object e) {
      if (!mounted) return;
      _addSystemLine('[错误] 中断发送失败: $e', color: Colors.red);
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
    if (!mounted) return;
    setState(() {
      _outputLines.add(TerminalLine(text: text, isCommand: isCommand));
    });
    _scrollToBottom();
  }

  /// 添加系统消息行
  void _addSystemLine(String text, {Color? color}) {
    if (!mounted) return;
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

  /// 手动重连：取消当前订阅，再走一次 _connect
  void _manualReconnect() {
    _cmdSub?.cancel();
    _cmdSub = null;
    if (mounted) {
      setState(() => _connectionState = CmdConnectionState.disconnected);
    }
    _connect();
  }

  /// 主动注销 CMD 会话
  void _disconnect() {
    final mid = _merchantId;
    if (_connectionState == CmdConnectionState.loggedIn && mid != null) {
      _ws.fireAndForget(
        fun: 'cmdlogout',
        seat: widget.seatId,
        merchantId: mid,
        data: const {},
        sessionId: _cmdSessionId, // 复用 cmdlogin 的会话 id
      ).catchError((Object _) {});
    }
    _cmdSub?.cancel();
    _cmdSub = null;
    _cmdSessionId = null;
    if (!mounted) return;
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
          Flexible(
            child: Text(
              '命令提示符 - ${widget.seatId}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
          // 右侧：编码状态
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
