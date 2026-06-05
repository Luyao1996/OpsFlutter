# 网吧管理 - 终端 CPU/内存/GPU 占用 接口文档

> 本文档面向对接开发者，描述【网吧管理】中终端 CPU/内存/GPU 占用数据的获取通道、请求格式与返回字段。
>
> **范围说明**：本文档基于管理端（Flutter 前端）源码核对得出。终端机上的采集程序（agent，C++/Go）与中央服务器代码不在前端仓库，因此「终端如何采集（WMI/性能计数器）、采集频率」无法从前端验证，文中已标注，请向 agent/服务端开发者确认。

---

## 0. 数据来源总览

终端硬件占用数据有**两个粒度、两个通道**，前端按场景分别使用：

| 通道 | 协议 | 用途 | 粒度 | 证据 |
|------|------|------|------|------|
| ① 座位列表 | 中央 HTTP `GET /api/terminals` | 列表整体快照（每个终端一行 CPU/内存/GPU/磁盘 百分比） | 粗（单个百分比） | `terminal_api.dart:177-204` |
| ② 硬件信息 | WebSocket `fun:'hwinfo'` | 卡片 hover 实时数值 + 详情页完整硬件树 | 细（逐设备明细） | `terminal_api.dart:556-613` |

> ⚠️ 数据**源头**（终端机如何采集）在终端 agent 程序中，不在前端仓库，无法验证。

---

## 1. 通道①：座位列表（粗粒度，HTTP）

### 请求

```
GET https://admin.wwls.net/api/terminals?merchant_id={商户ID}
```

- base URL：`/api`（**注意不是 `/api/v1`**），证据 `app_config.dart:4-7`
- 响应拦截器已剥外壳，`data` 字段即下方数组

### 响应（数组，每个终端一项）

字段来自 `Terminal.fromJson`，证据 `terminal_models.dart:66-168`：

```json
[
  {
    "id": 1001,
    "seat": "A01",
    "name": "A区001号",
    "ip": "192.168.1.100",
    "mac": "00:1A:2B:3C:4D:5E",
    "os": "Windows 10",
    "mode": 0,
    "is_online": true,
    "cpu_usage": 45.5,
    "ram_usage": 62.3,
    "gpu_usage": 78.9,
    "disk_usage": 35.2,
    "uptime": "5天3小时",
    "version": "2.1.0",
    "online_at": "...",
    "last_heartbeat": "...",
    "screenshot_url": "...",
    "remoting_users": [],
    "remark": "<p>...</p>"
  }
]
```

| 字段 | 类型 | 单位/取值 | 含义 |
|------|------|-----------|------|
| `cpu_usage` | double | 0–100 (%) | CPU 使用率 |
| `ram_usage` | double | 0–100 (%) | 内存使用率 |
| `gpu_usage` | double | 0–100 (%) | GPU 使用率 |
| `disk_usage` | double | 0–100 (%) | 磁盘使用率 |
| `mode` | int | 0=终端 / 1=主服务器 / 2=副服务器 | 设备类型 |
| `is_online` | bool | — | 在线状态 |

> 兼容性：前端同时兼容旧字段名 `cpuUsage/ramUsage/...` 和旧 `/seatlist` 格式（`online` 字段），见 `terminal_models.dart:150-153, 112-119`。

---

## 2. 通道②：硬件信息（细粒度，WebSocket）

### 2.1 WebSocket 外壳协议

证据 `task_ws.dart:36-38`：

**请求帧**

```json
{
  "event": "peer",
  "id": "<自动生成>",
  "merchant_id": 1,
  "data": {
    "fun": "hwinfo",
    "seat": "A01",
    "data": { "type": "info" }
  }
}
```

`data.data.type` 取值：`info`=静态硬件信息 / `realtime`=实时占用。

**响应帧**（剥掉 `event:peer` 外壳后的业务对象）

```json
{ "code": 0, "msg": "...", "data": { ... }, "fun": "hwinfo" }
```

- `code != 0` 视为失败，前端返回 null，证据 `terminal_api.dart:617-624`
- 前端拉取硬件信息时会发**两次** `hwinfo`：`type:'info'`（静态）+ `type:'realtime'`（实时），再合并，证据 `terminal_api.dart:564-586`

### 2.2 `type:'realtime'` 返回结构（占用率核心）

证据 `terminal_api.dart:779-899`，`monitor_page.dart:194-216`：

```json
{
  "cpu":    [ { "id": "...", "load_total": 45.5, "clock_core": 3600000000, "power": 65.2 } ],
  "gpu":    [ { "id": "...", "load_gpu": 78.9, "load_memory": 62.3,
                "temperature": 72, "temperature_memory": 65, "temperature_hotspot": 80,
                "clock_core": 1950000000, "clock_memory": 7000000000, "power": 285.5 } ],
  "memory": [ { "load_total": 62.3 } ],
  "storage":[ { "id": "...", "used_space": 524288000000, "free_space": 976000000000, "health": 98 } ],
  "network":[ { "id": "...", "upload_speed": 1024000, "download_speed": 5120000 } ]
}
```

| 字段 | 类型 | 单位 | 含义 |
|------|------|------|------|
| `cpu[].load_total` | num | % | **CPU 总占用率** |
| `cpu[].clock_core` | num | Hz | CPU 实时频率 |
| `cpu[].power` | num | W | CPU 功耗 |
| `gpu[].load_gpu` | num | % | **GPU 核心占用率** |
| `gpu[].load_memory` | num | % | GPU 显存占用率 |
| `gpu[].temperature` / `_memory` / `_hotspot` | num | °C | GPU 核心/显存/热点温度 |
| `gpu[].clock_core` / `clock_memory` | num | Hz | GPU 核心/显存频率 |
| `gpu[].power` | num | W | GPU 功耗 |
| `memory[].load_total` | num | % | **内存占用率**（可为对象或数组，多条取均值，见 `monitor_page.dart:206-215`）|
| `storage[].used_space` / `free_space` | num | Bytes | 磁盘已用/剩余 |
| `storage[].health` | num | % | 磁盘健康度 |
| `network[].upload_speed` / `download_speed` | num | Bytes/s | 上/下行速度 |

> ⚠️ `memory` 字段前端兼容两种形态：**对象** `{load_total}` 或 **数组** `[{load_total}, ...]`，对接时建议统一。证据 `monitor_page.dart:206-215`。

### 2.3 `type:'info'` 返回结构（静态硬件，非占用率）

详情页用，证据 `terminal_api.dart:778-918`。各分类字段：

- `cpu[]`: `id, name, vendor, core_count, thread_count, base_freq(Hz), l1_cache, l2_cache, l3_cache(Bytes)`
- `gpu[]`: `id, name, vendor, memory_total(Bytes)`
- `memory[]`: `size(Bytes), speed(MHz), type, form_factor, manufacturer, voltage(V), data_width(bit)`
- `storage[]`: `id, model, size(Bytes), type, interface, rotation(RPM), serial, firmware`
- `network[]`: `id, description, name, ip_address, gateway, subnet_mask, mac, speed, dns`
- `motherboard[]`: `manufacturer, product, version, bios_vendor, bios_version, bios_date`

`info` 与 `realtime` 通过 **`id` 字段配对**合并（同一块 GPU/磁盘），证据 `terminal_api.dart:924-930`。

---

## 3. 前端使用方式（占用率怎么显示）

| 场景 | 行为 | 取值 | 证据 |
|------|------|------|------|
| 卡片 hover | 进入卡片后**每 500ms** 轮询一次 `getHardwareRealtime`，离开即停并清缓存 | `cpu[0].load_total` / `gpu[0].load_gpu` / `memory.load_total` | `monitor_page.dart:257-277` |
| 列表整体 | 加载时取 HTTP `/terminals` 的 `cpu_usage/ram_usage/gpu_usage` 快照 | 通道① | `terminal_api.dart:177` |
| 详情页 | `getHardwareInfo` 拉 info+realtime 合并成完整硬件树 | 通道② 全字段 | `terminal_api.dart:558` |

> 注意：500ms 是**前端轮询拉取频率**，不等于终端实际采集频率（采集频率取决于 agent，未知）。

---

## 4. 进程级 CPU/内存（附）

另有 `fun:'processTree'` 返回进程树，含每进程 CPU/内存：字段 `ProcessId / ProcessName / cpuUsage / memoryUsage(Bytes) / User / ThreadCount / children`，证据 `terminal_models.dart:276-310`、`terminal_api.dart:291-326`。

---

## 关键源码索引

| 内容 | 文件:行 |
|------|---------|
| Terminal 模型/字段 | `lib/features/monitor/data/terminal_models.dart:4-234` |
| HTTP 列表接口 | `lib/features/monitor/data/terminal_api.dart:177-204` |
| hwinfo 拉取 | `terminal_api.dart:556-613` |
| realtime/info 字段解析 | `terminal_api.dart:773-930` |
| WS 协议外壳 | `lib/core/network/task_ws.dart:36-104` |
| hover 500ms 轮询 | `lib/features/monitor/presentation/monitor_page.dart:257-277` |
| base URL `/api` | `lib/core/config/app_config.dart:4-7` |
