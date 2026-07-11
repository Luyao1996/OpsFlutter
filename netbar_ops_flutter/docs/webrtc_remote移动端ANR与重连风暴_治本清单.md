# webrtc_remote 移动端崩溃根因 + 治本清单（ANR / 高CPU被杀 / 未捕获SocketException）

> 交付对象：`webrtc_remote` 组件开发者（仓库 `WebRtcGo`，git ref `feature/optimization` @ `74b3eca`，包路径 `examples/FlutterUi`）。
> 本文所有代码位置均为 **WebRtcGo 仓库内相对路径**（`examples/FlutterUi/lib/...`、`examples/FlutterUi/plugins/flutter_webrtc/...`）。
> 与既有文档 `webrtc_remote远控崩溃根治方案.md`（Windows 端 VideoRenderer OnFrame/dispose 竞争）是**两组不同崩溃**，互不替代。
> 本次仅做了只读源码 + 远程崩溃日志分析，**未修改任何代码**；本仓库 `netbar_ops_flutter` 的兜底加固另行决定，不在本文范围。

---

## 1. 问题摘要

某些机型（实测华为 **ICL-AL20 / arm64 / EMUI(HarmonyOS) 12**）+ 较差网络下，远控会"突然开始一直崩"。实为**同一条无退避正反馈环**点燃后，连环触发三种不同的进程退出：

| 现象 | Android 退出原因 | 根因层 |
|---|---|---|
| 界面卡死约 28s 后重启 | **reason=6 ANR** | 主线程被 `getStats` 同步阻塞 |
| 用一会儿就被系统杀 | **reason=9 EXCESSIVE_RESOURCE_USAGE** | 重连风暴持续高 CPU |
| 直接闪退 | Dart 未捕获异常 `dart_crash` | closed socket 仍被读，逃逸到 zone |

**治本点几乎全部在本组件（WebRtcGo）内。** 本仓库（netbar_ops_flutter）只能做止血兜底，无法根治。

---

## 2. 已确证证据（远程崩溃日志）

日志来源：`远端机器 .../remotelogs/{crash_logs,webrtc_logs}`。

- **证据1（高CPU）** `exit_reason_20260602`：`Reason: 9 (EXCESSIVE_RESOURCE_USAGE)`，`Description: excessive cpu 206420 during 300096 dur=1569032 limit=3.0`，进程 `com.netbarops.netbar_ops_flutter` 被杀。
- **证据2（ANR）** `exit_reason_20260614`：`Reason: 6 (ANR) desc=user request after error`。tombstone 主线程 `"main" ... Native`：
  ```
  pthread_cond_wait
  libjingle_peerconnection_so.so (Java_org_webrtc_PeerConnection_nativeNewGetStats+224)
  org.webrtc.PeerConnection.nativeNewGetStats(Native)
  org.webrtc.PeerConnection.getStats
  com.cloudwebrtc.webrtc.PeerConnectionObserver.getStats
  com.cloudwebrtc.webrtc.MethodCallHandlerImpl.peerConnectionGetStats
  com.cloudwebrtc.webrtc.MethodCallHandlerImpl.onMethodCall   ← 平台主线程 Looper
  ```
  对应 `webrtc_20260614.log` 时间线：连接 `23:49:25` 刚建好（createDataChannel/setRemoteDescription/createAnswer/`didFirstFrameRendered` 均正常），随后 **`23:49:27.8 → 23:49:55` 出现约 28 秒日志空窗**（冻结），进程随后以新 pid 重启，并打 `WARN reason=6 name=ANR`。
- **证据3（未捕获崩溃）** `dart_crash_20260605`（华为 ICL-AL20）：`SocketException: Reading from a closed socket` at `dart:io _RawSecureSocket.read`，经 `_Socket._onData` → Timer 回调抛出。
- **证据4（重连风暴）** `webrtc_20260613.log`（8 小时，38037 行）方法通道统计：`createPeerConnection ≈ 660`、`peerConnectionClose ≈ 654`、`createOffer ≈ 580`、`setLocalDescription ≈ 672`、`createDataChannel ≈ 680`、`dataChannelClose ≈ 570`；按分钟聚集峰值 **13–17 次/分钟**。全是"建连→关闭→重建"。
- **证据5（上游喂料）** 全部日志 ERROR：`TimeoutException: ws request timeout: fun=remote`（来自 netbar_ops_flutter 的 `TaskWsClient.request` ← `TerminalApi.remote` ← `terminal_detail_page._openWebRTCRemote/_handleWebRTCButtonTap`），多座位重复出现。
- **证据6（getStats 被屏蔽日志）** netbar_ops_flutter `lib/core/logging/logging_binary_messenger.dart:37-52` 把 `getStats/getStatsForTrack/peerConnectionGetStats` 列入 `_noisyMethods` 不打日志——所以日志里看不到 getStats，但它其实在**每秒高频调用**（见 §4）。

**关键修正（已验证）：崩溃设备是手机，走单 PC 分支。** `lib/services/ice_racing_service.dart:307 _getMobileCandidates()` 只返回 1 个候选（`mobile-1`，第 325-331 行），且第 334 行注释明说"移动端单 PC，避免多 PC 导致 Android SIGSEGV"。故证据4 的 660 次 `createPeerConnection` 是**单 PC 反复重连 ~660 次（频率主导）**，不是并行 5 条。→ 修复优先级指向"重连频率"，桌面端 5-PC 并行度问题对本次崩溃不是主因。

---

## 3. 根因因果链

```
底层 WSS/TLS socket 抖动（证据3）
  → signaling_service 自动重连「无总次数上限、封顶30s、前3次仅~300ms」
        ×  webrtc_service 自带的第二套重连(_handleSignalingClose)        ← 双引擎，同一次断开被排两次
  → ws 重连成功后 Host 周期心跳上报 peer_status=online，signaling_service 不去重，无条件 emit
  → webrtc_service._handlePeerStatus 对每条 online 都 cancel() + 重启 ICE Racing（无去重、无冷却）
  → 手机端单 PC 反复重建；退避被 reconnectWithNewConfig 反复清零 _reconnectAttempt 而失效，maxAttempts 形同虚设
  → 8h createPeerConnection≈660 / close≈654、峰值13-17次/分钟（证据4）
  → 每次连接进 connected 即 stats_service.start()，以 1000ms 链式 await _pc.getStats()，且无任何 timeout
       且停轮询 guard 读的是「缓存」connectionState getter（仅异步回调更新），native 已 teardown 但回调未派发时失效
       → 继续对垂死/正在 close 的 native PC 调 getStats
  → getStats 经 MethodChannel 进 native，在 ICL-AL20/EMUI12 撞 libjingle 网络线程锁竞争
       → 主线程 nativeNewGetStats → pthread_cond_wait 冻结约28s → ANR（证据2；getStats 被屏蔽日志=证据6）
  → 同时：660 次建/拆 + 每秒全量 getStats+全量 report 解析+多次 emit + 高频回调 + 全量日志 → 持续高CPU 被杀（证据1）
  → 风暴期大量游离 Timer/Future.delayed 捕获旧 socket/旧 pc，在 socket 已关后仍被调度 read → 未捕获 SocketException（证据3）
```

---

## 4. 治本清单（按优先级，均在 WebRtcGo 内）

> 标注「P0/P1/P2」为建议落地优先级；每条给出 **位置 / 改法 / 风险 / 验证**。

### B1【P0｜止 ANR 直接执行体】getStats 套 timeout，超时跳过本轮
- **位置**：`lib/services/stats_service.dart:262` `_collectWebRTCStats()` 内 `final stats = await _pc!.getStats();`
- **改法**：`await _pc!.getStats().timeout(const Duration(seconds: 2))`；捕获 `TimeoutException` 后**跳过本轮**——不前移 `_fpsSample*` / `_prev*` 基准点、打一行日志、照常在 `_poll:254` 排下一轮。
- **风险**：低。timeout 只让 **Dart 侧放弃等待**，**不能取消已卡死的 native 调用**——必须配合 B2 才彻底（见 §6 验证缺口）。
- **验证**：ICL-AL20 上人为制造 signaling 拥堵/弱网，确认主线程不再出现 28s 空窗。

### B2【P0｜根除 ANR】getStats 不在主线程同步阻塞
- **位置**：`plugins/flutter_webrtc/android/src/main/java/com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java`
  - `onMethodCall` 在**平台主线程 Looper** 执行（tombstone 实锤）；
  - `case "getStats":`（第 562-567 行）→ `peerConnectionGetStats`（第 2066 行）→ `pco.getStats(result)`（第 2072 行）**内联在主线程**；
  - 该类已持有 `ExecutorService executor = Executors.newSingleThreadExecutor();`（第 155 行），但 getStats 没用它（对比第 1110/1119 行的 `executor.execute(...) + mainHandler.post(...)` 模式）。
- **改法（任选其一）**：
  1. 把 `getStats`（及其它会阻塞 signaling 线程的 PC 同步调用）放进 `executor.execute(() -> { pco.getStats(...); })`，回调里用 `mainHandler.post` 回传 result；
  2. 或升级 flutter_webrtc 到已修复该问题的版本（注意本仓库 flutter_webrtc 是 vendored 在 `examples/FlutterUi/plugins/flutter_webrtc`，需同步）。
- **风险**：中。需保证 `AnyThreadResult`（第 349 行已在用）线程安全；getStats 与 close/dispose 的并发顺序要控好（避免对已 dispose 的 PC 调 getStats）。
- **验证**：tombstone 不再出现 `onMethodCall` 在 main 线程卡 `nativeNewGetStats`。

### B3【P0｜止 ANR + 降CPU】重连前显式停轮询 + 用实时状态判停 + 防跨 PC 并发
- **位置**：
  - `lib/services/stats_service.dart:192-211 _poll()`：第 199-205 行用**缓存** `_pc.connectionState` getter 判停（该 getter 仅在异步回调里更新，native 已拆但回调未到时失效）。
  - `lib/services/webrtc_service.dart:1674-1701 _cleanup()`：主动 close/重连前**未**显式 `statsService.stop()`。
  - `lib/services/stats_service.dart:117-169 start()`：无 epoch/token，旧 `await getStats()` 返回时无法判断是否已换 PC。
- **改法**：
  1. `webrtc_service._cleanup` / 重连入口处先 `statsService.stop()`，杜绝对正在 teardown 的 PC 调 getStats；
  2. `start()` 引入连接代际 `epoch`，`_collectWebRTCStats` 的 `await` 返回后校验 `epoch` 不一致即丢弃；
  3. 判停改为依据"是否仍持有当前有效 PC"，而非缓存 getter。
- **风险**：低。
- **验证**：重连切换瞬间不再有"对旧 PC 的 getStats"日志（配合 §5 临时打开采样）。

### B4【P1｜掐断风暴主回路】peer_status 去重 + race 重启冷却
- **位置**：
  - `lib/services/signaling_service.dart:272-286`：peer_status 分支无去重，无条件 emit。
  - `lib/services/webrtc_service.dart:1291-1302 _handlePeerStatus()`：对每条 online 都 `cancel()` + 重启 ICE Racing，无去重无冷却。
- **改法**：signaling 侧 `(status, peerType)` 与上次相同则 `return`；`_handlePeerStatus` 在已 connected / 已 racing 时不重启 race，并加 `startRace` 最小冷却（≥5s）。
- **风险**：中。需确认 Host 心跳是 offline↔online 翻转还是周期重发 online（见 §6），避免误吞真正的状态变化。
- **验证**：稳定连接期间 `createPeerConnection` 不应随 Host 心跳节奏反复出现。

### B5【P1｜消灭双重连引擎】重连决策唯一化
- **位置**：
  - `lib/services/signaling_service.dart`：`onError:163` / `onDone:180` / `host_offline:437-439` 各自调 `_scheduleReconnect:495-522`。
  - `lib/services/webrtc_service.dart`：`_handleSignalingClose:1423`（`:1447`/`:1483`）也发起重连。
- **改法**：二选一。建议 signaling 层只发 `signalingClose/Error` 事件、删除自身 `_scheduleReconnect` 调用，由 webrtc_service 独占重连决策（或反之），保证**唯一一条**重连路径覆盖所有断开场景。
- **风险**：中。要确保改后所有断开场景仍被覆盖，不漏重连。
- **验证**：单次断开只触发一次重连排程。

### B6【P1｜让 maxAttempts 真正生效】统一退避 + 硬上限 + 冷却
- **位置**：`lib/services/webrtc_service.dart`
  - `reconnectWithNewConfig:316-345`：第 336 行 `_reconnectAttempt = 0` 绕过 `maxAttempts=5`（`constants.dart` `reconnectStrategy`，默认 `backoffMultiplier=1.5`）。
  - `_handleVideoStuck:351-388` / `_handlePersistentPacketLoss:1321-1349`：触发整连重连无最小间隔。
  - `_scheduleFastReconnect:1373-1420`：200ms 快速重连无总次数限制。
- **改法**：删除 `reconnectWithNewConfig` 里的 `_reconnectAttempt=0`；videoStuck / 持续丢包 / fast-reconnect 共用一个"最近重连时间戳 + 计数器"，最小间隔（如 10s）+ 总上限；ICE Racing 失败也接入同一套退避。
- **风险**：中。退避变长会牺牲极端弱网下的恢复速度，需与产品权衡阈值。
- **验证**：连续失败时间隔应指数增长并最终停在上限，而非恒定高频。

### B7【P1｜消除证据3】游离 Timer/Future + socket 关闭路径加代际校验与 catch
- **位置**：
  - `lib/services/webrtc_service.dart`：relay 候选 `Future.delayed:1033-1039`、`onIceConnectionState` 的 `Future.delayed 5s:1108-1114`、`_scheduleFastReconnect` 的 `connectFuture.catchError:1413-1419`。
  - `lib/services/signaling_service.dart`：`cleanup` 的 `sink.close:539-545`、`send/_flushQueue` 裸 `add:216-224/458-463` 无 `catchError`。
- **改法**：所有游离 `Timer`/`Future.delayed` 闭包加**连接代际 generation 校验**（代际变了直接 return）+ `try/catch`；signaling 的 `sink.close` / `add` 包 `catchError`，防 `SocketException` 逃逸到 zone。
- **风险**：低。
- **验证**：风暴期不再出现 `Reading from a closed socket` 未捕获。

### B8【P2｜降CPU】资源 close+dispose、收敛高频回调与诊断 getStats
- **位置**：
  - `lib/services/webrtc_service.dart:1674-1701 _cleanup()`：对 PC/DataChannel 只 `close()` 不 `dispose()`；`disconnect:297-313` 未释放 `RTCVideoRenderer`。
  - `lib/services/ice_racing_service.dart`：`trickleTimer 200ms:839`、`_reportQualityStats 500ms`、ICE failed 诊断 `getStats:647`、`_collectStats/_detectConnectionType/_detectAndFixTurnProtocol` 多次 getStats。
- **改法**：`_cleanup` 改 `close()+dispose()`（**注意 dispose 时机晚于所有引用回调，避免 VideoRenderer OnFrame/dispose 竞争——见既有文档 `webrtc_remote远控崩溃根治方案.md`**）；诊断类 getStats 限频/仅 debug/串行加超时；质量包处理加 `if(_winner!=null || !_isRacing) return` 守卫。
- **风险**：中（dispose 时机错会引入 §既有文档 的崩溃）。
- **验证**：native heap / 句柄数随重连次数不再单调增长。

### 次要项（对本次「手机」崩溃非主因，建议顺手修）
- **桌面 5-PC 并行度**：`ice_racing_service.dart:259-303 _getRelayOnlyCandidates` + `startRace auto:455-472` 单轮 5 条 relay PC，建议收敛为 2–3 条阶梯补充。
- **fast-win 死代码**：`ice_racing_service.dart:1395/1407 _evaluateFastWin` 把 `raceId == 'relay-udp'/'relay-tcp'` 改为 `startsWith(...)`（实际 id 是 `relay-udp-1/2/3`），否则永不相等、快速胜出成死代码、每轮死等满 4s。**注意：手机走 `mobile-1` 单 PC 分支，此项主要影响桌面端。**
- **network_adaptive_service**：当前未启用但同构隐患，若启用须先加迟滞带 + 冷却≥10s（`:125`/阈值 `:69-74`）、ICE Restart 加退避与真实监听闭环（`_triggerIceRestart:303-311` 当前空发信号无人接）、`stop():151-164` 完整复位跨重连状态。

---

## 5. 建议先加观测（量化用，验证后还原）

- 临时把 `getStats/peerConnectionGetStats` 从 netbar_ops_flutter `lib/core/logging/logging_binary_messenger.dart:37` 的 `_noisyMethods` 移出或改采样，采集 **getStats 调用耗时 + start() 时间线**，量化跨 PC 并发与定位触发 native 死等的连接状态。
- 补 **socket 级带时间戳日志**，把 socket close 时刻与各 Timer/Future.delayed 触发时刻对齐，钉死证据3 的精确归属。

---

## 6. 验证缺口（需进一步确认，影响个别修复取舍）

1. **getStats 是否真能被 `Future.timeout` 解阻塞**：平台通道 timeout 只丢弃 Dart 侧结果、**不取消 native 调用**，native 仍可能 hang。需在 ICL-AL20/EMUI12 **实测** B1 后主线程是否真正解阻塞——若否，B2 为必做。
2. **证据3 SocketException 精确归属**：是本组件 signaling ws、还是 netbar_ops_flutter 的任务通道 ws（`webrtc.03kan.com`）。需 §5 socket 级日志对齐。
3. **Host peer_status online 心跳真实频率**：周期重发 online 还是仅 offline↔online 翻转——直接决定 B4 去重的收益与正确性。需抓 WS 报文。
4. **服务端对重复 `fun=remote` 是否幂等 / 是否提供取消语义**：决定上游超时后是否需补发 cancel、多条 remote 是否让 Host 反复起 webrtc-remote 服务放大证据4。需后端确认。
5. **`_cleanup` 只 close 不 dispose 的句柄/线程泄漏量级**：需 Android Profiler / native heap 计数佐证其对证据1 的实际贡献。

---

## 7. 优先级 / 风险总览

| 编号 | 作用 | 优先级 | 风险 | 是否根治 |
|---|---|---|---|---|
| B1 | getStats timeout | P0 | 低 | 部分（需配 B2） |
| B2 | getStats 离开主线程 | P0 | 中 | 是（根除 ANR） |
| B3 | 重连前停轮询/实时判停 | P0 | 低 | 是 |
| B4 | peer_status 去重 + race 冷却 | P1 | 中 | 是（断风暴回路） |
| B5 | 双重连引擎合一 | P1 | 中 | 是 |
| B6 | 退避真生效 | P1 | 中 | 是 |
| B7 | 游离 Timer/socket 加固 | P1 | 低 | 是（消证据3） |
| B8 | close+dispose / 降回调频率 | P2 | 中 | 部分（降CPU） |

**最小根治集**：B1+B2+B3（止 ANR）+ B4+B5+B6（断重连风暴）。B7 治证据3，B8 进一步降 CPU。

---

## 8. 备注（分工）

- 本仓库 `netbar_ops_flutter` 侧可做的**止血兜底**（远控按钮防抖/单会话、remote 失败退避、`ensureConnected` 加超时、`_closeChannel`/`_onClose` 硬化、收敛日志、切后台暂停、zone 白名单兜底）能**降低喂料与减少崩溃面，但无法根治**——本次按用户决定**未实施**，仅记录于此供后续决策。
- 治本须在本组件落地。本仓库不修改、不提交 WebRtcGo 代码。
