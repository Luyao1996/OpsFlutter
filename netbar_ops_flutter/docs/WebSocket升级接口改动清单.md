# WebSocket 升级接口改动清单

> 对齐 Web 端 toolboxPage 的 frp→WebSocket 升级。本清单只列**需要改动的接口**与前后调用方式对比，不涉及实现细节。

## 目录
- [一、WebSocket 怎么连](#一websocket-怎么连)
- [二、需要改动的接口清单](#二需要改动的接口清单)
  - [A. 改走 WebSocket（替换原 POST {domain}/api/task）](#a-改走-websocket替换原-post-domainapitask)
  - [B. 改走 WebSocket（替换原 ws://{domain}/ws_client）](#b-改走-websocket替换原-wsdomainws_client)
  - [C. 改走中央 HTTP（替换原 https://router-{host}/api/...）](#c-改走中央-http替换原-httpsrouter-hostapi)
  - [D. 改走中央 HTTP（替换原 https://{domain}/api/seatlist）](#d-改走中央-http替换原-httpsdomainapiseatlist)
  - [E. 操作日志埋点（新增，对齐 Web）](#e-操作日志埋点新增对齐-web)
- [三、不改的接口（明确不动）](#三不改的接口明确不动)

---

## 一、WebSocket 怎么连

```
URL（开发）: ws://118.123.99.244:9502/whatever
URL（生产）: wss://{当前 host}/whatever?token={token}
```

- **单例长连接**：主窗口持有唯一一条 WS；子窗口通过 method channel 转发到主窗口
- **首次需要时建连**，断开后指数退避自动重连
- **握手二段式**：`onopen` 后**等服务端推 `{event:'peer.ready'}`** 才能发业务；收到 `{event:'auth.failed'}` 则鉴权失败
- **请求帧外壳**（客户端发）：

  ```json
  {
    "event": "peer",
    "id": "<前端会话id>",
    "merchant_id": 215,
    "data": {
      "fun": "<fun名>",
      "seat": "<座位号>",
      "data": { "...业务字段...": "..." }
    }
  }
  ```

- **响应帧外壳**：服务端可能回 `{event:"peer", data:<业务对象>}`，客户端剥一层取 `data` 作为业务响应
- **多路复用**：同一条 WS 上并发多个请求/流，靠 `id` 路由对应 Completer/StreamController

---

## 二、需要改动的接口清单

### A. 改走 WebSocket（替换原 `POST {domain}/api/task`）

| 功能模块 | 代码地址 | 改动前调用 | 改动后调用 |
|---|---|---|---|
| 远程连接 | `lib/features/monitor/data/terminal_api.dart:218 remote()` | `POST https://{domain}/api/task?seat={seat}` body `{fun:'remote',data:{enable:true,type,user}}` | `taskWs.request(fun:'remote', seat, merchantId, data:{enable:true,type,user})` |
| 断开远程 | 同上 | body `{fun:'remote',data:{enable:false}}` | `taskWs.request(fun:'remote', …, data:{enable:false})` |
| 更新远端程序（**新增**） | — | — | `taskWs.request(fun:'update', seat, merchantId, data:{})` |
| 远程截图 | `lib/features/desktop/data/desktop_api.dart:253 ScreenshotApi.requestScreenshot` | `POST .../api/task` body `{fun:'Screenshot',data:{}}`，`responseType: bytes` | `taskWs.request(fun:'Screenshot', seat, merchantId, data:{})`，回包结构变 JSON `{base64\|url,width,height}` |
| 进程列表（平铺） | `terminal_api.dart:253 getProcesses` | body `{fun:'processTree',data:{}}` | `taskWs.request(fun:'processTree', …, data:{})` |
| 进程树 | `terminal_api.dart:277 getProcessTree` | 同上 | 同上 |
| 结束进程 | `terminal_api.dart:337 killProcess` | body `{fun:'processEnd',data:{type,ProcessId,ProcessName}}` | `taskWs.request(fun:'processEnd', …, data:{…})` |
| 文件列表 | `terminal_api.dart:360 getFiles` | body `{fun:'fileList',data:{path}}` | `taskWs.request(fun:'fileList', …, data:{path})` |
| 文件下载 | `terminal_api.dart:466 downloadFile` | body `{fun:'fileRead',data:{path}}`，bytes，timeout 120s | ⚠️ **待后端定方案**：建议改"返回临时下载 URL，前端再 GET" |
| 硬件静态信息 | `terminal_api.dart:501 getHardwareInfo` | body `{fun:'hwinfo',data:{type:'info'}}` | `taskWs.request(fun:'hwinfo', …, data:{type:'info'})` |
| 硬件实时（轮询） | `terminal_api.dart:536 getHardwareRealtime` | body `{fun:'hwinfo',data:{type:'realtime'}}` | `taskWs.request(fun:'hwinfo', …, data:{type:'realtime'})` |
| 电源控制 | `terminal_api.dart:555 controlPc` | body `{fun:'controlPc',data:{type}}` | `taskWs.request(fun:'controlPc', …, data:{type})` |

### B. 改走 WebSocket（替换原 `ws://{domain}/ws_client`）

| 功能模块 | 代码地址 | 改动前调用 | 改动后调用 |
|---|---|---|---|
| CMD 建连 | `lib/features/monitor/presentation/widgets/console_manager_tab.dart:95-107 _buildWsUrl` + `889 connectWs` | `new WebSocket('ws://{domain}/ws_client')` | 删除独立 WS；`await taskWs.ensureConnected()` |
| CMD 登录 | `console_manager_tab.dart:186 loginCmd` | send `{fun:'cmdlogin',data:{seat}}` | `taskWs.requestStream(fun:'cmdlogin', seat, merchantId, data:{})` 拿到流，承载后续输出 |
| CMD 执行命令 | `console_manager_tab.dart:275-287` | send `{fun:'cmd',data:{seat,cmd}}` | `taskWs.request(fun:'runcmd', seat, merchantId, data:{cmd})` ⚠️ **fun 名变 `runcmd`** |
| CMD Ctrl+C | `console_manager_tab.dart:296-298` | send `{fun:'cmd',data:{seat,cmd:'\\x03'}}` | `taskWs.request(fun:'runcmd', …, data:{cmd:'\\x03'})` |
| CMD 心跳/重连 | `console_manager_tab.dart:435 + onclose` | dialog 自身 WS 重连 | 委托 `taskWs` 全局重连；ready 后由 CMD 层重新 `requestStream(cmdlogin)` |
| CMD 接收命令输出 | `console_manager_tab.dart` 消息处理 | 监听 `fun==='cmdRun'` | 监听 `requestStream` 推送的每条 chunk（**事件名以后端落地为准，可能是 `cmdReply`**） |

### C. 改走中央 HTTP（替换原 `https://router-{host}/api/...`）

| 功能模块 | 代码地址 | 改动前调用 | 改动后调用 |
|---|---|---|---|
| 路由器列表 | `lib/features/monitor/data/router_api.dart:174 getAll` | `GET https://router-{host}/api/routers` | `GET {AppConfig.baseUrl}/routers?merchant_id={id}` |
| 路由器创建 | `router_api.dart:182 create` | `POST https://router-{host}/api/routers` | `POST {AppConfig.baseUrl}/routers` body 带 `merchant_id` |
| 路由器更新 | `router_api.dart:187 update` | `PUT https://router-{host}/api/routers/{id}` | `PUT {AppConfig.baseUrl}/routers/{id}` |
| 路由器备注（**新增**） | — | — | `PUT {AppConfig.baseUrl}/routers/{id}/remark` body `{remark}` |
| 路由器删除 | `router_api.dart:192 delete` | `DELETE https://router-{host}/api/routers/{id}` | `DELETE {AppConfig.baseUrl}/routers/{id}` |
| 路由器流量 | `router_api.dart:197 getTraffic` | `GET https://router-{host}/api/traffic/{routerId}` | ⚠️ **待后端确认**：路径未明示 |
| 脚本类型枚举 | `router_api.dart:210 getScriptTypes` | `GET https://router-{host}/api/scripts/types` | `GET {AppConfig.baseUrl}/config/global/router_types` |

### D. 改走中央 HTTP（替换原 `https://{domain}/api/seatlist`）

| 功能模块 | 代码地址 | 改动前调用 | 改动后调用 |
|---|---|---|---|
| 座位列表 | `terminal_api.dart:169 getAll`<br/>消费方：`monitor_page.dart:40 terminalsProvider`、`desktop_management_page_impl.dart:296 _loadSeats` | `GET https://{domain}/api/seatlist` | `GET {AppConfig.baseUrl}/terminals?merchant_id={id}`；返回字段 `remoting_users` 替代旧 `remote` |

### E. 操作日志埋点（**新增**，对齐 Web）

| 功能模块 | 代码地址 | 改动前调用 | 改动后调用 |
|---|---|---|---|
| 远程/唤醒/断开成功后 | `terminal_detail_page.dart`、`monitor_page.dart` 各远程入口 | — | `POST {AppConfig.baseUrl}/operationLog` body `{event,description}` |

---

## 三、不改的接口（明确不动）

| 功能模块 | 代码地址 | 原因 |
|---|---|---|
| 远程唤醒 WOL | `terminal_api.dart:590 wakeOnLan` | WOL 魔术包必须本地网关发，保留 `GET https://{domain}/api/awaken?seat=` |
| VNC 浏览器跳转 URL | `terminal_detail_page.dart:1657-1667` | noVnc 模板/参数不变，只改前置 `remote` 调用 |
| WebRTC 信令 URL | `terminal_detail_page.dart:1530-1573` | `wss://webrtc.03kan.com/ws?Peer=…` 不变，只改前置 `remote` 调用 |
| 路由器后台跳转 | `monitor_page.dart:1095-1106 _openRouterInBrowser` | `proxyUrl` 由后端下发，前端只 `launchUrl` |
