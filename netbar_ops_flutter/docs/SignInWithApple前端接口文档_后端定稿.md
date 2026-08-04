# Sign in with Apple 前端接口文档

## 1. 文档范围

本文档描述前端接入 Apple 登录和 Apple 账号绑定时使用的后端 HTTP 接口协议。

接口统一位于 Alpha Passport 模块：

```text
{BASE_URL}/alpha/passport
```

本文档不包含 Apple SDK 调用代码。前端需要自行通过 Apple SDK 获得：

- `identity_token`：Apple 返回的身份 JWT。
- `nonce`：发起 Apple 授权时生成的原始 nonce。后端会验证 `identity_token` 中的 nonce 是否为该原始值的 SHA-256 摘要。

## 2. 通用约定

### 2.1 请求格式

除特别说明外，请求使用 JSON：

```http
Content-Type: application/json
Accept: application/json
```

### 2.2 响应格式

业务响应统一使用以下结构：

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

字段说明：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `code` | integer | `0` 表示成功，`1` 表示业务失败，`401` 表示用户身份认证失败。 |
| `message` | string | 可展示或用于辅助排查的中文提示。前端业务分支不要依赖该文本。 |
| `data` | object | 接口数据。没有数据时通常为空对象或空数组。 |
| `error_code` | string | Apple 业务失败时返回的稳定错误码。前端应优先根据该字段分支。 |

说明：

- 当前接口主要通过响应体中的 `code` 表达业务结果，前端不能只依据 HTTP 状态码判断成功。
- Apple 接口响应均包含以下响应头：

```http
Cache-Control: no-store
Pragma: no-cache
```

- 前端不得持久化或记录完整的 `identity_token`、`nonce`、`bind_ticket`、密码或业务 JWT。

## 3. Apple 登录

### 3.1 接口

```http
POST /alpha/passport/login/apple
```

该接口不要求业务 JWT。

### 3.2 请求参数

```json
{
  "identity_token": "eyJraWQiOiJ...",
  "nonce": "frontend-generated-raw-nonce"
}
```

| 字段 | 类型 | 必填 | 约束 | 说明 |
| --- | --- | --- | --- | --- |
| `identity_token` | string | 是 | 最大 16384 字符 | Apple SDK 返回的身份 JWT。 |
| `nonce` | string | 是 | 8～512 字符 | 发起本次 Apple 授权时使用的原始 nonce，不是 SHA-256 后的值。 |

前端必须确保请求中的 `identity_token` 和 `nonce` 来自同一次 Apple 授权流程。

### 3.3 已绑定：登录成功

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "access_token": "eyJ0eXAiOiJKV1QiLCJhbGciOi...",
    "token_type": "Bearer",
    "create_in": 1785813000,
    "expire_in": 3600
  }
}
```

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `access_token` | string | 系统业务 JWT，后续接口通过 Bearer 请求头携带。 |
| `token_type` | string | 固定为 `Bearer`。 |
| `create_in` | integer | JWT 签发时间，Unix 秒级时间戳。 |
| `expire_in` | integer | JWT 有效秒数。 |

后续请求示例：

```http
Authorization: Bearer {access_token}
```

注意：Apple 登录签发的 JWT 可以正常访问业务接口，但不能直接作为“近期真实认证证明”绑定 Apple 账号。

### 3.4 未绑定：进入绑定流程

```json
{
  "code": 1,
  "message": "Apple 账号尚未绑定",
  "data": {
    "bind_ticket": "one-time-bind-ticket",
    "expires_in": 300
  },
  "error_code": "APPLE_NOT_BOUND"
}
```

`APPLE_NOT_BOUND` 是正常业务分支，不表示 Apple 授权失败。前端收到后应：

1. 暂存在内存中的 `bind_ticket`。
2. 引导用户通过现有账号密码登录系统。
3. 使用该次真实登录返回的业务 JWT 调用 Apple 绑定接口。

票据约束：

- `bind_ticket` 有效期为 300 秒。
- 票据只能成功消费一次。
- 不建议写入日志、本地持久化存储、埋点或崩溃报告。
- 票据过期后，重新发起 Apple 登录即可获得新票据。

### 3.5 登录失败示例

```json
{
  "code": 1,
  "message": "Apple 身份凭证无效",
  "data": [],
  "error_code": "INVALID_APPLE_TOKEN"
}
```

## 4. Apple 账号绑定

### 4.1 接口

```http
POST /alpha/passport/login/apple/bind
Authorization: Bearer {access_token}
Content-Type: application/json
```

### 4.2 前置条件

调用绑定接口必须同时满足：

1. `bind_ticket` 来自 Apple 登录接口返回的 `APPLE_NOT_BOUND` 分支，且未过期、未消费。
2. `Authorization` 必须是标准 Bearer 请求头。
3. JWT 必须来自近期完成的 Alpha 账号密码登录。
4. JWT 对应的近期认证窗口为 600 秒。
5. 微信或二维码登录 JWT、刷新 JWT、Apple 登录 JWT、临时 JWT、接口口令、Query Token 和仅存在于 Session 中的 JWT 均不能完成绑定。

最直接的账号密码登录入口为：

```http
POST /alpha/passport/login
```

账号密码登录成功后，应直接使用该响应中的 `access_token` 调用绑定接口。不要先刷新 Token。

### 4.3 请求参数

```json
{
  "bind_ticket": "one-time-bind-ticket"
}
```

| 字段 | 类型 | 必填 | 约束 | 说明 |
| --- | --- | --- | --- | --- |
| `bind_ticket` | string | 是 | 最大 128 字符 | Apple 登录接口签发的一次性绑定票据。 |

绑定接口不需要再次提交 `identity_token` 或 `nonce`。

### 4.4 绑定成功

```json
{
  "code": 0,
  "message": "Apple 账号绑定成功",
  "data": []
}
```

绑定成功后：

- 当前业务 JWT 保持不变，后端不会签发或替换 Token。
- 前端可以继续使用当前 JWT。
- 用户以后可直接通过 Apple 登录获得业务 JWT。

### 4.5 身份认证失败

绑定请求没有携带可接受的正常用户 JWT 时，可能在控制器执行前返回：

```json
{
  "code": 401,
  "message": "无效的口令",
  "data": []
}
```

该响应可能没有 `error_code`。前端遇到 `code = 401` 时应要求用户重新完成 Alpha 账号密码登录，再重新调用绑定接口。

## 5. Apple 账号解绑

### 5.1 接口

```http
POST /alpha/passport/apple/unbind
Authorization: Bearer {recent_password_login_access_token}
Content-Type: application/json

{}
```

请求体不接收 `user_id`、Apple `sub` 或密码。解绑目标始终是 Bearer JWT 对应的当前用户。

### 5.2 前置条件

解绑属于账号安全操作，必须满足：

1. 用户重新完成 Alpha 账号密码登录。
2. 使用该次登录返回的正常业务 JWT 调用解绑接口。
3. JWT 对应的近期认证窗口未超过 600 秒。
4. Apple 登录、微信或二维码登录、refresh、临时 JWT、接口口令、Query Token 和仅存在于 Session 中的 JWT 均不能解绑。

不要在解绑接口中再次提交密码，也不要通过刷新 JWT 延长近期认证窗口。

### 5.3 解绑成功

```json
{
  "code": 0,
  "message": "Apple 账号解绑成功",
  "data": []
}
```

当前用户没有 Apple 绑定时也返回相同成功响应，因此前端可以安全重试，但应避免连续点击。

解绑成功后：

- 当前业务 JWT 继续有效，不会强制退出当前会话。
- 原 Apple ID 以后不能直接登录；再次登录时返回 `APPLE_NOT_BOUND`。
- 如需恢复 Apple 登录，必须重新进行 Alpha 账号密码登录并走现有绑定票据流程。

### 5.4 推荐解绑流程

```text
用户在账号安全页点击解除 Apple 绑定
    ↓
前端二次确认
    ↓
用户重新完成 Alpha 账号密码登录
    ↓
POST /alpha/passport/apple/unbind
Authorization: Bearer {recent_password_login_access_token}
    ├─ code=0
    │    └─ 清除前端 Apple 已绑定状态，继续保留当前会话
    │
    ├─ error_code=RECENT_LOGIN_REQUIRED 或 code=401
    │    └─ 重新进行 Alpha 账号密码登录，不使用 refresh、Apple 或微信登录
    │
    └─ error_code=APPLE_UNBIND_FAILED
         └─ 保留当前展示状态，提示稍后重试或重新查询账号状态
```

## 6. 推荐绑定流程

### 6.1 流程说明

```text
用户点击 Apple 登录
    ↓
前端生成原始 nonce，并通过 Apple SDK 完成授权
    ↓
POST /alpha/passport/login/apple
    ├─ code=0
    │    └─ 已绑定：保存 access_token，进入系统
    │
    └─ error_code=APPLE_NOT_BOUND
         ↓
       前端暂存 bind_ticket
         ↓
       引导用户通过 Alpha 账号密码登录
         ↓
       获得刚完成真实认证的 access_token
         ↓
       POST /alpha/passport/login/apple/bind
       Authorization: Bearer {access_token}
         ├─ code=0
         │    └─ 绑定成功，继续使用当前 access_token
         │
         └─ code=1/401
              └─ 根据 error_code 或 code 提示重试、重新登录或重新获取票据
```

### 6.2 完整 HTTP 示例

第一步，尝试 Apple 登录：

```http
POST /alpha/passport/login/apple
Content-Type: application/json

{
  "identity_token": "{apple_identity_token}",
  "nonce": "{raw_nonce}"
}
```

响应未绑定：

```json
{
  "code": 1,
  "message": "Apple 账号尚未绑定",
  "data": {
    "bind_ticket": "{bind_ticket}",
    "expires_in": 300
  },
  "error_code": "APPLE_NOT_BOUND"
}
```

第二步，使用现有账号登录：

```http
POST /alpha/passport/login
Content-Type: application/json

{
  "username": "existing-user",
  "password": "user-password"
}
```

响应成功：

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "access_token": "{recent_login_access_token}",
    "token_type": "Bearer",
    "create_in": 1785813000,
    "expire_in": 3600
  }
}
```

第三步，绑定 Apple 账号：

```http
POST /alpha/passport/login/apple/bind
Authorization: Bearer {recent_login_access_token}
Content-Type: application/json

{
  "bind_ticket": "{bind_ticket}"
}
```

响应成功：

```json
{
  "code": 0,
  "message": "Apple 账号绑定成功",
  "data": []
}
```

第四步，可选验证：退出当前账号后重新执行 Apple 登录。此时接口应直接返回新的业务 JWT。

## 7. 稳定错误码

| `error_code` | 可能出现的接口 | 含义 | 前端建议 |
| --- | --- | --- | --- |
| `INVALID_APPLE_TOKEN` | Apple 登录 | `identity_token` 格式、签名、声明或 nonce 无效。 | 终止本次登录；重新生成 nonce 并重新发起 Apple 授权。 |
| `APPLE_NOT_BOUND` | Apple 登录 | Apple 身份有效，但尚未绑定系统账号。 | 保存本次 `bind_ticket`，进入现有账号登录和绑定流程。 |
| `ACCOUNT_DISABLED` | Apple 登录 | Apple 绑定的系统账号已停用。 | 提示账号已停用，不要继续重试。 |
| `INVALID_BIND_TICKET` | Apple 绑定 | 票据格式错误、过期、已消费或不存在。 | 重新发起 Apple 登录获取新票据。 |
| `BIND_TICKET_BUSY` | Apple 绑定 | 同一票据正在被另一个请求处理。 | 禁止并发提交；短暂等待后查询结果或重试一次。 |
| `APPLE_ALREADY_BOUND` | Apple 绑定 | 该 Apple 身份已绑定其他系统账号。 | 提示用户切换正确的系统账号；不要自动覆盖绑定。 |
| `USER_ALREADY_BOUND_APPLE` | Apple 绑定 | 当前系统账号已绑定其他 Apple 身份。 | 提示当前账号已有 Apple 绑定；不要自动覆盖。 |
| `RECENT_LOGIN_REQUIRED` | Apple 绑定、解绑 | 当前 JWT 没有匹配的近期账号密码认证证明。 | 重新进行 Alpha 账号密码登录，并使用新返回的 JWT 立即完成敏感操作。 |
| `APPLE_SERVICE_UNAVAILABLE` | Apple 登录 | Apple 公钥服务暂时不可用且后端无可用缓存。 | 提示稍后重试，避免快速循环请求。 |
| `APPLE_LOGIN_DISABLED` | Apple 登录、绑定、解绑 | 后端尚未启用 Apple 登录。 | 隐藏或禁用 Apple 相关入口，并上报环境配置问题。 |
| `TOO_MANY_ATTEMPTS` | Apple 登录、绑定、解绑 | 请求触发 IP、用户或 Apple subject 限流。 | 根据产品策略等待后重试，禁止立即循环请求。 |
| `APPLE_LOGIN_FAILED` | Apple 登录 | 后端发生未预期登录异常。 | 展示通用失败提示并允许稍后重试。 |
| `APPLE_BIND_FAILED` | Apple 绑定 | 后端发生未预期绑定异常。 | 保留当前登录态；必要时重新获取票据后重试。 |
| `APPLE_UNBIND_FAILED` | Apple 解绑 | 后端发生未预期解绑异常。 | 不假定绑定已删除；保留当前展示状态并允许稍后重试。 |

前端不得根据 `message` 精确文本判断错误类型，必须优先使用 `error_code`。

## 8. 前端状态处理建议

建议至少维护以下状态：

```text
idle
apple_authorizing
apple_logging_in
existing_account_login_required
binding
unbinding
authenticated
failed
```

关键约束：

- Apple 登录请求和绑定请求都要防止重复点击和并发提交。
- `APPLE_NOT_BOUND` 应进入账号绑定页面，而不是展示为通用错误弹窗。
- `INVALID_BIND_TICKET` 应重新走 Apple 授权，不应只重复提交旧票据。
- `RECENT_LOGIN_REQUIRED` 应重新走现有账号登录，不应通过刷新 JWT 解决。
- `code = 401` 时清理失效业务 JWT，但不要把完整 Token 写入日志。
- 绑定成功后不需要替换当前 JWT，也不需要再次调用绑定接口。
- 解绑成功后不需要退出当前会话，但应立即更新账号安全页的 Apple 绑定展示。

## 9. 联调检查清单

- [ ] 相同的原始 nonce 同时用于 Apple 授权和后端 Apple 登录请求。
- [ ] 已绑定 Apple 身份可以直接获得业务 JWT。
- [ ] 未绑定 Apple 身份返回 `APPLE_NOT_BOUND` 和 300 秒票据。
- [ ] 绑定前完成 Alpha 账号密码登录。
- [ ] 绑定请求只通过 `Authorization: Bearer` 携带正常业务 JWT。
- [ ] 绑定请求不提交 `identity_token`、`nonce` 或密码。
- [ ] 绑定成功后继续使用原业务 JWT。
- [ ] 票据过期、近期登录过期、重复绑定和账号冲突均按稳定错误码处理。
- [ ] 解绑前重新完成 Alpha 账号密码登录，且请求体不提交用户 ID、Apple sub 或密码。
- [ ] 未绑定状态重复解绑仍返回成功。
- [ ] 解绑后当前 JWT 继续有效，原 Apple ID 再次登录返回 `APPLE_NOT_BOUND`。
- [ ] 前端日志、埋点和崩溃报告不包含完整凭证。
