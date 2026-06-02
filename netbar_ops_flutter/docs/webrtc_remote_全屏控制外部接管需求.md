# webrtc_remote 需求：全屏控制支持外部接管（onToggleFullscreen 注入）

> 交付对象：webrtc_remote 组件开发 Agent
> 仓库：https://github.com/Luyao1996/WebRtcGo.git ，path `examples/FlutterUi`，分支 `feature/optimization`
> 影响入口：`lib/screens/remote_screen.dart` 的 `RemoteScreen`

---

## 1. 背景与问题现象

宿主 App（NetBar-Ops Flutter，Windows 桌面）把 `RemoteScreen` 嵌在一个**由 `desktop_multi_window` 创建的独立子窗口**里使用（不是主窗口）。

**复现步骤：**
1. 先把承载远程画面的子窗口"最大化/全屏"（铺满屏幕）。
2. 再进入笨鸟远程（`RemoteScreen`）。
3. 点击远程画面内置状态栏（`DesktopStatusBar`）上的"全屏/取消全屏"按钮。

**现象：** 无论怎么点全屏/取消全屏按钮，窗口都**无法还原到窗口化大小**，一直铺满。

---

## 2. 根因（为什么要做这个改动）

`RemoteScreen` 内置的全屏切换逻辑写死用了 `window_manager`：

```dart
// lib/screens/remote_screen.dart:3838-3841
Future<void> _toggleFullscreen() async {
  _isFullscreen = !_isFullscreen;                  // 包内自维护标志，初始 false（:87）
  await windowManager.setFullScreen(_isFullscreen);
}
```

`window_manager` 只能控制**主窗口（main FlutterWindow）**，它**不认识 `desktop_multi_window` 创建的子窗口**。因此：

- 当 `RemoteScreen` 运行在子窗口里时，这个按钮调用的 `windowManager.setFullScreen()` 打不到当前承载它的子窗口，等于**空操作（对子窗无效）**；
- 包内自维护的 `_isFullscreen`（初始 `false`）与子窗真实的最大化状态完全脱节，状态栏图标也会显示错误。

宿主侧的子窗口全屏/还原是用各自的 native 机制（Win32 `ShowWindow` 等）控制的，宿主**已经实现了一套能正确操作子窗口的全屏切换回调**，只差 `RemoteScreen` 没有开放注入点，无法把这套回调接进来。

> 结论：`RemoteScreen` 需要开放"全屏控制由外部接管"的能力。当宿主注入了自己的全屏切换回调时，组件内部不再调用 `windowManager.setFullScreen`，改为调用宿主回调，并用宿主提供的全屏状态来渲染按钮图标。

---

## 3. 需求目标

给 `RemoteScreen` 增加**可选的**"外部接管全屏"能力，满足：

1. 宿主可以注入一个"切换全屏"的回调，由宿主自己决定如何让窗口全屏/还原。
2. 宿主可以注入当前的全屏状态，供组件状态栏正确显示"全屏"还是"取消全屏"图标。
3. 注入存在时，组件内部**不得**再调用 `windowManager.setFullScreen`，也**不得**再依赖/翻转自己内部的 `_isFullscreen`。
4. **向后兼容**：当宿主不注入（即独立 example App 直接全屏运行）时，保持现有行为完全不变（继续走 `windowManager.setFullScreen` + 内部 `_isFullscreen`）。

---

## 4. 接口契约要求（对外 API）

在 `RemoteScreen` 构造函数新增两个**可选**参数（命名可按组件库风格微调，但语义需一致）：

| 参数 | 类型 | 含义 |
|---|---|---|
| `onToggleFullscreen` | `VoidCallback?` | 外部全屏切换回调。非空时，组件所有"切换全屏"动作都改为调用它，不再调用 `windowManager.setFullScreen`。 |
| `isFullscreen` | `bool?` | 外部全屏状态。非空时，状态栏全屏按钮的图标/提示以此为准（true=已全屏显示"退出全屏"，false=显示"进入全屏"）。 |

**判定规则：**
- 「外部接管模式」= `onToggleFullscreen != null`。
- 进入外部接管模式后：
  - 状态栏全屏按钮点击 → 调用 `onToggleFullscreen`；
  - 状态栏全屏按钮显示状态 → 取 `isFullscreen ?? false`；
  - 组件内部 `windowManager.setFullScreen(...)` **完全不执行**；
  - 组件内部 `_isFullscreen` 不再作为真值来源（可保留字段但不参与渲染判断）。
- 未进入外部接管模式（`onToggleFullscreen == null`）：行为与现状 100% 一致。

**状态更新方式：** 宿主会在自己的全屏状态变化时 `setState` 重建 `RemoteScreen`（传入新的 `isFullscreen`）。组件按常规 `widget.isFullscreen` 读取即可，**无需**自己监听窗口事件来同步图标。

---

## 5. 需要覆盖的全屏触发点（不要遗漏）

组件内现有的所有"全屏切换"入口，在外部接管模式下都必须改走 `onToggleFullscreen`，而不是内部 `_toggleFullscreen`：

1. `DesktopStatusBar` 的全屏按钮 —— `remote_screen.dart:3090` 当前 `onToggleFullscreen: _toggleFullscreen`。
2. 键盘快捷键 **F11** —— `remote_screen.dart:2291` 当前调用 `_toggleFullscreen()`。
3. 其它任何调用 `_toggleFullscreen()` 或 `windowManager.setFullScreen()` 的地方（请全局检索确认，`remote_screen.dart:1232-1233` 的 `case 'fullscreen'` TODO 也一并对齐）。

建议实现：保留单一内部入口（例如改造 `_toggleFullscreen`），内部先判断是否外部接管，再决定调宿主回调还是走旧逻辑；这样上述所有触发点自动统一。

---

## 6. 兼容性与约束

- **不得**破坏独立 example App 的全屏（`onToggleFullscreen == null` 时必须等价于现状）。
- **不得**新增对宿主环境的强依赖（参数都是可选）。
- 移动端全屏逻辑（`remote_screen.dart:284` 等）不在本需求范围，保持原状；本需求仅针对桌面端状态栏/快捷键的全屏切换。
- 改动尽量内聚在 `RemoteScreen` 与其状态栏交互层，避免外溢到 WebRTC 连接/输入/渲染逻辑。

---

## 7. 验收标准

**场景 A（外部接管，宿主子窗口）：**
- 宿主注入 `onToggleFullscreen` + `isFullscreen`。
- 子窗口先最大化铺满 → 进入远程 → 点状态栏全屏按钮 → 能正常在"铺满 ↔ 窗口化"之间切换（由宿主回调驱动）。
- 状态栏全屏图标随宿主 `isFullscreen` 正确显示，无错位。
- F11 行为与状态栏按钮一致。
- 全程组件内部不调用 `windowManager.setFullScreen`（可加日志或断点自证）。

**场景 B（向后兼容，独立运行）：**
- 不注入 `onToggleFullscreen`。
- example App 直接运行，点全屏按钮 / F11，行为与改造前完全一致。

---

## 8. 宿主侧对接说明（供组件开发者理解上下游契约，宿主代码由 NetBar-Ops 侧自行修改）

宿主 `RemoteScreen` 的承载层 `_WebRTCWindowWrapper` 已经有：
- 正确操作子窗口的全屏切换回调（Win32 `ShowWindow` 还原/最大化）；
- 实时的全屏状态 `isFullscreen`。

宿主会通过 `RemoteScreen(onToggleFullscreen: <宿主回调>, isFullscreen: <宿主状态>, ...)` 注入。组件只要按第 4、5 节实现注入点即可，**无需关心宿主回调内部如何控制窗口**。
