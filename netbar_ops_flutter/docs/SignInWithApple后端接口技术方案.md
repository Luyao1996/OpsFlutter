# Sign in with Apple 后端接口技术方案（PHP）

> 交付对象：passport 认证服务（admin.wwls.net）后端开发
> 需求方：iOS App（智维网吧管家，Bundle ID `com.netbarops.netbarOpsFlutter`）
> 日期：2026-08-03

---

## 1. 背景与目标

iOS App 需要上线微信登录。App Store 审核条款 **Guideline 4.8（Login Services）** 强制要求：提供第三方登录（微信）的 App 必须同时提供 Sign in with Apple（下称 SIWA）作为等效登录方式。**该条款我们已被实测拒审过，无豁免可能**，因此 SIWA 是微信登录上线的前置硬依赖。

- **微信登录**：复用现有小程序扫码/深链会话机制（`/passport/login/qr` + `/passport/token`），**后端零改动**。
- **SIWA**：后端需新增 **2 个接口 + 1 张表**，即本文档全部工作量。

### 账号体系适配

我们是 B2B 系统，账号由管理员后台分配、无公开注册。SIWA 采用**「首次登录即关联」**模式：

```
用户点"通过 Apple 登录"
  → iOS 弹 Apple 授权，App 拿到 identityToken（一个 Apple 签名的 JWT）
  → App 调【接口一】登录
      ├─ 该 Apple 账号已关联过系统账号 → 直接发业务 token（老用户一键登录）
      └─ 未关联 → 返回 APPLE_ID_NOT_BOUND
          → App 弹"关联已有账号"窗，用户输一次账密
          → App 调【接口二】完成 绑定+登录
          → 之后该 Apple 账号一键登录
```

Apple 授权后我们拿到的用户标识是 `sub`（一串稳定的不透明字符串，同一 Apple ID 对我们 App 永远不变），绑定关系即 `sub ↔ 系统用户`。

---

## 2. 数据库设计

新表（表名按你们惯例调整）：

```sql
CREATE TABLE `apple_binding` (
  `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id`    INT UNSIGNED NOT NULL COMMENT '系统用户ID（关联现有用户表）',
  `apple_sub`  VARCHAR(64)  NOT NULL COMMENT 'Apple identityToken 的 sub 声明',
  `created_at` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_apple_sub` (`apple_sub`),
  KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Apple登录绑定关系';
```

设计说明：

- `apple_sub` 全局唯一：一个 Apple 账号只能关联一个系统账号（防串号）。
- `user_id` 不唯一：允许一个系统账号被多个 Apple 账号关联（如员工换 Apple ID 后重新绑定，旧绑定不清理也不影响；是否提供解绑/清理入口见 §6 可选项）。

---

## 3. 接口设计

两个接口都挂在与现有账密登录相同的前缀下（现有：`POST /alpha/passport/login`）。

### 3.1 接口一：Apple 登录

```
POST /alpha/passport/login/apple
Content-Type: application/json
```

**请求体**：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `identity_token` | string | 是 | Apple 返回的 JWT 原文（三段式 `xxx.yyy.zzz`） |
| `nonce` | string | 是 | App 生成的随机串**原文**（防重放，校验方式见 §4.2 第 5 步） |

**响应**：

成功（sub 已有绑定）——**与现有 `/alpha/passport/login` 返回结构完全一致**，App 端零适配：

```json
{ "access_token": "...", "token_type": "Bearer", "create_in": 1780000000, "expire_in": 7200 }
```

失败：

| HTTP | code | 场景 |
|---|---|---|
| 404 | `APPLE_ID_NOT_BOUND` | token 验证通过，但 sub 无绑定记录（App 据此弹关联窗，**必须稳定返回此错误码**，这是关联流程的分支依据） |
| 401 | `INVALID_APPLE_TOKEN` | token 验签失败 / 过期 / iss/aud/nonce 不符（细分原因写日志，不外露） |
| 403 | `ACCOUNT_DISABLED` | sub 有绑定但对应账号已停用（与账密登录停用行为对齐） |

错误响应体格式与你们现有错误结构对齐即可，但**必须包含可供客户端判定的 `code` 字段**，例如：

```json
{ "code": "APPLE_ID_NOT_BOUND", "message": "该 Apple 账号尚未关联系统账号" }
```

### 3.2 接口二：绑定并登录

```
POST /alpha/passport/login/apple/bind
Content-Type: application/json
```

**请求体**：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `identity_token` | string | 是 | 同上（App 会在关联窗提交时**重新拉起 Apple 授权**取新 token，避免过期） |
| `nonce` | string | 是 | 同上 |
| `username` | string | 是 | 已有系统账号 |
| `password` | string | 是 | 密码（校验逻辑与 `/alpha/passport/login` 完全一致，含失败限流策略） |

**处理流程**：验证 identity_token（§4）→ 校验账密 → 事务内写入 `apple_binding` → 返回 access_token（同上成功结构）。

**失败**：

| HTTP | code | 场景 |
|---|---|---|
| 401 | `INVALID_APPLE_TOKEN` | token 无效 |
| 401 | `INVALID_CREDENTIALS` | 账密错误（与现有账密登录错误行为/限流对齐） |
| 403 | `ACCOUNT_DISABLED` | 账号停用 |
| 409 | `APPLE_ID_ALREADY_BOUND` | 该 sub 已绑定其他系统账号（并发/重复提交兜底，依赖 `uk_apple_sub` 唯一键捕获） |

---

## 4. identityToken 验证（核心，必须逐条实现）

### 4.1 它是什么

Apple 签发的 RS256 JWT，payload 示例：

```json
{
  "iss": "https://appleid.apple.com",
  "aud": "com.netbarops.netbarOpsFlutter",
  "exp": 1780001234,
  "iat": 1780000634,
  "sub": "001234.abc567def890...",
  "nonce": "9f86d081884c7d65...",
  "nonce_supported": true,
  "auth_time": 1780000634
}
```

注意：我们 App 端申请授权时不索取 email/姓名（隐私最小化），payload 里可能没有 email 字段，**不要依赖它**。用户身份只认 `sub`。

### 4.2 验证步骤（缺一不可）

1. **验签**：用 Apple 公钥集（JWKS）验证 RS256 签名。公钥集地址：`https://appleid.apple.com/auth/keys`（公开接口，**无需任何 Apple 开发者密钥/证书**）。JWT header 里的 `kid` 指明用哪把公钥。
2. **iss** === `https://appleid.apple.com`
3. **aud** === `com.netbarops.netbarOpsFlutter`（我们的 Bundle ID，写配置不要硬编码）
4. **exp** 未过期（identityToken 有效期很短，约 10 分钟）
5. **nonce**：`hash('sha256', 请求体里的 nonce 原文) === payload 的 nonce 声明`（App 端生成随机串，把它的 sha256 传给 Apple，Apple 原样放进 token；后端比对可防 token 重放）

### 4.3 PHP 参考实现

推荐 `firebase/php-jwt`（^6.0，composer 装）：

```php
use Firebase\JWT\JWT;
use Firebase\JWT\JWK;

const APPLE_ISS = 'https://appleid.apple.com';
const APPLE_AUD = 'com.netbarops.netbarOpsFlutter'; // 放配置

function verifyAppleIdentityToken(string $identityToken, string $rawNonce): object {
    // 1. 取 JWKS（务必缓存，见 4.4）
    $jwksJson = getAppleJwksCached(); // 自行实现：redis/文件缓存 24h
    $keySet = JWK::parseKeySet(json_decode($jwksJson, true), 'RS256');

    // 2. 验签 + exp（decode 内部自动校验签名与过期，kid 自动匹配）
    JWT::$leeway = 30; // 容忍 30s 时钟偏差
    $payload = JWT::decode($identityToken, $keySet); // 失败抛异常 → 401 INVALID_APPLE_TOKEN

    // 3. iss / aud / nonce
    if (($payload->iss ?? '') !== APPLE_ISS)  throw new InvalidAppleTokenException('iss mismatch');
    if (($payload->aud ?? '') !== APPLE_AUD)  throw new InvalidAppleTokenException('aud mismatch');
    if (hash('sha256', $rawNonce) !== ($payload->nonce ?? '')) {
        throw new InvalidAppleTokenException('nonce mismatch');
    }

    return $payload; // 用 $payload->sub 查/写 apple_binding
}
```

### 4.4 JWKS 缓存与轮换

- JWKS 内容缓存 24 小时（redis 或文件均可），不要每次请求都拉 Apple。
- Apple 会轮换密钥：如果 decode 抛「找不到 kid」类异常，**强制刷新一次缓存再重试一次**，仍失败才返回 401。

---

## 5. 安全与日志要求

1. 仅 HTTPS（现状已满足）。
2. **不要把 identity_token 全文写进日志**（它在有效期内等同登录凭证）。日志记 `sub`、JWT header 的 `kid`、失败原因即可。
3. 接口二含密码校验，**必须套用与 `/alpha/passport/login` 相同的防爆破限流**（按 IP+username）。
4. 日志格式沿用项目统一规范：`[time][level][module][operType][contextId] message`，module 建议 `passport.apple`，operType 如 `login`/`bind`，contextId 用请求 ID 或 sub 前 8 位。

---

## 6. 可选项（P2，本期可不做）

- 解绑接口（用户侧或管理后台删除 `apple_binding` 记录）。
- 管理后台展示某用户的 Apple 绑定状态。
- 用户被删除/停用时级联清理绑定（不清理也不影响安全——接口一命中绑定后仍会校验账号状态）。

---

## 7. 联调与验收

### 7.1 测试要点

identityToken 只能由真机 iOS App 产生，且 **10 分钟左右过期**，联调方式：

1. App 端开发（前端侧）在真机触发授权后，把 `identity_token` + `nonce` 原文实时发给你，你用 curl 立刻回放：

```bash
curl -k -X POST https://admin.wwls.net/alpha/passport/login/apple \
  -H 'Content-Type: application/json' \
  -d '{"identity_token":"<真机拿到的JWT>","nonce":"<原文>"}'
```

2. 建议开发环境加一个**仅测试环境生效**的开关：跳过 exp 校验（其余校验保留），这样一个 token 可反复调试。**生产严禁开启**。
3. token 内容可贴到 jwt.io 肉眼核对 payload（注意 jwt.io 不要贴生产期 token）。

### 7.2 验收用例

| # | 用例 | 预期 |
|---|---|---|
| 1 | 未绑定的 sub 调接口一 | 404 `APPLE_ID_NOT_BOUND` |
| 2 | 接口二正确账密 + 有效 token | 绑定成功，返回 access_token，`apple_binding` 落一条记录 |
| 3 | 同一 sub 再调接口一 | 直接返回 access_token（**返回的 token 能正常访问 `/api` 业务接口与 `/passport/profile`**） |
| 4 | 篡改 token 任一段 / token 过期 | 401 `INVALID_APPLE_TOKEN` |
| 5 | nonce 原文传错 | 401 `INVALID_APPLE_TOKEN` |
| 6 | 接口二密码错误 | 401 `INVALID_CREDENTIALS`，且触发限流计数 |
| 7 | 已绑定账号 A 的 sub 用账号 B 走接口二 | 409 `APPLE_ID_ALREADY_BOUND` |
| 8 | 停用账号的绑定 sub 调接口一 | 403 `ACCOUNT_DISABLED` |

### 7.3 工作量参考

接口 + 表 + 验证逻辑约 0.5~1 人天，联调 0.5 人天（依赖 iOS 侧就绪，双方约时间实时回放 token）。

---

## 附：常见疑问

- **需要 Apple 开发者账号里的什么密钥吗？** 不需要。验 identityToken 只用 Apple 公开的 JWKS。（网上教程里的 client_secret/私钥 .p8 是"服务端换 refresh_token"流程用的，我们的登录场景用不到。）
- **微信登录要后端做什么？** 什么都不做，完全复用现有扫码会话机制。
- **sub 会变吗？** 同一 Apple ID 对同一开发者团队的 App 永远不变（用户在 Apple 侧"停止使用该 App"后重新授权，sub 也不变）。
