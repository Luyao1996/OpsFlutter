import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:xterm/xterm.dart' as xterm;

import '../../../../core/network/task_ws.dart';
import '../../../../shared/utils/top_notice.dart';
import '../../data/ptyshell/pty_controller.dart';
import '../../data/ptyshell/pty_session.dart';

// ---------- demo 调色板（1:1 对齐 ptyshell-demo src/styles/main.css 的 CSS 变量） ----------
const _bg1 = Color(0xFF1C1F26); // 面板（标签栏底）
const _bg2 = Color(0xFF232730); // 非激活标签 / 输入框
const _bg3 = Color(0xFF2C313C); // hover / 徽标底
const _fg0 = Color(0xFFD7DAE0); // 主文字
const _fg1 = Color(0xFF9AA0AB); // 次要文字
const _fg2 = Color(0xFF6B7280); // 更次要
const _accent = Color(0xFF4DD0E1); // 强调青
const _ok = Color(0xFF66BB6A);
const _warn = Color(0xFFFFA726);
const _danger = Color(0xFFEF5350);
const _border = Color(0xFF2F343F);
const _termBg = Color(0xFF14161A); // 终端底

/// 终端主题：demo TerminalPane.vue 的 xterm.js theme 逐色对齐
/// （background/foreground/cursor/selection/black/brightBlack），
/// 其余 ANSI 颜色沿用 xterm.dart TerminalThemes.defaultTheme 原值。
const _demoTheme = xterm.TerminalTheme(
  cursor: Color(0xFF4DD0E1),
  selection: Color(0xAA33405A),
  foreground: Color(0xFFD7DAE0),
  background: Color(0xFF14161A),
  black: Color(0xFF16181D),
  red: Color(0xFFCD3131),
  green: Color(0xFF0DBC79),
  yellow: Color(0xFFE5E510),
  blue: Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan: Color(0xFF11A8CD),
  white: Color(0xFFE5E5E5),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFF14C4C),
  brightGreen: Color(0xFF23D18B),
  brightYellow: Color(0xFFF5F543),
  brightBlue: Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan: Color(0xFF29B8DB),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFFF2B),
  searchHitBackgroundCurrent: Color(0xFF31FF26),
  searchHitForeground: Color(0xFF000000),
);

/// 新版【终端命令】tab —— ptyshell 交互式远程终端（PowerShell / cmd）。
///
/// UI 按 ptyshell-demo（Vue 版 App.vue + main.css）1:1 还原，去掉连接面板与
/// 报文日志窗（用户拍板不做）：多标签（上限 5、IndexedStack 保活）、shell 选择、
/// 标签状态点、双击（移动端长按）改名、连接状态、字号调节、应用内最大化、
/// 右键有选中即复制无选中即粘贴、移动端软键盘工具条。
///
/// 会话状态全部在 [PtyShellController]（详情页 State 持有，切顶层 tab 不销毁），
/// 本 widget 只做渲染——★Terminal 对象绝不能在 build 里 new（指南 §8.3）。
class PtyConsoleTab extends StatefulWidget {
  final PtyShellController controller;

  /// 应用内全屏态（复用游戏管理的机制：布局由 terminal_detail_page 顶层判定，
  /// 本 widget 只负责按钮图标与回调；controller 不变 ⇒ 切换全屏会话保活）。
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  const PtyConsoleTab({
    super.key,
    required this.controller,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });

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
            color: _termBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _border),
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

  // ---------- 标签栏（demo .tabbar：padding 6/12、bg1 底、border 底边） ----------

  Widget _buildTabBar() {
    final canOpen = _ctrl.sessions.length < ptyMaxSessions;
    final active = _ctrl.activeSession;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: _bg1,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          // 标签区：可收缩横向滚动。★Flexible 而非 Expanded——标签少时不占满，
          // ＋/▾ 才能紧跟在最后一个标签后面（demo 的 .newtab-wrap 布局）。
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in _ctrl.sessions) _buildTab(s),
                ],
              ),
            ),
          ),
          // ＋ 新建（缺省 shell：客户机先试 powershell 失败退 cmd）＋ ▾ 选 shell，
          // 紧跟标签之后（demo .newtab-wrap margin-right:auto 分组）
          _barButton(
            icon: LucideIcons.plus,
            tooltip: canOpen ? '新建终端（默认 shell）' : '已达上限 $ptyMaxSessions 个',
            enabled: canOpen,
            onTap: () => _ctrl.openSession(),
          ),
          PopupMenuButton<String>(
            enabled: canOpen,
            tooltip: '选择 shell 再新建',
            color: _bg2,
            onSelected: (v) => _ctrl.openSession(shell: v == 'auto' ? null : v),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'auto',
                child: Text('默认（自动）',
                    style: TextStyle(color: _fg0, fontSize: 13)),
              ),
              PopupMenuItem(
                value: 'powershell',
                child:
                    Text('PowerShell', style: TextStyle(color: _fg0, fontSize: 13)),
              ),
              PopupMenuItem(
                value: 'cmd',
                child: Text('CMD', style: TextStyle(color: _fg0, fontSize: 13)),
              ),
            ],
            child: Container(
              width: 22,
              height: 28,
              alignment: Alignment.center,
              child: Icon(LucideIcons.chevronDown,
                  size: 13, color: canOpen ? _fg1 : _fg2),
            ),
          ),
          const Spacer(),
          // Win7 降级提示：backend=pipe 无颜色/补全，平台限制不是故障
          if (active != null && active.backend == 'pipe') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _warn.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('纯文本(Win7)',
                  style: TextStyle(color: _warn, fontSize: 10)),
            ),
            const SizedBox(width: 10),
          ],
          // 连接状态（demo .state：通道状态文字），跟随全局任务通道
          StreamBuilder<TaskWsState>(
            stream: _ctrl.ws.state,
            initialData: _ctrl.ws.currentState,
            builder: (context, snap) => _buildWsState(snap.data),
          ),
          const SizedBox(width: 12),
          // 字号调节（demo .fs：「字号」文字 + 滑条 + 数值）
          const Text('字号', style: TextStyle(color: _fg1, fontSize: 12)),
          SizedBox(
            width: 90,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                activeTrackColor: _accent,
                inactiveTrackColor: _bg3,
                thumbColor: _accent,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
              style: const TextStyle(color: _fg1, fontSize: 11)),
          // 应用内最大化：铺满整个终端详情窗口（同游戏管理的全屏机制）
          if (widget.onToggleFullscreen != null) ...[
            const SizedBox(width: 6),
            _barButton(
              icon: widget.isFullscreen
                  ? LucideIcons.minimize2
                  : LucideIcons.maximize2,
              tooltip: widget.isFullscreen ? '还原' : '最大化',
              onTap: widget.onToggleFullscreen!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWsState(TaskWsState? s) {
    final (text, color) = switch (s) {
      TaskWsState.ready => ('已连接', _ok),
      TaskWsState.connecting ||
      TaskWsState.awaitingReady =>
        ('连接中…', _warn),
      TaskWsState.closed => ('已断开', _danger),
      TaskWsState.authFailed => ('鉴权失败', _danger),
      _ => ('未连接', _fg1),
    };
    return Text(text, style: TextStyle(color: color, fontSize: 12));
  }

  // 单个标签：1:1 demo .tab —— padding 6/10、gap 7、只圆上角、
  // active 底色与终端融为一体（termBg + border），非 active bg2
  Widget _buildTab(PtySession s) {
    final isActive = s.id == _ctrl.activeId;
    final renaming = _renamingId == s.id;
    final dotColor = s.ended ? _fg2 : (s.opening ? _warn : _ok);
    return Tooltip(
      message:
          '会话 ${s.id}${s.shell.isNotEmpty ? ' · ${s.shell}' : ''}${s.backend.isNotEmpty ? ' · 后端 ${s.backend}' : ''}${s.ended ? ' · 已结束' : ''}',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: () => _ctrl.setActive(s.id),
        onDoubleTap: _isMobile ? null : () => _startRename(s),
        onLongPress: _isMobile ? () => _startRename(s) : null,
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isActive ? _termBg : _bg2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            border: Border.all(color: isActive ? _border : Colors.transparent),
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
              const SizedBox(width: 7),
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
                      style: const TextStyle(color: _fg0, fontSize: 12),
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
                // ended：删除线 + 65% 透明（demo .tab.ended .name）
                Opacity(
                  opacity: s.ended ? 0.65 : 1,
                  child: Text(
                    s.label,
                    style: TextStyle(
                      color: isActive ? _fg0 : _fg1,
                      fontSize: 13,
                      decoration: s.ended ? TextDecoration.lineThrough : null,
                      decorationColor: _fg1,
                    ),
                  ),
                ),
                // shell 徽标：客户机回执报的**实际**起的 shell，与 backend 独立
                if (s.shell.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: _bg3,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      s.shell == 'powershell' ? 'PS' : 'CMD',
                      style:
                          TextStyle(color: isActive ? _fg1 : _fg2, fontSize: 10),
                    ),
                  ),
                ],
              ],
              const SizedBox(width: 7),
              InkWell(
                onTap: () => _ctrl.closeSession(s.id),
                child: const Icon(LucideIcons.x, size: 11, color: _fg2),
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
          child: Icon(icon, size: 14, color: enabled ? _fg1 : _fg2),
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _renameFocus.requestFocus());
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
          style: TextStyle(color: _fg2, fontSize: 13),
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
            theme: _demoTheme,
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
        color: _bg1,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          for (final (label, seq) in keys)
            Expanded(
              child: InkWell(
                onTap: () => _ctrl.sendInputToActive(seq),
                child: Center(
                  child: Text(label,
                      style: const TextStyle(color: _fg0, fontSize: 12)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
