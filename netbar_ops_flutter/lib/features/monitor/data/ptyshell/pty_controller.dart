import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/network/task_ws.dart';
import 'pty_session.dart';

/// 与客户机侧 ptyMaxSessions 保持一致（NetbarOpsClient internal/client/ptymanager.go:24）。
const int ptyMaxSessions = 5;

/// 会话 id 下限：server 用 `len(taskID) > 10` 区分云端会话与本地连接号
/// （wshandler.go:84），太短回执被**静默丢弃**；上限来自二进制帧头 id_len 只有 1 字节。
const int _minSessionIdBytes = 11;
const int _maxSessionIdBytes = 255;

/// ptyshell 会话管理器：一个终端详情页一个实例，详情页存活期间保活
/// （切顶层 tab 不销毁），页面/独立窗关闭时 [closeAllSessions]。
///
/// 走全局 [TaskWs] peer 通道，不新建 WS 连接：
///   下行 ptyOpen/ptyIn/ptyResize/ptyClose 复用 peer 信封（seat 在 data 里）；
///   上行 JSON 回执与 ptyshell 二进制输出帧都按会话 id 路由到 requestStream 的流上
///   （task_ws_client.dart 的 _onBinaryFrame ptyshell 分支 / _isStreamEnd ptyExit 分支）。
class PtyShellController extends ChangeNotifier {
  PtyShellController({
    required this.ws,
    required this.seat,
    required this.merchantId,
    this.onNote,
  });

  final TaskWs ws;
  final String seat;
  final int merchantId;

  /// 面向用户的提示（toast），由 UI 层挂接。
  void Function(String msg)? onNote;

  final List<PtySession> sessions = [];
  String activeId = '';

  /// 标签默认名序号，只增不减（关掉中间标签再新建也不会重名，同 demo tabSeq）。
  int _tabSeq = 0;

  /// 会话 id 序号（与 _tabSeq 独立：id 要求全局唯一，名字要求人眼不重号）。
  int _seq = 0;

  bool _disposed = false;

  /// 回执错误码 → 用户可读提示（协议手册 §1.4）。
  static const Map<int, String> _codeText = {
    1: '通用失败',
    2: '会话不存在',
    4: '已达并发上限 $ptyMaxSessions 个会话，请先关闭一个',
    5: '会话 id 非法',
    6: 'shell 不在白名单（仅 powershell/cmd）',
  };

  static String _codeMsg(int code, String msg) =>
      _codeText[code] ?? (msg.isNotEmpty ? msg : '错误码 $code');

  int get activeIndex {
    final i = sessions.indexWhere((s) => s.id == activeId);
    return i < 0 ? 0 : i;
  }

  PtySession? get activeSession {
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  /// 开一个终端会话。返回会话 id；超上限或 id 非法返回 null（原因已 toast）。
  ///
  /// [shell] 可选：'powershell' | 'cmd'。**留空＝缺省**（客户机先试 powershell、
  /// 失败退回 cmd）；白名单外的值客户机拒绝（code=6）且不启动任何进程。
  String? openSession({String? shell}) {
    if (_disposed) return null;
    if (sessions.length >= ptyMaxSessions) {
      _note('已达并发上限 $ptyMaxSessions 个会话，请先关闭一个');
      return null;
    }
    final id = '$seat-pty-${DateTime.now().millisecondsSinceEpoch}-${++_seq}';
    final idBytes = utf8.encode(id).length;
    if (idBytes < _minSessionIdBytes || idBytes > _maxSessionIdBytes) {
      // 生成规则已保证长度，理论走不到；防御性拦截以免回执被 server 静默丢弃
      _note('会话 id 非法（$idBytes 字节），已取消');
      return null;
    }

    final session = PtySession(id: id, seat: seat, title: '#${++_tabSeq}');

    // 输入：onOutput 给的是要发给 pty 的字符串（已含 ESC 序列/控制字符），
    // ★一个字节都不要加工——"顺手补个换行"会把 Tab 补全变成「Tab 然后回车」。
    session.terminal.onOutput = (data) {
      if (session.ended) return; // 已结束不再发，免得堆无效请求
      sendInput(id, data);
    };
    // 尺寸：回执前发 ptyResize 会撞 code=2，守卫挡掉（补发靠 _onOpened）。
    session.terminal.onResize = (w, h, pw, ph) {
      if (session.opening || session.ended) return;
      resize(id, w, h);
    };

    // widget 还没布局，先给估算值；ptyOpen 回执后确定性补发真实尺寸（§8.1）
    final stream = ws.requestStream(
      fun: 'ptyOpen',
      seat: seat,
      merchantId: merchantId,
      data: {
        'cols': 120,
        'rows': 30,
        if (shell != null) 'shell': shell,
      },
      sessionId: id,
    );
    session.sub = stream.listen(
      (msg) => _onStreamEvent(session, msg),
      onError: (Object e) => _onStreamBroken(session, 'error: $e'),
      onDone: () => _onStreamBroken(session, 'done'),
    );

    sessions.add(session);
    activeId = id;
    _log('INFO', 'open', id, 'shell=${shell ?? '(auto)'} seat=$seat');
    notifyListeners();
    return id;
  }

  /// 会话流上的元素：二进制帧 data（终端输出字节）或 JSON 回执载荷（Map）。
  void _onStreamEvent(PtySession s, dynamic msg) {
    if (msg is Uint8List) {
      s.feed(msg);
      return;
    }
    if (msg is List<int>) {
      s.feed(Uint8List.fromList(msg));
      return;
    }
    if (msg is! Map) return;
    final fun = (msg['fun'] ?? '').toString();
    // code 兼容数字与字符串两种形态（旧版 cmd 回执实测出现过 '0' 字符串）
    final code = int.tryParse('${msg['code'] ?? 0}') ?? 0;
    final tip = (msg['msg'] ?? '').toString();

    switch (fun) {
      case 'ptyOpen':
        if (code != 0) {
          _log('WARN', 'open-fail', s.id, 'code=$code msg=$tip');
          _note('开会话失败：${_codeMsg(code, tip)}');
          _removeSession(s);
          return;
        }
        final inner = msg['data'];
        s
          ..backend = (inner is Map ? inner['backend'] ?? '' : '').toString()
          ..shell = (inner is Map ? inner['shell'] ?? '' : '').toString()
          ..opening = false;
        _log('INFO', 'opened', s.id, 'backend=${s.backend} shell=${s.shell}');
        notifyListeners();
        // ★会话就绪后**确定性补发**一次真实尺寸（指南 §8.1，踩过坑）：
        // TerminalView 首次布局早已把 Terminal 调到真实尺寸并触发过 onResize，
        // 但那一刻 opening 还是 true 被守卫挡掉；回执到达后尺寸不再变化 ⇒
        // onResize 不会再触发 ⇒ 不补发 ConPTY 就停在 120x30 估算值上花屏。
        // postFrame 确保 TerminalView 完成至少一帧布局后再读 viewWidth/viewHeight。
        // 客户机侧 Resize 幂等，多发无害，★不要加「与上次相同就跳过」的去重。
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_disposed || s.ended) return;
          final cols = s.terminal.viewWidth;
          final rows = s.terminal.viewHeight;
          if (cols > 0 && rows > 0) resize(s.id, cols, rows);
        });
        return;
      case 'ptyExit':
        final inner = msg['data'];
        final ec =
            (inner is Map && inner['code'] is int) ? inner['code'] as int : code;
        _log('INFO', 'exit', s.id, 'code=$ec');
        _markEnded(s, ec);
        return; // 流随后被 _isStreamEnd 关闭，onDone 里有 ended 守卫
      case 'ptyIn':
      case 'ptyResize':
      case 'ptyClose':
        if (code != 0 && code != 2) {
          // code=2（会话不存在）多为对已结束会话的尾包指令，静默即可
          _log('WARN', 'reply', s.id, '$fun 失败 code=$code msg=$tip');
        }
        return;
    }
  }

  /// 流异常/断开：链路断了客户机侧会 CloseAll，本端同步标记结束（同 demo _onDone）。
  /// 重连后会话**不可恢复**，需用户重开（指南 §14）。
  void _onStreamBroken(PtySession s, String reason) {
    if (s.ended) return;
    _log('WARN', 'broken', s.id, 'opening=${s.opening} reason=$reason');
    if (s.opening) {
      // 回执都没等到（通道未就绪/鉴权失败），标签留着没意义，直接移除
      _note('开会话失败：通道未就绪或已断开');
      _removeSession(s);
      return;
    }
    _markEnded(s, -1);
  }

  void _markEnded(PtySession s, int code) {
    if (s.ended) return;
    s
      ..ended = true
      ..exitCode = code;
    s.writeExitNotice(code);
    notifyListeners();
  }

  void _removeSession(PtySession s) {
    sessions.remove(s);
    if (activeId == s.id) {
      activeId = sessions.isEmpty ? '' : sessions.last.id;
    }
    s.dispose();
    notifyListeners();
  }

  /// 发按键流。★UTF-8 编码后 base64，原样送达客户机不加工；quiet 抑制逐帧日志。
  void sendInput(String sessionId, String text) {
    ws
        .fireAndForget(
          fun: 'ptyIn',
          seat: seat,
          merchantId: merchantId,
          data: {'b': base64Encode(utf8.encode(text))},
          sessionId: sessionId,
          quiet: true,
        )
        .catchError((Object e) => _log('WARN', 'input', sessionId, 'send_failed: $e'));
  }

  /// 移动端软键盘工具条：向当前活动会话发控制序列。
  void sendInputToActive(String text) {
    final s = activeSession;
    if (s == null || s.ended || s.opening) return;
    sendInput(s.id, text);
  }

  void resize(String sessionId, int cols, int rows) {
    ws
        .fireAndForget(
          fun: 'ptyResize',
          seat: seat,
          merchantId: merchantId,
          data: {'cols': cols, 'rows': rows},
          sessionId: sessionId,
        )
        .catchError((Object e) => _log('WARN', 'resize', sessionId, 'send_failed: $e'));
  }

  void setActive(String sessionId) {
    if (activeId == sessionId) return;
    activeId = sessionId;
    notifyListeners();
  }

  /// 标签改名：空白回退默认名 #N（清空 custom），不留看不见名字的标签。
  void renameSession(String sessionId, String name) {
    for (final s in sessions) {
      if (s.id == sessionId) {
        s.custom = name.trim();
        notifyListeners();
        return;
      }
    }
  }

  /// 关一个会话（用户点 ✕）。已 ended 的只清 UI，不再发 ptyClose
  /// （shell 早退了，再发只会换回 code=2）。
  void closeSession(String sessionId) {
    final i = sessions.indexWhere((s) => s.id == sessionId);
    if (i < 0) return;
    final s = sessions[i];
    if (!s.ended) {
      ws
          .fireAndForget(
            fun: 'ptyClose',
            seat: seat,
            merchantId: merchantId,
            sessionId: sessionId,
            quiet: true,
          )
          .catchError((Object e) => _log('WARN', 'close', sessionId, 'send_failed: $e'));
    }
    s.ended = true; // 防 onDone/onError 再补一条结束提示
    sessions.removeAt(i);
    if (activeId == sessionId) {
      activeId = sessions.isEmpty
          ? ''
          : sessions[i < sessions.length ? i : sessions.length - 1].id;
    }
    s.dispose();
    _log('INFO', 'close', sessionId, 'left=${sessions.length}');
    notifyListeners();
  }

  /// 关掉全部会话。★页面/独立窗关闭前调用，且全同步不 await：
  /// 客户机侧的 CloseAll 挂在 client↔server 断链上，本端退出断的是 App↔云端
  /// 那一段，不主动发 ptyClose 客户机上的 shell 会残留到 5 分钟空闲回收
  /// （反复开关几轮就把上限 5 占满，新会话全被 code=4 拒掉，指南 §8.2）。
  int closeAllSessions() {
    var n = 0;
    for (final s in sessions) {
      if (!s.ended) {
        s.ended = true;
        ws
            .fireAndForget(
              fun: 'ptyClose',
              seat: seat,
              merchantId: merchantId,
              sessionId: s.id,
              quiet: true,
            )
            .catchError((Object _) {});
        n++;
      }
      s.dispose();
    }
    sessions.clear();
    activeId = '';
    if (n > 0) _log('INFO', 'close-all', '-', 'sent=$n');
    if (!_disposed) notifyListeners();
    return n;
  }

  void _note(String msg) {
    _log('INFO', 'note', '-', msg);
    onNote?.call(msg);
  }

  void _log(String level, String operType, String contextId, String msg) {
    debugPrint(
        '[${DateTime.now().toIso8601String()}][$level][pty_controller][$operType][$contextId] $msg');
  }

  @override
  void dispose() {
    _disposed = true;
    closeAllSessions();
    super.dispose();
  }
}
