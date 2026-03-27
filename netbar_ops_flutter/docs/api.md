# RouterProxy API 文档

所有 API 基础路径：`/api`

## 通用说明

### 认证方式

受保护接口需要在请求头中携带 JWT Token：

```
Authorization: Bearer {token}
```

Token 通过 `/api/auth/login` 获取，有效期 24 小时。

### 错误响应格式

所有接口的错误响应统一为：

```json
{
  "error": "错误描述信息"
}
```

### HTTP 状态码

| 状态码 | 含义 | 场景 |
|--------|------|------|
| 200 | 成功 | GET 查询、PUT 更新、POST 操作 |
| 201 | 已创建 | POST 创建资源 |
| 400 | 请求无效 | 参数校验失败、JSON 格式错误 |
| 401 | 未授权 | Token 无效或过期 |
| 404 | 不存在 | 路由器/脚本不存在 |
| 500 | 服务器错误 | 文件读写失败、内部异常 |
| 502 | 网关错误 | 请求路由器失败（超时、连接拒绝等） |

---

## 一、认证（无需 JWT）

### 1.1 获取服务器时间

```
GET /api/auth/time
```

获取服务器当前时间，用于前端计算动态密码。

**响应：**

```json
{
  "time": "2026-03-17T14:30:45+08:00",
  "display": "14:30:45"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | string | RFC3339 格式完整时间 |
| `display` | string | HH:MM:SS 格式，用于界面显示 |

---

### 1.2 登录

```
POST /api/auth/login
```

使用动态密码登录，获取 JWT Token。

**请求体：**

```json
{
  "password": "hudd416341714"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `password` | string | 是 | 动态密码，格式：`hudd416{分钟2位}{小时2位}{日期2位}` |

**密码计算示例：** 2026-03-17 14:34 → `hudd416` + `34` + `14` + `17` = `hudd4163414`17`

**成功响应（200）：**

```json
{
  "success": true,
  "token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**失败响应（401）：**

```json
{
  "success": false,
  "error": "密码错误"
}
```

---

## 二、路由器管理（需 JWT）

### 2.1 获取所有路由器

```
GET /api/routers
```

返回所有路由器列表，包含代理地址信息。

**响应（200）：**

```json
[
  {
    "id": "643b87b7",
    "name": "办公室",
    "host": "192.168.1.1",
    "type": "TPLink",
    "user": "admin",
    "pass": "admin",
    "enabled": true,
    "proxyUrl": "http://643b87b7.router-7GzPA8J3Z9By.net.hudd.cc",
    "isIp": false
  }
]
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 路由器 ID（UUID 前 8 位） |
| `name` | string | 路由器名称 |
| `host` | string | 路由器地址（IP:端口 或 域名） |
| `type` | string | 路由器类型（对应脚本名，如 `TPLink`） |
| `user` | string | 登录账号 |
| `pass` | string | 登录密码 |
| `enabled` | boolean | 是否启用 |
| `proxyUrl` | string | 代理访问地址 |
| `isIp` | boolean | 是否通过 IP 访问（IP 访问时 proxyUrl 为空） |

---

### 2.2 获取单个路由器

```
GET /api/routers/:id
```

| 参数 | 位置 | 说明 |
|------|------|------|
| `id` | 路径 | 路由器 ID |

**响应（200）：** 单个路由器对象（同列表中的元素格式）

**错误（404）：** 路由器不存在

---

### 2.3 创建路由器

```
POST /api/routers
```

**请求体：**

```json
{
  "name": "新路由器",
  "host": "192.168.1.1",
  "type": "TPLink",
  "user": "admin",
  "pass": "admin123",
  "enabled": true
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 路由器名称 |
| `host` | string | 是 | 路由器地址。自动去除 `http://`/`https://` 前缀 |
| `type` | string | 否 | 路由器类型（需与脚本名匹配） |
| `user` | string | 否 | 登录账号 |
| `pass` | string | 否 | 登录密码 |
| `enabled` | boolean | 否 | 是否启用，默认 false |

**去重规则：** 相同 `host` + `user` 组合不允许重复添加。

**成功响应（201）：** 返回创建的路由器对象（含自动生成的 `id`）

**错误（400/500）：**

```json
{
  "error": "已存在相同地址和账号的路由器: 办公室 (643b87b7)"
}
```

**副作用：** 自动更新 frpc 配置并重启。

---

### 2.4 更新路由器

```
PUT /api/routers/:id
```

| 参数 | 位置 | 说明 |
|------|------|------|
| `id` | 路径 | 路由器 ID |

**请求体：** 同创建。仅非空字段会被更新（`enabled` 总是更新）。

**去重规则：** 更新后的 `host` + `user` 不能与其他路由器冲突。

**成功响应（200）：** 返回更新后的路由器对象

**副作用：** 自动更新 frpc 配置。

---

### 2.5 删除路由器

```
DELETE /api/routers/:id
```

| 参数 | 位置 | 说明 |
|------|------|------|
| `id` | 路径 | 路由器 ID |

**成功响应（200）：**

```json
{
  "success": true
}
```

**副作用：**
- 从 `user.json` 删除
- 更新 frpc 配置
- 清理流量缓存

---

### 2.6 重新加载路由器配置

```
POST /api/routers/reload
```

从 `user.json` 文件热更新路由器配置（应对外部手动编辑场景）。

**请求体：** 空

**成功响应（200）：**

```json
{
  "success": true,
  "count": 3
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `count` | number | 加载的路由器数量 |

---

## 三、frpc 管理（需 JWT）

### 3.1 获取 frpc 状态

```
GET /api/frpc/status
```

**响应（200）：**

```json
{
  "running": true,
  "pid": 12345,
  "uptime": "2h34m10s",
  "lastError": ""
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `running` | boolean | 是否运行中 |
| `pid` | number | 进程 ID，未运行时为 0 |
| `uptime` | string | 运行时长（如 `1h2m3s`） |
| `lastError` | string | 最近一次错误信息，无错误时为空 |

---

### 3.2 重启 frpc

```
POST /api/frpc/restart
```

停止当前 frpc 进程并重新启动。

**请求体：** 空

**成功响应（200）：**

```json
{
  "success": true,
  "message": "frpc 重启成功"
}
```

**失败响应（500）：**

```json
{
  "success": false,
  "message": "启动 frpc 失败，已重试5次: ..."
}
```

---

## 四、脚本管理（需 JWT）

### 4.1 获取脚本类型列表

```
GET /api/scripts/types
```

返回所有已加载的脚本类型名称（对应 `router/` 目录下的 JSON 文件名）。

**响应（200）：**

```json
["TPLink", "百为", "高格", "爱快"]
```

---

### 4.2 获取所有脚本

```
GET /api/scripts
```

返回所有脚本的完整配置。

**响应（200）：**

```json
[
  {
    "name": "TPLink",
    "type": "login",
    "page": "/login.htm",
    "script": "$(document).ready(function (e) {...})",
    "logFilters": ["/stok=*"],
    "proxyVars": [
      {
        "method": "POST",
        "path": "/",
        "vars": { "stok": "stok" }
      }
    ],
    "tokenRefresh": {
      "method": "GET",
      "path": "/"
    },
    "traffic": {
      "steps": [
        {
          "method": "POST",
          "path": "/stok={stok}/ds",
          "body": "{\"method\":\"get\",\"system\":{\"table\":\"ifstat_list\",...}}"
        }
      ],
      "dataPath": "system.ifstat_list",
      "unwrap": true,
      "mapping": {
        "name": "interface",
        "sendRate": "tx_bps",
        "recvRate": "rx_bps",
        "sendBytes": "tx_bytes",
        "recvBytes": "rx_bytes"
      },
      "lanValue": "lan"
    }
  }
]
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 脚本名称（同文件名） |
| `type` | string | 脚本类型（如 `login`） |
| `page` | string | 注入脚本的页面路径 |
| `script` | string | 注入的 JavaScript 代码。`{#user}` 和 `{#pass}` 为凭据占位符 |
| `logFilters` | string[] | 审计日志过滤路径（匹配的请求不记录日志） |
| `sensitiveFields` | string[] | 额外脱敏字段名 |
| `proxyVars` | ProxyVarRule[] | 代理层变量提取规则 |
| `tokenRefresh` | TokenRefresh | Token 刷新请求配置 |
| `traffic` | TrafficConfig | 流量监控管道配置 |

**ProxyVarRule 结构：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `method` | string | 匹配的 HTTP 方法（GET/POST/PUT） |
| `path` | string | 匹配的请求路径（精确匹配） |
| `vars` | object | 变量提取规则。key=变量名，value=提取路径（JSON 点分路径或 `regex:正则`） |

**TokenRefresh 结构：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `method` | string | HTTP 方法 |
| `path` | string | 请求路径，支持 `{var}` 变量替换 |
| `body` | string | 请求体，支持 `{var}` 变量替换 |
| `contentType` | string | Content-Type |

**TrafficConfig 结构：** 详见 [流量监控步骤说明](流量监控步骤说明.md)

---

### 4.3 创建脚本

```
POST /api/scripts
```

**请求体：**

```json
{
  "name": "新脚本",
  "type": "login",
  "page": "/login.htm",
  "script": "document.querySelector('#btn').click()",
  "logFilters": [],
  "sensitiveFields": [],
  "proxyVars": [],
  "tokenRefresh": null,
  "traffic": null
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 脚本名称（作为文件名保存） |
| `type` | string | 是 | 脚本类型 |
| `page` | string | 是 | 注入页面路径 |
| `script` | string | 否 | JavaScript 脚本内容 |
| 其他字段 | - | 否 | 同获取接口的字段说明 |

**成功响应（201）：** 返回创建的脚本对象

**错误（500）：** `"脚本 xxx 已存在"`

**副作用：** 在 `router/` 目录创建 `{name}.json` 文件

---

### 4.4 更新脚本

```
PUT /api/scripts/:name
```

| 参数 | 位置 | 说明 |
|------|------|------|
| `name` | 路径 | 原脚本名称 |

**请求体：** 同创建。如果新 `name` 与原 `name` 不同，会删除旧文件并创建新文件。

**成功响应（200）：** 返回更新后的脚本对象

---

### 4.5 删除脚本

```
DELETE /api/scripts/:name
```

| 参数 | 位置 | 说明 |
|------|------|------|
| `name` | 路径 | 脚本名称 |

**成功响应（200）：**

```json
{
  "success": true
}
```

**副作用：** 删除 `router/{name}.json` 文件

---

### 4.6 重新加载脚本

```
POST /api/scripts/reload
```

从 `router/` 目录热加载所有脚本文件。

**请求体：** 空

**成功响应（200）：**

```json
{
  "success": true,
  "count": 4
}
```

---

## 五、流量监控（需 JWT）

### 5.1 获取路由器实时流量

```
GET /api/traffic/:id
```

执行路由器的流量监控管道，返回统一格式的接口流量数据。

| 参数 | 位置 | 说明 |
|------|------|------|
| `id` | 路径 | 路由器 ID |

**响应（200）：**

```json
{
  "interfaces": [
    {
      "name": "2_5GE3",
      "alias": "",
      "ip": "",
      "mac": "",
      "sendRate": 34345,
      "recvRate": 4040,
      "sendBytes": 10141430274102,
      "recvBytes": 22896733316976,
      "status": false,
      "type": "wan",
      "bandwidth": 0
    }
  ]
}
```

**TrafficInterface 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | string | 接口名称（如 `GE1`、`eth0`） |
| `alias` | string | 接口别名 |
| `ip` | string | IP 地址 |
| `mac` | string | MAC 地址 |
| `sendRate` | number | 实时发送速率 |
| `recvRate` | number | 实时接收速率 |
| `sendBytes` | number | 累计发送字节数 |
| `recvBytes` | number | 累计接收字节数 |
| `status` | boolean | 接口是否在线 |
| `type` | string | 接口类型：`lan` 或 `wan` |
| `bandwidth` | number | 接口带宽 |

**执行流程：**
1. 获取路由器会话（Cookies + Vars）
2. 获取脚本的 `traffic` 配置
3. 按 `steps` 顺序执行 HTTP 请求（路径和请求体中的 `{var}` 自动替换）
4. 从最后一步响应按 `dataPath` 提取数据数组
5. `unwrap`：展开单 key 对象（如启用）
6. `join`：合并查找表数据（如配置）
7. `mapping`：映射为统一 TrafficInterface 格式

**错误：**
- `404` — 路由器不存在，或该类型未配置流量监控
- `502` — 请求路由器失败（网络超时、认证过期等）

---

### 5.2 测试单个流量步骤

```
POST /api/traffic-test
```

用于调试：向路由器发送单个请求步骤，返回原始响应。

**请求体：**

```json
{
  "routerId": "643b87b7",
  "step": {
    "method": "POST",
    "path": "/stok={stok}/ds",
    "body": "{\"method\":\"get\",\"system\":{\"table\":\"ifstat_list\"}}",
    "contentType": "application/json"
  }
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `routerId` | string | 是 | 路由器 ID |
| `step.method` | string | 是 | HTTP 方法 |
| `step.path` | string | 是 | 请求路径。`{var}` 会被 Session.Vars 中的值替换 |
| `step.body` | string | 否 | 请求体。`{var}` 同样会被替换 |
| `step.contentType` | string | 否 | Content-Type |

**响应（200）：** 路由器返回的原始 JSON 响应（格式化输出）

---

### 5.3 刷新路由器 Token

```
POST /api/token-refresh
```

手动触发路由器的 token 刷新。使用脚本中配置的 `tokenRefresh` 发送请求，并用 `proxyVars` 规则从响应中提取变量，更新到会话。

**请求体：**

```json
{
  "routerId": "643b87b7"
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `routerId` | string | 是 | 路由器 ID |

**成功响应（200）：**

```json
{
  "response": {
    "error_code": 0,
    "stok": "461ab7329882417dc116b35f56cfa07b"
  },
  "vars": {
    "stok": "461ab7329882417dc116b35f56cfa07b"
  }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `response` | object | 路由器返回的原始响应 |
| `vars` | object | 从响应中提取的变量（已存入 Session.Vars） |

**前置条件：**
- 路由器必须有有效的 Cookie（需先通过代理访问过路由器）
- 脚本必须配置了 `tokenRefresh`

**错误：**
- `404` — 路由器不存在，或未配置 token 刷新
- `502` — `"无有效 Cookie，请先访问路由器"` 或请求失败

**自动刷新：** 后台每 5 分钟自动对所有有 Cookie 且配置了 `tokenRefresh` 的路由器执行刷新。

---

## 六、设置管理（需 JWT）

### 6.1 获取敏感字段

```
GET /api/settings/sensitive-fields
```

获取审计日志的全局脱敏字段列表。匹配的字段值在日志中会被替换为 `***FILTERED***`。

**响应（200）：**

```json
{
  "fields": ["password", "pass", "token", "secret", "credential", "auth", "apikey", "api_key"]
}
```

---

### 6.2 更新敏感字段

```
PUT /api/settings/sensitive-fields
```

**请求体：**

```json
{
  "fields": ["password", "pass", "token", "secret", "credential", "auth", "apikey", "api_key", "web_password"]
}
```

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `fields` | string[] | 是 | 敏感字段名数组 |

**成功响应（200）：**

```json
{
  "success": true,
  "fields": ["password", "pass", "token", "secret", "credential", "auth", "apikey", "api_key", "web_password"]
}
```

**存储位置：** `config/sensitive_fields.json`
