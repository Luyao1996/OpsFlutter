# WebRTC 远程窗口全屏闪烁+黑屏（第 2 轮深度修复）

- **日期**: 2026-03-31
- **问题**: WebRTC 远程桌面子窗口在全屏（F11）或最大化/还原时闪烁+黑屏（上次 SetTimer 修复后仍存在）
- **平台**: Windows
- **结果**: PASS
- **总轮次**: 1

---

## 前置背景

上一轮修复（2026-03-30）在 `flutter_window.cc` 中添加了 `SetTimer(50ms) + InvalidateRect` 延迟重绘，但问题仍然存在。本轮深度分析发现了真正的根因。

---

## 第 1 轮

### 调查摘要

**真正的全屏触发路径**：
```
F11 → remote_screen.dart:_toggleFullscreen()
    → windowManager.setFullScreen(true)
    → window_manager C++ SetFullScreen()
    → SendMessage(SC_MAXIMIZE)
    → WM_SIZE(SIZE_MAXIMIZED)
    → FlutterWindow MessageHandler
```

**核心根因**：

| # | 根因 | 严重度 |
|---|------|--------|
| 1 | `hbrBackground = BLACK_BRUSH` — DefWindowProc 用黑色擦除客户区 | 最严重 |
| 2 | 50ms SetTimer 延迟 — 保证黑帧可见 | 严重 |
| 3 | 无 WM_ERASEBKGND 拦截 | 辅助 |

**关键对比**：Flutter 主窗口（win32_window.cpp）用 `hbrBackground = 0` + `MoveWindow(repaint=TRUE)` → 不闪。子窗口用 `BLACK_BRUSH` + `repaint=FALSE` + 50ms 延迟 → 闪烁+黑屏。

### 评审结果

**APPROVE** — 根因代码证据确凿，方案与主窗口行为对齐，风险可控。

### 代码修改

**文件**: `plugins/desktop_multi_window/windows/flutter_window.cc`（唯一）

6 处改动：
1. `hbrBackground = 0`（原 `BLACK_BRUSH`）
2. 删除 `kDelayedRepaintTimerId` 常量
3. 新增 `WM_ERASEBKGND` 拦截返回 TRUE
4. WM_SIZE 简化为 `MoveWindow(..., TRUE)`
5. 删除 `WM_TIMER` case
6. 删除 `Destroy()` 中 `KillTimer`

文件净减 16 行（415→399）。

### 验证结果

- Windows 构建：成功（10.8s），C++ 无错误
- Flutter analyze：无新增 error
- 额外修复：注释中 em dash 替换为 ASCII（避免 C4819 编码警告）

---

## 经验教训

1. **闪烁问题先查 `hbrBackground` 和 `WM_ERASEBKGND`** — 这是 Windows 窗口闪烁最常见的根因，应第一时间检查而非跳到延迟重绘方案
2. **延迟重绘是 workaround 不是 fix** — 上次的 SetTimer 50ms 方案治标不治本，反而保证了黑帧可见时长
3. **与 Flutter 主窗口对齐** — Flutter 引擎团队已经解决了主窗口的渲染问题，子窗口应保持一致的窗口参数（hbrBackground=0、repaint=TRUE）
4. **`CS_HREDRAW | CS_VREDRAW` 不是闪烁根因** — 它只控制 invalidation 范围，配合 hbrBackground=0 不会闪烁
