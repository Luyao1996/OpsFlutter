import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xterm/xterm.dart' as xterm;

/// 一个 ptyshell 终端会话 = 一个 xterm Terminal + 一条**独立的** UTF-8 流式解码管道。
///
/// ★为什么必须流式解码（实现指南-Flutter.md §6.2，本功能最关键的一节）：
/// xterm.dart 的写入接口是 `write(String)` 只吃字符串，而终端输出是 UTF-8 字节流，
/// 客户机按 16ms/32KB 双阈值聚合发送、WS 还可能再分片——一个汉字被劈进两帧是常态。
/// 每帧独立 `utf8.decode` 会在劈开处产生不可逆的 U+FFFD 乱码；
/// `Utf8Decoder` 的流式转换内部有跨块状态机，能把上一块结尾的半个字符留到下一块拼回。
///
/// ★为什么必须一会话一解码器：解码器持有"上一块结尾的残缺字节"这个状态，
/// 两个会话共用会把 A 的半个汉字和 B 的下一块字节拼在一起，两边同时乱码且极难排查。
class PtySession {
  PtySession({
    required this.id,
    required this.seat,
    required this.title,
  }) {
    // allowMalformed: true —— 真正被劈开的字符由状态机拼回，剩下的非法字节退化成 �，
    // 而不是抛异常把整条流打断（终端流里出现二进制垃圾并不罕见）。
    _decodeSub = _bytes.stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);
  }

  /// 会话 id（即 peer 信封顶层 id，>10 且 ≤255 字节，见协议手册 §1.3③）。
  final String id;

  /// 目标客户机机号。
  final String seat;

  /// 默认标签名（#N，序号只增不减）。
  final String title;

  /// 用户双击/长按改过的名字；空＝跟随默认名 [title]。
  String custom = '';

  /// 滚动缓冲 5000 行：运维看长输出要往回翻，默认 1000 行偏少（指南 §7.1）。
  final xterm.Terminal terminal = xterm.Terminal(maxLines: 5000);

  /// 选区/复制状态，供 TerminalView 使用。
  final xterm.TerminalController viewController = xterm.TerminalController();

  /// ptyOpen 回执报的底层后端："conpty" | "pipe"（Win7 降级，纯文本）| ''（未回执）。
  String backend = '';

  /// ptyOpen 回执报的**实际起的** shell："powershell" | "cmd" | ''（未回执）。
  /// ★与 backend 是两个独立维度：Win7 机器 backend 必为 "pipe"，但 shell 仍可自选。
  String shell = '';

  /// 尚未收到 ptyOpen 回执（此期间禁止发 ptyResize，会撞 code=2）。
  bool opening = true;

  /// shell 已结束（收到 ptyExit / 断线 / 开会话失败）。
  bool ended = false;

  int? exitCode;

  /// 收发流订阅（requestStream 的返回流），由 controller 挂上并负责取消。
  StreamSubscription<dynamic>? sub;

  final StreamController<List<int>> _bytes = StreamController<List<int>>();
  late final StreamSubscription<String> _decodeSub;

  /// 显示名：改过用自定义名，否则默认 #N。
  String get label => custom.isNotEmpty ? custom : title;

  /// 收到的二进制帧原始字节丢进解码管道。★不要在外面 decode。
  void feed(Uint8List data) {
    if (_bytes.isClosed) return;
    _bytes.add(data);
  }

  /// shell 结束时写一行黄字提示，让用户明白是结束了而不是卡死。
  void writeExitNotice(int code) =>
      terminal.write('\r\n\x1b[33m[会话已结束，退出码 $code]\x1b[0m\r\n');

  Future<void> dispose() async {
    await sub?.cancel();
    sub = null;
    await _bytes.close();
    await _decodeSub.cancel();
    viewController.dispose();
  }
}
