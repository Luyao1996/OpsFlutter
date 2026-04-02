# WebRTC Relay 模式首次连接偶发失败

- **日期**: 2026-03-30
- **问题**: 发起 WebRTC 远程时偶尔直接提示"连接失败"
- **目标平台**: Windows
- **结果**: PASS（第 1 轮）
- **总轮次**: 1

---

## 第 1 轮

### 调查摘要

**现象**: 用户点击"WebRTC 远程"后偶尔直接看到"连接失败"/"无法建立连接"，需手动返回重试。

**代码定位**: 完整 17 步调用链从 `terminal_detail_page.dart:1258` 用户点击 → `webrtc_service.dart:1116` 直接 `_setState(failed)`。

**根因**:
1. API 调用告知终端启动 WebRTC Host（189ms 返回成功）
2. 客户端立即连接 relay WebSocket → 成功 OPEN → state=signaling
3. Host 尚未连接到 relay → relay 服务器直接关闭 WebSocket（不发 `host_offline` 消息）
4. `_handleSignalingClose()` 中 state=signaling + hasBeenConnected=false → `_handleInitialConnectionError()` → 直接 `_setState(failed)`，无重试
5. 现有 `_handleHostOfflineRetry`（30 次重试）仅在收到 `{type:'error', code:'host_offline'}` 消息时触发，不覆盖 WebSocket 直接关闭的场景
6. 偶发性取决于 Host 启动速度与客户端连接 relay 的竞争关系

**日志证据**: OPEN → 0 条服务器消息 → closed → failed（< 1 秒）

### 评审结果

**第一次**: NEEDS_REVISION — 3 个必须修正问题：
1. `connectRelay()` 有 state 守卫，重试前必须 `_state = disconnected` 直接赋值
2. 缺少 Timer 防重入守卫
3. 去掉 `_setState(connecting)` 中间调用避免 UI 闪烁

**第二次**: APPROVE — 修订后方案解决所有问题

### 代码修改

**文件**: `webrtc_remote` 包 — `examples/FlutterUi/lib/services/webrtc_service.dart`
**改动量**: 1 file, +32 lines

| # | 位置 | 改动 |
|---|---|---|
| 1 | 字段区 line 74-78 | +4 字段：`_relayInitialRetryCount`, `_relayInitialRetryTimer`, `_relayInitialMaxRetries`(15), `_relayInitialRetryInterval`(1s) |
| 2 | `initialize()` line 123-125 | +3 行重置 |
| 3 | `disconnect()` line 213-215 | +3 行取消 Timer + 重置 |
| 4 | `_handleSignalingClose()` line 1121-1139 | +17 行 relay 模式重试（Timer 防重入 + 直接赋值 state + connectRelay 复用）|
| 5 | `_setState()` line 1258-1260 | +3 行 connected 时重置计数 |

### 验证结果

- `flutter analyze`: 本次改动文件无 error
- `flutter build windows`: 构建成功

---

## 根因

Relay 模式首次连接时，WebSocket 被服务器立即关闭（Host 尚未上线），`_handleSignalingClose()` 中初始连接失败路径无重试机制，直接 `_setState(failed)`。

## 修复方案

在 `_handleSignalingClose()` 分支 4b（state=connecting/signaling + !hasBeenConnected）中增加 relay 模式判断：满足条件时 15 次 x 1 秒自动重试 `connectRelay()`，超过上限才走 `_handleInitialConnectionError`。

## Follow-up TODO

1. `_scheduleFastReconnect` line 1071 的 state 守卫 bug（relay 模式下 Agent 重启快速重连静默失败）
2. `_handleHostOfflineRetry` 与本次新增重试逻辑的潜在双 Timer 冲突
3. `_handleSignalingClose` 接收 closeCode 用于诊断日志（当前用 `_` 丢弃）

## 经验教训

- WebSocket relay 服务器在 Host 不在线时直接关闭连接（而非发送错误消息），导致客户端已有的 `host_offline` 重试逻辑无法触发
- `_handleSignalingClose` 的事件监听用 `(_)` 丢弃了 closeCode/closeReason，缺少诊断信息
- 新增重试逻辑时必须检查目标方法的 state 守卫，避免静默返回
