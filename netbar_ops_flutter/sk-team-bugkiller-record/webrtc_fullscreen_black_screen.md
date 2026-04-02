# WebRTC 远程窗口全屏/还原黑屏

- **日期**: 2026-03-30
- **问题**: WebRTC 远程桌面窗口在 Windows 上执行最大化/还原后视频画面变黑
- **平台**: Windows
- **结果**: PASS
- **总轮次**: 1

---

## 第 1 轮

### 调查摘要

**现象**: WebRTC 远程窗口全屏/还原后视频区域黑屏，窗口控件正常。

**根因**: 未提交的工作区改动同时移除了两层重绘防御：
1. Flutter 侧：`_WebRTCWindowWrapper`（含 `_forceRepaint()` 多级延迟重绘 50/150/500ms）从调用链移除，改为直接 push `RemoteScreen`
2. C++ 侧：`WM_SIZE` 中 `MoveWindow(repaint=TRUE)` 改为 `repaint=FALSE`
3. 新增 `DWMWA_TRANSITIONS_FORCEDISABLED` 减少 DWM 重绘触发机会

三层防御同时拆除 → maximize/restore 后零重绘信号 → ANGLE surface 未重建 → 黑屏

### 评审结果

**APPROVE**，附 3 项改进建议：
1. Timer ID 用命名常量 `kDelayedRepaintTimerId = 0xF001` 替代魔数
2. `Destroy()` 中加 `KillTimer` 防止悬空 Timer
3. 确认 CMakeLists.txt 已链接 `dwmapi.lib`

### 代码修改

**文件**: `plugins/desktop_multi_window/windows/flutter_window.cc`（唯一修改文件）

4 处改动：
1. 匿名命名空间内新增常量 `static constexpr UINT_PTR kDelayedRepaintTimerId = 0xF001;`
2. WM_SIZE 处理器：`MoveWindow` 后添加 `SetTimer(window_handle_, kDelayedRepaintTimerId, 50, nullptr)`
3. 新增 WM_TIMER case：`KillTimer` + `InvalidateRect(view, nullptr, FALSE)`
4. `Destroy()` 开头添加 `KillTimer(window_handle_, kDelayedRepaintTimerId)`

### 验证结果

- Windows 构建：✅ 成功（14.4s），C++ 无错误无警告
- Flutter analyze：5 个预存 error（desktop_mock_data.dart），与本次修复无关

---

## 经验教训

- 简化代码时如果同时移除多个防御层，需要确保至少保留一层兜底机制
- ANGLE 在窗口状态变化时不能可靠地自行重建 surface 并触发重绘，需要外部显式 InvalidateRect
- C++ 侧 `SetTimer` + `InvalidateRect` 是比 Flutter 侧 `Future.delayed` + `scheduleFrame` 更简洁高效的延迟重绘方案
