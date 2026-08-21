import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../../../shared/utils/top_notice.dart';
import '../../data/ptyshell/pty_controller.dart';
import '../../data/ptyshell/pty_session.dart';

/// 新版【终端命令】tab —— ptyshell 交互式远程终端（PowerShell / cmd）。
///
/// UI 按 ptyshell-demo（Vue 版 App.vue）1:1 还原，去掉连接面板与报文日志窗：
/// 多标签（上限 5、IndexedStack 保活）、shell 选择（默认/PS/CMD）、
/// 标签状态点（打开中/就绪/已结束）、双击（移动端长按）改名、字号调节、
/// 右键有选中即复制无选中即粘贴、移动端软键盘工具条。
///
/// 会话状态全部在 [PtyShellController]（详情页 State 持有，切顶层 tab 不销毁），
/// 本 widget 只做渲染——★Terminal 对象绝不能在 build 里 new（指南 §8.3）。
class PtyConsoleTab extends StatefulWidget {
  final PtyShellController controller;

  const PtyConsoleTab({super.key, required this.controller});

  @override
  State<PtyConsoleTab> createState() => _PtyConsoleTabState();
}

class _PtyConsoleTabState extends State<PtyConsoleTab> {
  PtyShellController get _ctrl => widget.controller;

  double _fontSize = 14;

  // 就地改名状态：空＝没有正在改名的标签
  String _renamingId = '';
  final TextEditingController _renameCtrl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _ctrl.onNote = (msg) {
      if (mounted) showTopNotice(context, msg, level: NoticeLevel.warning);
    };
    // 进入 tab 自动开第一个会话（缺省 shell），与 demo「连上即开」对齐；
    // 会话保活在 controller 里，切走再切回不会重复开。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ctrl.sessions.isEmpty) {
        _ctrl.openSession();
      }
    });
  }

  @override
  void dispose() {
    // controller 归详情页 State 所有（保活），这里只摘掉持有 context 的回调
    _ctrl.onNote = null;
    _renameCtrl.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0C0C0C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF3A3A3A)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildTabBar(),
              Expanded(child: _buildTerminalArea()),
              if (_isMobile) _buildKeyToolbar(),
            ],
          ),
        );
      },
    );
  }

  // ---------- 标签栏 ----------

  Widget _buildTabBar() {
    final canOpen = _ctrl.sessions.length < ptyMaxSessions;
    final active = _ctrl.activeSession;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in _ctrl.sessions) _buildTab(s),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ＋ 新建（缺省 shell：客户机先试 powershell 失败退 cmd）
          _barButton(
            icon: LucideIcons.plus,
            tooltip: canOpen ? '新建终端（默认 shell）' : '已达上限 $ptyMaxSessions 个',
            enabled: canOpen,
            onTap: () => _ctrl.openSession(),
          ),
          // ▾ 选 shell 再新建
          PopupMenuButton<String>(
            enabled: canOpen,
            tooltip: '选择 shell 再新建',
            color: const Color(0xFF2D2D2D),
            onSelected: (v) => _ctrl.openSession(shell: v == 'auto' ? null : v),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'auto',
                child: Text('默认（自动）',
                    style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
              ),
              PopupMenuItem(
                value: 'powershell',
                child: Text('PowerShell',
                    style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
              ),
              PopupMenuItem(
                value: 'cmd',
                child: Text('CMD',
                    style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13)),
              ),
            ],
            child: Container(
              width: 22,
              height: 28,
              alignment: Alignment.center,
              child: Icon(LucideIcons.chevronDown,
                  size: 13,
                  color: canOpen
                      ? const Color(0xFF888888)
                      : const Color(0xFF555555)),
            ),
          ),
          // Win7 降级提示：backend=pipe 无颜色/补全，平台限制不是故障
          if (active != null && active.backend == 'pipe') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('纯文本(Win7)',
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10)),
            ),
          ],
          const SizedBox(width: 8),
          // 字号调节（10-22，同 demo）
          const Icon(LucideIcons.type, size: 12, color: Color(0xFF888888)),
          SizedBox(
            width: 90,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: _fontSize,
                min: 10,
                max: 22,
                divisions: 12,
                onChanged: (v) => setState(() => _fontSize = v),
              ),
            ),
          ),
          Text('${_fontSize.round()}',
              style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildTab(PtySession s) {
    final isActive = s.id == _ctrl.activeId;
    final renaming = _renamingId == s.id;
    final dotColor = s.ended
        ? const Color(0xFF666666)
        : s.opening
            ? const Color(0xFFFBBF24)
            : const Color(0xFF4ADE80);
    return Tooltip(
      message:
          '会话 ${s.id}${s.shell.isNotEmpty ? ' · ${s.shell}' : ''}${s.backend.isNotEmpty ? ' · 后端 ${s.backend}' : ''}${s.ended ? ' · 已结束' : ''}',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () => _ctrl.setActive(s.id),
        onDoubleTap: _isMobile ? null : () => _startRename(s),
        onLongPress: _isMobile ? () => _startRename(s) : null,
        child: Container(
          margin: const EdgeInsets.only(right: 4, top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF0C0C0C) : const Color(0xFF222222),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(
                color:
                    isActive ? const Color(0xFF3A3A3A) : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              if (renaming)
                SizedBox(
                  width: 96,
                  child: Focus(
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        _cancelRename();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _renameCtrl,
                      focusNode: _renameFocus,
                      maxLength: 40,
                      style: const TextStyle(
                          color: Color(0xFFEEEEEE), fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _commitRename(),
                      onTapOutside: (_) => _commitRename(),
                    ),
                  ),
                )
              else ...[
                Text(
                  s.label,
                  style: TextStyle(
                    color: isActive
                        ? const Color(0xFFEEEEEE)
                        : const Color(0xFF999999),
                    fontSize: 12,
                    decoration: s.ended ? TextDecoration.lineThrough : null,
                    decorationColor: const Color(0xFF999999),
                  ),
                ),
                // shell 徽标：客户机回执报的**实际**起的 shell，与 backend 独立
                if (s.shell.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      s.shell == 'powershell' ? 'PS' : 'CMD',
                      style: const TextStyle(
                          color: Color(0xFF999999), fontSize: 9),
                    ),
                  ),
                ],
              ],
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _ctrl.closeSession(s.id),
                child: const Icon(LucideIcons.x,
                    size: 11, color: Color(0xFF888888)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 14,
              color: enabled
                  ? const Color(0xFF888888)
                  : const Color(0xFF555555)),
        ),
      ),
    );
  }

  // ---------- 改名 ----------

  void _startRename(PtySession s) {
    setState(() {
      _renamingId = s.id;
      _renameCtrl.text = s.label;
      _renameCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _renameCtrl.text.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _renameFocus.requestFocus());
  }

  /// 提交改名。空白名回退默认 #N（controller 里 trim 后清空 custom）。
  void _commitRename() {
    if (_renamingId.isEmpty) return;
    _ctrl.renameSession(_renamingId, _renameCtrl.text);
    setState(() => _renamingId = '');
  }

  void _cancelRename() {
    if (_renamingId.isEmpty) return;
    setState(() => _renamingId = '');
  }

  // ---------- 终端区 ----------

  Widget _buildTerminalArea() {
    if (_ctrl.sessions.isEmpty) {
      return const Center(
        child: Text(
          '点「＋」新建终端会话（最多 $ptyMaxSessions 个）',
          style: TextStyle(color: Color(0xFF666666), fontSize: 13),
        ),
      );
    }
    // ★IndexedStack 全部子树常驻：切标签只换显示的那个，滚动缓冲和终端状态都在。
    // 不能用 TabBarView/PageView——它们销毁离屏页面，切回来终端就空了（指南 §8.3）。
    return IndexedStack(
      index: _ctrl.activeIndex,
      children: [
        for (final s in _ctrl.sessions)
          xterm.TerminalView(
            s.terminal,
            key: ValueKey(s.id),
            controller: s.viewController,
            autofocus: s.id == _ctrl.activeId,
            padding: const EdgeInsets.all(6),
            theme: xterm.TerminalThemes.defaultTheme,
            textStyle: xterm.TerminalStyle(
              fontSize: _fontSize,
              fontFamily: 'Cascadia Mono',
              fontFamilyFallback: const ['Consolas', 'Courier New', 'monospace'],
            ),
            // 右键：有选中即复制，无选中即粘贴（终端老习惯，同 demo）
            onSecondaryTapDown:
                _isMobile ? null : (details, offset) => _onSecondaryTap(s),
          ),
      ],
    );
  }

  Future<void> _onSecondaryTap(PtySession s) async {
    final sel = s.viewController.selection;
    if (sel != null) {
      final text = s.terminal.buffer.getText(sel);
      await Clipboard.setData(ClipboardData(text: text));
      s.viewController.clearSelection();
      if (mounted) {
        showTopNotice(context, '已复制 ${text.length} 个字符',
            level: NoticeLevel.success);
      }
      return;
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && !s.ended) {
      // paste 会按 bracketed-paste 模式交给 shell，最终经 onOutput → ptyIn 发出
      s.terminal.paste(text);
    }
  }

  // ---------- 移动端软键盘工具条 ----------

  /// 软键盘没有 Esc/Tab/Ctrl/方向键，自建一条工具条直发控制字节（指南 §10.3）。
  Widget _buildKeyToolbar() {
    const keys = <(String, String)>[
      ('Esc', '\x1b'),
      ('Tab', '\t'),
      ('Ctrl+C', '\x03'),
      ('↑', '\x1b[A'),
      ('↓', '\x1b[B'),
      ('←', '\x1b[D'),
      ('→', '\x1b[C'),
    ];
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF3A3A3A))),
      ),
      child: Row(
        children: [
          for (final (label, seq) in keys)
            Expanded(
              child: InkWell(
                onTap: () => _ctrl.sendInputToActive(seq),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(
                          color: Color(0xFFCCCCCC), fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
