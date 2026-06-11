# WS 持续订阅（holding）：终端上下机实时状态 — 技术实现文档

> 目标读者：需要在**另一个项目**中实现完全相同功能的开发者。
> 协议部分（第 2 章）与后端强约定，**必须逐字一致**；实现部分（第 3~5 章）为语言无关的设计要点 + 本项目（Flutter/Dart）参考实现。
>
> 参考实现代码（本仓库）：
> - 接口定义：`lib/core/network/task_ws.dart`
> - 核心实现：`lib/core/network/task_ws_client.dart`
> - 状态层：`lib/features/monitor/providers/terminal_online_provider.dart`
> - UI 接入：`lib/features/monitor/presentation/monitor_page.dart`、`terminal_detail_page.dart`

---

## 1. 功能概述

在已有的「请求/响应式」WebSocket 通道上，新增一类**持续订阅（holding）消息**，用于实时接收网吧客户端（终端）的上线/下线状态：

1. 客户端发送一条**注册帧**（`reg.subscribe`），声明要订阅某网吧的终端上下机事件；
2. 之后**每 1 分钟（可配置）重发同一条注册帧**作为心跳保活；
3. 后端在有终端上线/下线时，按**与注册帧相同的消息 id** 持续推送 `subscribe.terminal` 帧；
4. 客户端把每条推送路由到一个**永不结束的流**上（除非主动取消订阅）；
5. UI 层把推送增量与 HTTP 快照合并，使终端列表/详情页的在线状态**实时变化、无需手动刷新**。

与普通消息的本质区别：普通请求/响应消息**收到一条回复后监听即销毁**；holding 消息**收到回复后监听保留**，持续接收。

---

## 2. 协议规范（与后端约定，必须完全一致）

### 2.1 连接与握手

| 项 | 约定 |
|---|---|
| URL | `ws(s)://<host>/whatever?token=<URL编码的登录token>` |
| 调试直连 | `ws://118.123.99.244:9502/whatever?token=...`（开发环境） |
| 生产 | 与 HTTP API 同源，`https→wss / http→ws` |
| 就绪信号 | WS 握手成功后**不能立即发业务帧**，必须等服务端推 `{"event":"peer.ready"}` |
| 鉴权失败 | 服务端推 `{"event":"auth.failed","data":{"message":"..."}}`，客户端**终止且不再重连**（跳登录页） |

连接状态机（`task_ws.dart:5-10`）：

```
idle → connecting → awaitingReady → ready
                          ↓
                        closed → connecting（指数退避重连：1s 起步 ×2，上限 30s；ready 后重置 1s）
                          ↓
                    authFailed（终止态，不重连）
```

### 2.2 注册帧（客户端 → 服务端）

```json
{"event":"reg.subscribe","id":"holdon-flutter-1718000000000-7","merchant_id":123,"data":{"type":"terminal"}}
```

| 字段 | 说明 |
|---|---|
| `event` | 固定 `"reg.subscribe"` |
| `id` | 客户端生成的消息 id，**后端会原样带回**，是路由的唯一关联键（格式见 2.4） |
| `merchant_id` | 网吧 id（整型，**帧顶层**，不在 data 里） |
| `data` | 固定 `{"type":"terminal"}`（订阅终端上下机） |

**心跳即重发**：没有独立的 ping 帧，心跳就是**每 60s 把这条注册帧原样重发一次**（同一个 id）。

### 2.3 推送帧（服务端 → 客户端，按同 id 持续推）

```json
{"event":"subscribe.terminal","id":"holdon-flutter-1718000000000-7","data":{"mac":"00-CF-E0-59-E1-CC","seat":"VIP-127","name":"无盘服务端","ip":"10.0.0.127","version":"","ConnID":1,"mode":1,"online":1}}
```

| data 字段 | 类型 | 说明 |
|---|---|---|
| `mac` | string | 终端 MAC 地址 |
| `seat` | string | **座位号，与 HTTP 终端列表的 seat 字段匹配的关联键** |
| `name` | string | 终端名 |
| `ip` | string | 终端 IP |
| `version` | string | 终端程序版本（可为空） |
| `ConnID` | int | 连接 id（注意大写 C 大写 ID，解析时按原字段名取） |
| `mode` | int | 0=client，1=server |
| `online` | int | **1=上线，0=下线**（核心字段） |

注意两点（实测踩过）：
- 响应的 `event`（`subscribe.terminal`）与请求的 `event`（`reg.subscribe`）**不同名**，所以**只能按 id 路由，不能按 event 路由**；
- `online`/`ConnID` 等数值字段做容错解析（int / num / 字符串数字都接受），见 `terminal_online_provider.dart:42-44`。

### 2.4 消息 id 设计

本项目所有 WS 消息 id 由客户端统一生成（`task_ws_client.dart:268-271`）：

```
普通消息：  flutter-<毫秒时间戳>-<自增序号>          例：flutter-1718000000000-6
持续消息：  <kind>-flutter-<毫秒时间戳>-<自增序号>   例：holdon-flutter-1718000000000-7
```

- `kind` 默认 `holdon`，作用是**在日志/抓包里一眼识别持续型消息**，路由逻辑不解析它（路由只按完整 id 精确匹配）；
- 后端对 id 不做格式要求，只要求**响应原样带回**。新项目可换成自己的客户端标识（如 `holdon-web-<ts>-<seq>`），格式自由，但必须全局唯一。

### 2.5 取消订阅

默认**仅本地注销**（停心跳、移除注册表、关流），不向后端发帧——后端靠"60s 心跳停了"自然过期。
如后端将来要求显式退订，约定为可选的 `cancelEvent` 参数（如 `reg.unsubscribe`），帧格式：

```json
{"event":"reg.unsubscribe","id":"<原订阅id>","merchant_id":123}
```

实现已留好参数位（`task_ws_client.dart:330-335`），传入即发，当前后端不需要、保持不传。

---

## 3. 客户端核心实现设计（语言无关）

### 3.1 两张注册表：pending 与 holding 分离

这是整个设计的关键决策（`task_ws_client.dart:29-35`）：

| | `_pending`（一次性/流式请求） | `_holding`（持续订阅） |
|---|---|---|
| 收到匹配响应后 | 完成并**移除** | 推到流上，**保留** |
| 断线时 | 全部以错误结束并清空 | **保留**，仅暂停心跳 |
| 重连成功后 | （调用方自己重试） | **自动重放**：重发注册帧 + 重启心跳 |
| 鉴权失败时 | 全部失败清空 | 全部失败清空（终止态） |

每个 holding 条目保存：注册帧参数（event/merchant_id/data）、对外的 broadcast 流、心跳定时器（`task_ws_client.dart:761-780`）。**条目必须保存完整注册参数**，否则重连后无法重放。

### 3.2 收帧路由规则（`task_ws_client.dart:444-524`）

```
收到 JSON 帧
 ├─ event == 'peer.ready'  → 置 ready、重置退避、唤醒等待者、重放所有 holding
 ├─ event == 'auth.failed' → 置 authFailed、fail 掉 pending+holding、关连接、不重连
 └─ 其它（业务帧）
     ├─ 取 id（无 id 丢弃）
     ├─ ① 先查 holding 表：命中 → 整帧推到流上，【不移除】，return
     ├─ ② 再查 pending 表：命中 → 完成/推流，按规则移除
     └─ ③ 都不命中 → 记 orphan 日志（重连漂帧/协议异常排查用），丢弃
```

holding **优先于** pending 匹配；holding 推给上层的是**完整帧** `{event,id,data}`（不剥壳），由业务层按 `event` 区分语义。

### 3.3 订阅生命周期（`subscribeHolding`，`task_ws_client.dart:225-259`）

```
subscribe(event, merchantId, data, heartbeat=60s)
  1. 生成 id（holdon- 前缀）
  2. 建 broadcast 流，onCancel(最后一个监听者取消) → 本地注销
  3. 写入 holding 表（先注册再连接，避免竞态丢帧）
  4. ensureConnected()
       成功 → start(id)：发注册帧 + 启动周期心跳
       失败（首连即 authFailed 等）→ 流上报错 + 注销
  5. 返回流
```

心跳定时器要点（`task_ws_client.dart:297-312`）：
- 仅在连接 `ready` 时才真正发送，非 ready 跳过（不报错）；
- `start(id)` 是**幂等**的：重发注册帧 + 先 cancel 旧 timer 再启新 timer。重连重放直接复用它。

### 3.4 断线 / 重连（`task_ws_client.dart:612-648`）

```
断线(onClose) → 暂停所有 holding 的心跳定时器（注册表保留）
            → fail 掉所有 pending
            → 指数退避重连（1s ×2 → 上限 30s）
重连成功(收到 peer.ready) → 退避重置 1s → 遍历 holding 表逐个 start(id)（重发注册帧+重启心跳）
```

效果：**上层拿到的流在断线期间不中断、不报错**，重连后自动恢复推送，对业务层完全透明。

### 3.5 日志规范

统一格式 `[time][level][module][operType][contextId] message`，holding 相关 operType：
`holding-open` / `holding-send`（含心跳）/ `holding-cancel` / `holding-replay` / `holding-hb`（心跳失败）/ `recv-hold`（收到推送）。
另有全量帧日志 `send-raw` / `recv-raw`（联调时直接核对帧体）。

---

## 4. 状态层：推送增量 → 在线状态聚合

参考 `lib/features/monitor/providers/terminal_online_provider.dart`，与框架无关的设计：

1. **事件模型**：把推送帧 data 解析成 `TerminalOnlineEvent{mac, seat, name, ip, version, connId, mode, online(bool), rawEvent}`，数值字段容错解析。
2. **聚合 Map**：维护 `seat → 最新事件` 的字典，每收一条按 seat 覆盖（seat 为空丢弃）。这是 UI 消费的唯一数据结构。
3. **按网吧隔离**：订阅与聚合 Map 都以 `merchantId` 为参数隔离（本项目用 Riverpod `family`；Vue 等可按 merchantId 建独立 store/Map）。切网吧时旧订阅自动销毁（无监听者 → 流取消 → 本地注销）。

---

## 5. UI 接入：HTTP 快照 + WS 增量合并

核心模式：**快照=初值、推送=增量**，不新增任何 UI 控件，让现有在线状态展示自动实时化。

### 5.1 合并规则（纯函数，`terminal_online_provider.dart:106-119`）

终端的 `status` 是三态：0=离线，1=在线，2=远程中(busy)。WS 推送只有两态（online 0/1），合并时**不能抹掉 busy**：

```
merge(terminal, event):
  event == null（该座位无推送）→ 原样返回（沿用 HTTP 快照状态）★ 因此无需用快照预填(seed)
  event.online == false        → status 置 0
  event.online == true:
      status == 2(busy)        → 原样返回（远程中不被降级成普通在线）
      否则                     → status 置 1
  （状态未变化时返回原对象，避免无谓重建/重渲染）
```

### 5.2 列表页（`monitor_page.dart:54-69`）

在「HTTP 列表数据源」之上叠一层「实时视图」，UI 只消费实时视图：

```
liveTerminals(netbarId) = httpTerminals(netbarId)
                            .map(t => merge(t, onlineMap(netbarId)[t.seat]))
```

- 原有的**手动刷新/失效逻辑全部不动**（仍然打 HTTP 数据源），HTTP 刷新与 WS 实时**分层互不干扰**；
- 列表的卡片边框色/状态徽章/在线离线筛选计数等所有依赖 `status` 的展示自动实时变化。

### 5.3 详情页（`terminal_detail_page.dart:400-404, 433-436`）

渲染前对当前终端对象跑一遍同一个 merge 函数：

```
live = merge(本地最新终端对象, onlineMap(本页所属网吧id)[terminal.seat])
```

头部「● 在线/离线」等展示用 `live` 渲染。注意详情页所属网吧 id 用**打开时锁定的值**，不跟随全局当前网吧（多窗口场景）。

### 5.4 踩过的坑（新项目照搬时注意）

| 坑 | 说明 |
|---|---|
| copyWith/克隆漏字段 | 合并 status 用对象克隆时，漏掉任何字段（本项目漏过 `alias`）会把该字段静默重置为默认值。克隆函数必须覆盖**全部字段**并逐一核对 |
| 按 event 路由收不到推送 | 响应 event 名与请求不同（2.3），必须按完整 id 路由 |
| 断线把 holding 当 pending 清掉 | 两张表必须分离（3.1），否则断线后订阅永久丢失 |
| 重连后只重连不重放 | 必须在收到 `peer.ready` 后重发注册帧，光重建 TCP 连接后端不认 |
| 心跳在非 ready 状态发送报错 | 心跳 tick 先判连接状态，非 ready 静默跳过 |
| 首次连接失败 vs 中途断线 | 首连失败（如 token 失效）应让订阅流报错终止；中途断线必须静默重连重放，不能向上层冒错 |

---

## 6. 多窗口（仅当新项目也有独立子窗口时需要）

本项目桌面端详情页可弹独立子窗口，子窗口**没有自己的 WS 连接**，通过 IPC 代理到主窗口单例：

- 子窗口侧代理：`lib/core/network/task_ws_proxy.dart`（`subscribeHolding` 走 IPC，推送复用 streamChunk 回推通道）
- 主窗口侧 handler：`lib/shared/services/terminal_window_bridge_desktop.dart`（`ws/holdingOpen` / `ws/holdingCancel`）

单窗口/Web 项目可整体跳过本章。

---

## 7. 联调验收清单

1. 连接后日志先后出现 `ws_handshake_ok` → `peer.ready`；
2. 发出 `reg.subscribe` 后，后端在终端上/下机时按同 id 推 `subscribe.terminal`（抓 `recv-hold` 日志）；
3. 静置 60s+，确认心跳帧（同 id 的 `reg.subscribe`）周期重发，订阅不过期；
4. 手动断网→恢复：日志出现 `holding-replay`，推送恢复，UI 无感知；
5. 列表页/详情页：终端开机/关机，对应卡片与详情头部**数秒内**自动变色变字，无需手动刷新；
6. 终端处于"远程中"(busy) 时收到在线推送，状态保持远程中不降级；
7. 切换网吧：旧网吧订阅注销（`holding-cancel`），新网吧重新 `holding-open`。
