# webrtc_host 内网转发「掉回直连后不再自动回归」根因 + 治本清单

> 交付对象：`webrtc_host` 组件开发者（仓库 `WebRtcGo`，分支 `feature/sfu_rebuild` @ `9fd87d66`，路径 `webrtc_host/src`）。
> 本文所有代码位置均为 **WebRtcGo 仓库内相对路径**（`webrtc_host/src/webrtc_host.cpp` 等）。
> 线上 host 版本 `3.0.40`（hash `2c0a4d31e92e466554e7118c6ed3c0a0`），与上述源码 ref 是否逐字对应**未验证**（见 §6-1），但本文引用的日志文案与源码逐字吻合。
> 本次仅做了只读源码 + host 日志分析，**未修改任何代码**；本仓库 `netbar_ops_flutter` 侧可做的前端提示另行决定，不在本文范围。
> 与既有文档 `webrtc_remote移动端ANR与重连风暴_治本清单.md`（观众端 Flutter）、`webrtc_remote远控崩溃根治方案.md`（Windows 观众端渲染）是**不同组件、不同故障**，互不替代。

---

## 1. 问题摘要

现象：某台 host 远程时"根本连不上、疯狂丢包"，用户手动在客户端点了内网转发相关按钮后恢复正常。用户的第一印象是"host 启动时没走内网转发"。

**实际情况与第一印象相反**：host 启动 3 秒内就成功走了内网转发（forward），并稳定跑了近 7 小时。之后名单上的转发器相继下线，host 按设计降级到直连（direct）。**从这一刻起到用户手点之前的 2.5 小时里，局域网内其实已经有 3 台新的转发器在线，host 却一台也不知道**，一直用直连硬扛公网丢包。

根因是两个各自合理的设计叠加出的死锁：

| 机制 | 单独看 | 叠加后 |
|---|---|---|
| 转发优先"使命完成"闸 `g_ff_mission_done`：成功进过一次 forward，进程余生不再自动进 | 合理，防止巡逻与 L4 TCP 档打架 | 它落闸时**顺带把唯一的周期性名单刷新 `Rediscover()` 也关了** |
| 降级回直连后，回去的口"只剩 L2 质量换路" | 合理，注释里明写"用户已知悉" | L2 选台读的正是那份**再也不刷新**的名单 → 名单腐烂后 L2 必然失败 |

用户手点起作用的那一步，不是"切内网转发"，而是**顺带触发了一次 `Rediscover()`**。名单一新，本来一直在跑的 L2 自救逻辑自己就成功了。

---

## 2. 已确证证据（host 日志）

日志来源：`C:\Users\Administrator\Desktop\remotelogs\webrtclogs\内网转发失败\`（host `WIN-2BCOA7NU6G9-EyJO71VaG1qX`，2026-09-01，进程 pid=19948 全程未重启，`service.log` Guard 轮询可证）。

- **证据1（启动即 forward）** `relay.log`：
  ```
  13:17:47.116 [FwdFirst][fwd=192.168.1.47:18444] forward-first ENGAGED (media uplink via forwarder by policy) → mission accomplished, forward-first will not auto-enter again this process
  13:17:48.569 [Landing][fwd=192.168.1.47:18444] selected pair == forwarder → forward landing CONFIRMED
  13:17:53 ~ 15:14   [Quality][forward] tick ... loss=0 ... degraded=N   （持续约 2 小时全 0）
  ```
- **证据2（使命完成闸落下）** `relay.log 13:17:47.535`：
  ```
  [FwdFirst][signaling_connected] forward-first mission accomplished (already entered forward once) → no more automatic forward entry for the life of this process (2026-08-14 user ruling)
  ```
- **证据3（两次可达性降级）** `relay.log`：
  ```
  15:14:15.861 [Keepalive][192.168.1.47:18444] forwarder DEAD by keepalive (3 consecutive rounds) AND uplink media stopped → demote
  15:14:18.185 [Landing][fwd=192.168.1.13:18444] forward landing CONFIRMED          ← 自动换到第二台，仍是 forward
  20:06:16.267 [Keepalive][192.168.1.13:18444] forwarder DEAD by keepalive → demote
  20:06:20.770 [Select] forward REJECTED: no forwarder port targets current SFU rtc2.03kan.com (probed 3, skipped 3 excluded/session-failed, ...)
  20:06:20.770 [Demote][fwd=192.168.1.13:18444] already in FORWARD but no usable forwarder → force fallback DIRECT
  ```
- **证据4（名单冻结 9 小时）** 全部 `*.log` 中 `TurnDiscovery` 仅出现两轮：
  ```
  13:17:44.874 [TurnDiscovery][ini] host=192.168.1.9 http_port=5896 from ...\Config.ini
  13:17:45.896 [TurnDiscovery][fetch] got 3 ips                          ← 启动那次：.47 / .13 / .51
  22:33:41.243 [TurnDiscovery] manual rediscover triggered               ← 用户手点
  22:33:41.246 [TurnDiscovery][fetch] got 3 ips                          ← 名单已变：.42 / .15 / .47
  ```
  期间 `relay_diag`（每 15s 一条，20:06→22:26 共约 560 条）候选恒为同一组 6 口，全部 `wtfdOk:false`：
  ```
  "candidates":[{"ip":"192.168.1.47",...,"wtfdOk":false},{"ip":"192.168.1.13",...},{"ip":"192.168.1.51",...}],
  "available":[],"problem":"no_forwarder_alive"
  ```
- **证据5（名单其实早就变了）** `relay.log 22:33:42` rediscover 后：
  ```
  [Test][192.168.1.42:18443] node=tf-0ed1b2b1 wtfd=0ms ... ok=Y
  [Test][192.168.1.15:18443] node=tf-8aaa1476 wtfd=0ms ... ok=Y
  [Test][192.168.1.47:18443] node=tf-74d35f90 wtfd=0ms ... ok=Y     ← 同一 IP，nodeId 已从 tf-c59cf2fa 变为 tf-74d35f90（重装/换机）
  ```
  网吧转发节点即客户机，关机 / 重装 / 换 IP 是常态，名单必须持续刷新才有意义。
- **证据6（L2 自救三次全失败）** `relay.log`：
  ```
  22:18:13.046 [Quality][direct] monitor action GoForward: no usable forwarder candidate → escalate SwitchSfu
  22:18:15.050 [SwitchSfu] no healthy alternative SFU responded → stay on ws://rtc2.03kan.com:18443/ws
  22:30:21.141 [Quality][direct] monitor action GoForward: no usable forwarder candidate → escalate SwitchSfu
  22:32:44.255 [Quality][direct] monitor action GoForward: no usable forwarder candidate → escalate SwitchSfu
  ```
  自救逻辑一直在跑，每次都拿 9 小时前的死名单去选台。
- **证据7（直连期间丢包）** `relay.log [Quality][direct] tick`：
  22:17:53~22:18:13 `loss=0.14~0.57 retx=0.10~0.36`；22:30:03~22:30:10 `loss=0.17~0.85`。
  观众端同期 `signaling.log weaknet_metrics`：`phys_pct=49.5% / 27.2%`。
- **证据8（名单一新，自动就好；用户并没有手动切 forward）** `signaling.log 22:33~22:38` 收到的操作类消息只有两条：
  ```
  22:33:40.975 {"type":"relay_test","mode":"discover"}
  22:37:42.227 {"type":"relay_test","mode":"single","target":"192.168.1.47:18443"}
  ```
  没有任何 `relay_toggle`。随后 `relay.log`：
  ```
  22:38:25.468 [Quality][direct] DEGRADED confirmed lossEwma=0.124967 ...
  22:38:25.468 [Quality][direct] monitor action GoForward → dispatched to background
  22:38:25.500 [Select][192.168.1.42:18444] FORWARD selected: node=tf-0ed1b2b1
  22:38:26.066 [Landing][fwd=192.168.1.42:18444] forward landing CONFIRMED sinceSwitch=566ms
  22:38:54 起   [Quality][forward] tick ... loss=0 degraded=N
  ```
- **证据9（30min `triedDirect` 锁未参与）** `webrtc.log [Weaknet]` 22:18:04 / 22:31:11 / 22:31:51 / 22:38:01 / 22:38:24 均 `triedDirect=N`；`relay.log 20:06:20.770` 明确 `NOT marking triedDirect (forwarder died, this is not a direct trial)`。

---

## 3. 根因因果链

```
13:17:47  forward-first 成功进 forward
  → g_ff_mission_done = true                                   webrtc_host.cpp:11994
  → MaybeEnterForwardFirst() 顶部门禁对【所有】trigger 直接 return    webrtc_host.cpp:11911
       含 patrol_30s                                            webrtc_host.cpp:12028
  → patrol_30s 是 turn_discovery_->Rediscover() 唯一的自动周期入口
       (forceRediscover=true 全仓库仅此一处)                     webrtc_host.cpp:11977
  → 名单从此冻结（证据4）

15:14 / 20:06  名单上 3 台转发器相继下线（网吧客户机关机/重装，证据3/5）
  → TriggerForwardDemote 换台失败 → force fallback DIRECT       webrtc_host.cpp:11440-11490
  → g_ff_all_failed_until_ms 冷却 5min（本身无问题，冷却过后巡检仍被 mission_done 挡）
  → 源码注释承诺的回去出口："L2 质量换路 / 手动 relay_toggle / host 重启"   webrtc_host.cpp:11908-11910

22:17  观众上线，direct 丢包 → L2 DecideAndSwitch → kGoForward       ingest_quality_monitor.cpp:336
  → 后台 Select 读 turn_discovery 缓存名单 (eps)                   webrtc_host.cpp:11300-11325
  → 6 口全死 → "no usable forwarder candidate" → escalate SwitchSfu → 无备用 SFU → 停在 direct（证据6）
  → L2 这条"唯一自动出口"被同一个闸间接废掉 → 死锁

22:33  用户手点 relay_test discover → Rediscover()                 webrtc_host.cpp:12135
  → 名单更新（证据5）→ 22:38 L2 下一次 GoForward 自己就成功（证据8）
```

**一句话**：`g_ff_mission_done` 的实际杀伤力比注释承诺的大一档——注释说"留了 L2 这条口"，实际把 L2 依赖的名单也一并断了。

### 3.1 用户记忆里的"内网转发质量差就再也不用内网转发"——核实结果

存在两条锁，都不是这个字面意思：

| 锁 | 位置 | 真实语义 | 本次是否参与 |
|---|---|---|---|
| `triedDirect` 30min 锁 | `ingest_quality_monitor.cpp:329-360`，TTL `webrtc_host.cpp:292` | forward 换满 `maxForwarderTries=3` 台仍差 → 回 direct 试一轮并置标记 → direct 也差 → 回 forward → **30min 内锁定在 forward 上**不再做质量类切换。**最终落点是 forward 不是 direct**，方向与记忆相反 | 否（证据9） |
| `g_ff_mission_done` 进程级闸 | `webrtc_host.cpp:239` 声明、`:11911` 门禁 | 成功进过一次 forward 后，**进程余生不再自动进 forward**（只挡自动入口，不挡 L2/手动/重启） | **是，元凶** |

另有 `g_manual_direct_pin`（手动切 direct 后压制自动转发入口，`:11874`）与 `g_ff_all_failed_until_ms`（全灭后 5min 冷却，`:245`），本次均未触发或已过期。

### 3.2 已排除项

- **`Select` 的"会话内不回头"黑名单**（`skip: already failed in this forward session`，`webrtc_host.cpp:11316`）：判据是 `last_fail_ms >= g_relay_session_start_ms`，后者在每次新进 forward 会话时置为当前时间（`:11248`）、换 SFU 时归零（`:439`）。**每次重新进 forward 全员重新参选，不会跨会话误伤复活节点**。不是问题。

---

## 4. 治本清单（按优先级，均在 WebRtcGo `webrtc_host` 内）

> 标注「P0/P1/P2」为建议落地优先级；每条给出 **位置 / 改法 / 风险 / 验证**。

### R1【P0｜根治】名单刷新与"转发优先"解耦，做成独立巡检
- **位置**：
  - `webrtc_host.cpp:12012 CheckForwardFirstPatrol()`：目前刷名单与"要不要自动进 forward"绑在同一次 `MaybeEnterForwardFirst("patrol_30s", forceRediscover=true)` 调用里；
  - `webrtc_host.cpp:11911`：`g_ff_mission_done` 门禁在函数最顶部，`Rediscover()`（`:11977`）在其后的后台体内，被一并挡住；
  - `webrtc_host.cpp:12323`：`relay_diag` 后台循环，每 500ms 一拍，是现成的挂载点。
- **改法**：新增 `CheckDiscoveryRefresh()`，挂在 `:12323` 同一循环里，自频控 30~60s 一轮，条件仅两个：`g_sfu_ingest_accel_enabled` 且（当前 direct **或** `relay_diag.problem == no_forwarder_alive`）；满足即在后台线程调 `turn_discovery_->Rediscover()`。**不读** `g_ff_mission_done` / `g_manual_direct_pin` / `g_ff_all_failed_until_ms`。`CheckForwardFirstPatrol` 本身一行不改（它继续只管"要不要自动进 forward"，mission_done 的原意——不与 L4 TCP 档打架——完全保留，因为刷新名单本身不切任何路）。
- **理由**：名单新鲜度是**所有**选台路径的共同前提——L2 质量换路 `Select`（`:11300`）、手动 toggle、信令兜底 `PickSignalingFallbackForwarder` 全读同一份 `endpoints_`——不该和某一条策略入口耦合。
- **风险**：低。`Rediscover()` 同步阻塞数秒（getip + STUN），已在后台线程；内置 CAS `rediscovering_` 防重入（`turn_discovery_service.h:131`）。需确认 `RebuildIceCacheLocked()` 整体替换 `endpoints_` 时不影响**正在使用中**的转发器——建议刷新条件限定 direct 态或 `no_forwarder_alive`，天然避开 forward 态。对网维接口 `192.168.1.9:5896 /api/getip` 的压力见 §6-4。
- **验证**：`webrtc.log` 中 `[TurnDiscovery][fetch]` 周期性出现；人为关掉当前转发器机器、另开一台新 IP 转发器，≤ 2 个巡检周期内 `relay_diag.available` 非空，随后 L2 `GoForward` 自动落地。

### R2【P1｜补护航】可达性降级回直连时，让转发优先重新上场（备选，可与 R1 叠加）
- **位置**：`webrtc_host.cpp:11440-11490` `force fallback DIRECT` 分支（`g_ff_all_failed_until_ms` 置 5min 冷却处）。
- **改法**：在该分支同时 `g_ff_mission_done.store(false)`。语义：护航使命被"路断了"打断，应重新上场；已有的 5min 冷却继续防打转。
- **风险**：中。这会让 `patrol_30s` 在 TCP 档（L4）期间也重新活跃——源码注释（`:229-238`）记录过"巡逻把上行拽回 UDP 转发器 → 丢包回升 → L5 判失败 → 循环"的线上冲突。虽然 W8-P6 已撤销"TCP 档一律 skip"（转发器同端口双协议），仍需在 `MaybeEnterForwardFirst` 内对 TCP 档做一次"目标转发口支持 TCP 才进"的判断。**若 R1 已落地，R2 收益显著变小**（L2 会自己回去），可以不做。
- **验证**：同 R1，并额外覆盖 TCP 档场景：L4 切 TCP 后 30s 内不得出现 `forward-first attempt dispatched`。

### R3【P2｜排查误导】TurnDiscovery 自带探活协议与转发器不匹配
- **位置**：`turn_discovery_service.cpp:399` `Reprobe()` 用 `StunProbeRtt()`（STUN Binding）判活；relay 层用 `WtfdProbeForwarder()`（`webrtc_host.cpp:11323`）。
- **现象**：两次发现均 `[TurnDiscovery][done] reachable=0/6`，而同一批地址 relay 层 `diag probe ok=Y rtt=0ms`。转发器只应答 WTFD，不应答 STUN。
- **后果**：`endpoints_[].reachable` 恒 false，`relay_diag.discovery.error` 恒 `probe-all-fail`——**即使一切正常时也是这个值**（13:17:48 首条 relay_diag 即如此），排查时会被误导。目前 `Select` 自己做 WTFD 探测、不按 `reachable` 过滤，所以无功能后果。
- **改法**：`Reprobe` 改用 WTFD；或删掉 `reachable`/`error` 字段的"探活"语义，只保留名单。
- **风险**：低。
- **验证**：`[TurnDiscovery][done] reachable=N/6` 与 relay `Probe ok=Y` 计数一致。

### R4【P2｜可观测】relay_status / relay_diag 上报名单年龄
- **位置**：`webrtc_host.cpp EmitRelayDiag()`（`:12319` 调用处）JSON 的 `discovery` 块。
- **改法**：增加 `"lastFetchMs"`（距上次 `[TurnDiscovery][fetch]` 的毫秒数）。观众端在 `state=direct && problem=no_forwarder_alive && lastFetchMs > 10min` 时给出"转发器名单陈旧，点此重新发现"提示——这半边落在本仓库 `netbar_ops_flutter`，**本次未实施**。
- **风险**：低。
- **验证**：字段随 rediscover 归零。

### R5【P1｜配合 R1】`/api/getip` 结果去重 + trim + 合法性校验
- **背景**：接口上限返回 5 个 IP，且**可能含重复**（用户确认）。
- **位置**：`turn_discovery_service.cpp:511` `ips = JsonSplitStringArray(JsonExtractArrayBody(body, "data"))` 之后、`:518` 打 `got N ips` 日志之前。
- **现状**：解析结果不去重、不 trim（`JsonSplitStringArray` 只按引号切分）。`:551-556` 组探测集 `ips × probe_ports` 时重复 IP 会生成重复 (ip, port) 对；`Reprobe()`（`:395-405`）对每一项各起一个线程，**重复项重复探测**。写回时（`:410-418`）按 (ip, port) 找 slot 覆盖，所以 `endpoints_` 本身不会出现重复条目——危害限于重复线程、重复日志、`got N ips` 数字失真。R1 落地后每 30~60s 一轮，这点浪费会被放大。
- **改法**：对每个字符串 trim 前后空白 → IPv4 合法性校验（非法丢弃）→ `unordered_set` 去重，**保持接口返回顺序**（顺序可能带优先级含义，不要 sort）。日志改为 `got N ips (M unique, K dropped)`。顺带在 `:551` 组 work 时对 (ip, port) 再去一次重，做防御，不依赖上游。
- **风险**：低，纯过滤。
- **验证**：构造含重复项的响应，`[TurnDiscovery][reprobe]` 每个 (ip, port) 只出现一次。

---

## 5. 建议先加观测（量化用）

- `[TurnDiscovery][fetch]` 之后补一行**名单 diff**（新增/消失的 IP 与 nodeId），本次 `.47` 的 nodeId 变化是靠 `relay_test` 结果人工对比出来的。
- `relay_diag` 里 `problem=no_forwarder_alive` 持续超过 N 分钟时打一条 WARN（当前只有 INFO 级每 15s 刷屏，8.6MB 的 relay.log 里 `Diag` 占 1846 条）。

---

## 6. 验证缺口（需进一步确认）

1. **源码 ref 与线上 3.0.40 是否一致**：本文引用行号来自 `feature/sfu_rebuild @ 9fd87d66`（`webrtc_host.cpp` 最近改动 `e8aa8e4f 2026-08-27`）。日志文案与源码逐字吻合，但未比对二进制 hash。
2. **20:06 三台转发器为何同时不可达**：`relay_diag 20:06:15` 六口全 `wtfdOk:false`。是网吧批量关机、交换机/VLAN 抖动、还是网维服务重启，日志无法判定。**不影响本文结论**（无论原因，名单不刷新都会死锁）。
3. **R1 在 forward 态刷新名单的安全性**：`RebuildIceCacheLocked()` 替换 `endpoints_` 时，正在使用的转发器条目是否会被清掉 `ForwarderQuality`——需读 `turn_discovery_service.cpp:554-562` 与 `GetForwarderQuality` 的键来源。本文建议的"只在 direct 态刷新"可绕开，但若要在 forward 态也刷新（提前发现更优节点），需先确认。
4. **`/api/getip` 的调用频率上限**：网维服务 `192.168.1.9:5896` 是否能承受每台 host 每 30~60s 一次；一个网吧可能有上百台 host 同时在 direct 态。若不能，R1 的频控需按 host 数量抖动或改为 2~5min。
5. ~~**`.51` 这台转发器**：是真下线还是网维接口只返回前 3 个？~~ **已关闭**（用户确认）：接口上限是 **5 个**，两次 `got 3 ips` 都未触顶，`.51` 是真下线，不是截断。
6. **转发节点超过 5 台时，接口选哪 5 个**：这是网维侧（`192.168.1.9:5896`）的策略，host 无法控制。若是"前 5 个"或"随机 5 个"，大网吧里 host 可能长期看不到离它最近/最空闲的节点，R1 刷新得再勤也只能在这 5 个里选。需向网维侧确认排序规则（建议按在线时长或负载排序）。

---

## 7. 优先级 / 风险总览

| 编号 | 作用 | 优先级 | 风险 | 是否根治 |
|---|---|---|---|---|
| R1 | 名单刷新独立巡检，与转发优先解耦 | P0 | 低 | **是** |
| R2 | 降级回直连时重置 mission_done | P1 | 中 | 部分（R1 落地后可不做） |
| R3 | TurnDiscovery 探活改 WTFD | P2 | 低 | 否（消除排查误导） |
| R4 | 上报名单年龄 + 观众端提示 | P2 | 低 | 否（可观测兜底） |
| R5 | `/api/getip` 结果去重 + trim + 校验 | P1 | 低 | 否（配合 R1 降浪费） |

**最小根治集**：R1（建议与 R5 同批落地，改动都在 `turn_discovery_service.cpp` 附近）。

---

## 8. 备注（分工）

- 治本须在 `webrtc_host`（WebRtcGo 仓库）落地。本仓库 `netbar_ops_flutter` **不修改、不提交** WebRtcGo 代码。
- 本仓库可做的只有 R4 的观众端提示半边，**本次按用户决定未实施**，仅记录于此供后续决策。
- 临时绕过（无需发版）：观众端遇到"host 在 direct 且丢包严重"时，点一次 `relay_test discover`（本次用户实际就是这么恢复的）；或重启 host 进程（`g_ff_mission_done` 是进程级，重启即清）。
