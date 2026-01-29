# Flutter前端对接后端API详细方案

> **更新时间**: 2026-01-27
> **状态**: 第一阶段改造已完成

## 已完成的修改文件

### 第一阶段（核心API）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/core/config/app_config.dart` | ✅ 已修改 | API前缀改为 `/api` |
| `lib/core/network/api_client.dart` | ✅ 已修改 | 添加响应解包逻辑 |
| `lib/features/auth/data/auth_api.dart` | ✅ 已修改 | 适配扫码登录流程 |
| `lib/features/netbar/data/netbar_api.dart` | ✅ 已修改 | 适配商户接口 |
| `lib/features/dashboard/data/dashboard_api.dart` | ✅ 已修改 | 适配首页统计接口 |
| `lib/features/netbar/data/group_api.dart` | ✅ 已修改 | 适配分组接口 |
| `lib/features/user/data/user_api.dart` | ✅ 已修改 | 适配用户接口 |
| `lib/features/channel/data/channel_models.dart` | ✅ 已修改 | 适配文件/启动项模型 |
| `lib/features/channel/data/channel_api.dart` | ✅ 已修改 | 适配文件/启动项接口 |
| `lib/features/logs/data/log_types.dart` | ✅ 已修改 | 适配日志模型 |
| `lib/features/logs/data/log_api.dart` | ✅ 已修改 | 适配操作日志接口 |

### 第二阶段（Provider和UI）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/shared/providers/app_providers.dart` | ✅ 已修改 | 添加扫码登录Provider |
| `lib/features/auth/presentation/login_page.dart` | ✅ 已修改 | 支持扫码登录流程 |

### 第三阶段（其他API）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/features/desktop/data/desktop_api.dart` | ✅ 已修改 | 适配 `/api/layout` 接口 |
| `lib/features/desktop/data/desktop_model.dart` | ✅ 已修改 | 适配后端布局字段 |
| `lib/features/netbar/data/area_api.dart` | ✅ 已修改 | 添加 DistrictApi 适配区域接口 |
| `lib/features/channel/data/startup_item_api.dart` | ✅ 已修改 | 适配 `/api/startup` 接口 |
| `lib/features/channel/data/resource_api.dart` | ✅ 已修改 | 适配 `/api/file/*` 接口 |

---

## 一、概述

本文档详细描述了 Flutter 前端项目 (`netbar_ops_flutter`) 与 PHP 后端 (`op-toolbox`) 的对接方案。

### 1.1 项目信息

| 项目 | 技术栈 | 位置 |
|------|--------|------|
| Flutter前端 | Flutter 3.10+ / Riverpod / Dio | `netbar_ops_flutter/` |
| PHP后端 | Hyperf 3.1 / Swoole / JWT | `E:\luyao\A-Project\op-toolbox\op-toolbox` |

### 1.2 核心差异总结

| 差异项 | Flutter前端设计 | 后端实际实现 |
|--------|----------------|--------------|
| API前缀 | `/api/v1` | `/api` |
| 响应格式 | 直接返回数据对象 | `{code, message, data}` 包装 |
| 认证路径 | `/auth/*` | `/api/passport/*` |
| 网吧路径 | `/netbars` | `/api/merchant` |
| 用户路径 | `/users` | `/api/user` |
| 分组路径 | `/groups` | `/api/group` |
| 文件路径 | `/resources` | `/api/file/*` |

---

## 二、响应格式适配

### 2.1 后端统一响应格式

后端所有API返回格式为：
```json
{
  "code": 0,        // 0=成功, 1=失败
  "message": "success",
  "data": { ... }   // 实际数据
}
```

### 2.2 Flutter ApiClient改造

**文件位置**: `lib/core/network/api_client.dart`

**改造方案**:

```dart
// 在响应拦截器中解包data
_dio.interceptors.add(
  InterceptorsWrapper(
    onResponse: (response, handler) {
      // 后端返回 {code, message, data} 格式
      if (response.data is Map<String, dynamic>) {
        final map = response.data as Map<String, dynamic>;
        final code = map['code'];
        final message = map['message'];
        final data = map['data'];

        if (code == 0) {
          // 成功时，将response.data替换为实际data
          response.data = data;
          handler.next(response);
        } else {
          // 失败时抛出ApiError
          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: ApiError(code: code, message: message ?? '请求失败', raw: map),
            ),
          );
        }
      } else {
        handler.next(response);
      }
    },
  ),
);
```

---

## 三、API路径映射与改造

### 3.1 认证模块 (AuthApi)

**文件位置**: `lib/features/auth/data/auth_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 预登录 | `/auth/login` | `/api/passport/login` | POST |
| 获取Token | (新增) | `/api/passport/token?pwd=xxx` | GET |
| 登出 | `/auth/logout` | `/api/passport/logout` | POST |
| 获取当前用户 | `/auth/me` | `/api/passport/profile` | GET |
| 刷新Token | (新增) | `/api/passport/refresh` | POST |
| 二维码登录 | `/auth/qr/create` | `/api/passport/login/qr` | GET |
| 检查二维码状态 | `/auth/qr/status/$id` | `/api/passport/token?pwd=$id` | GET |

**响应数据映射**:

```dart
// 后端预登录响应
{
  "pwd": "随机口令",
  "qrCode": "base64二维码图片"
}

// 后端获取Token响应
{
  "access_token": "JWT令牌",
  "token_type": "Bearer",
  "create_in": 1234567890,
  "expire_in": 3600
}

// 后端profile响应
{
  "user": {
    "id": 1,
    "group_id": 0,
    "nickname": "管理员",
    "username": "admin",
    "is_manager": true,
    "is_enable": true,
    "phone_number": "...",
    "roles": [{"id": 1, "name": "角色名"}],
    "created_at": "..."
  }
}
```

**Flutter User模型改造**:

```dart
class User {
  final int id;
  final String username;
  final String nickname;     // 后端字段名
  final int? groupId;
  final bool isManager;       // 后端字段名
  final bool isEnable;
  final String? phoneNumber;
  final List<Role>? roles;
  final String? createdAt;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? json['username'] ?? '',
      groupId: json['group_id'],
      isManager: json['is_manager'] == true || json['is_manager'] == 1,
      isEnable: json['is_enable'] == true || json['is_enable'] == 1,
      phoneNumber: json['phone_number'],
      roles: (json['roles'] as List?)?.map((e) => Role.fromJson(e)).toList(),
      createdAt: json['created_at'],
    );
  }
}
```

### 3.2 网吧/商户模块 (NetbarApi)

**文件位置**: `lib/features/netbar/data/netbar_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取列表 | `/netbars` | `/api/merchant` | GET |
| 创建 | `/netbars` | `/api/merchant` | POST |
| 更新 | `/netbars/$id` | `/api/merchant/$id` | PUT/POST |
| 删除 | `/netbars/$id` | `/api/merchant/$id` | DELETE |
| 详情 | `/netbars/$id` | `/api/merchant/$id` | GET |
| 设置密码 | (新增) | `/api/merchant/setPwd/$id` | POST |
| 下载配置 | (新增) | `/api/merchant/down/$id` | GET |
| 清空密码 | (新增) | `/api/merchant/clearAllPwd` | POST |

**后端返回数据结构**:

```dart
// 商户列表响应
{
  "merchants": [...],
  "groups": [...],
  "summary": {"online_count": 10, "offline_count": 5},
  "group": {...}
}

// 单个商户数据
{
  "id": 1,
  "name": "网吧名称",
  "token": "登录令牌",
  "terminal_count": 100,
  "terminal_avg": 50,
  "is_online": true,
  "subdomain": "xxx",
  "subdomain_full": "xxx.domain.com",
  "groups": [{"id": 1, "name": "分组名"}],
  "users": [{"id": 1, "nickname": "管理员"}],
  "created_at": "..."
}
```

**Flutter Netbar模型改造**:

```dart
class Netbar {
  final int id;
  final String name;
  final String token;           // 后端: token
  final int terminalCount;      // 后端: terminal_count
  final int terminalAvg;        // 后端: terminal_avg
  final bool isOnline;          // 后端: is_online
  final String? subdomain;
  final String? subdomainFull;
  final List<Group>? groups;
  final List<User>? users;
  final String? createdAt;

  factory Netbar.fromJson(Map<String, dynamic> json) {
    return Netbar(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      token: json['token'] ?? '',
      terminalCount: json['terminal_count'] ?? 0,
      terminalAvg: json['terminal_avg'] ?? 0,
      isOnline: json['is_online'] == true || json['is_online'] == 1,
      subdomain: json['subdomain'],
      subdomainFull: json['subdomain_full'],
      groups: (json['groups'] as List?)?.map((e) => Group.fromJson(e)).toList(),
      users: (json['users'] as List?)?.map((e) => User.fromJson(e)).toList(),
      createdAt: json['created_at'],
    );
  }
}
```

### 3.3 仪表盘模块 (DashboardApi)

**文件位置**: `lib/features/dashboard/data/dashboard_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取统计 | `/dashboard` | `/api/home` | GET |
| 获取趋势 | `/dashboard/trend` | `/api/home` (同上) | GET |

**后端返回数据结构**:

```dart
{
  "ma": [{
    "merchant_total": 10,      // 网吧总数
    "merchant_offline": 2,     // 离线网吧数
    "terminal_total": 1000,    // 终端总数
    "terminal_7days": 500      // 近7日运行终端数
  }],
  "ma30days": [...],           // 近30天趋势
  "ma12months": [...]          // 近12个月趋势
}
```

**Flutter DashboardStats模型改造**:

```dart
class DashboardStats {
  final int totalNetbars;      // ma[0].merchant_total
  final int offlineNetbars;    // ma[0].merchant_offline
  final int totalTerminals;    // ma[0].terminal_total
  final int recentTerminals;   // ma[0].terminal_7days

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final ma = (json['ma'] as List?)?.firstOrNull as Map<String, dynamic>? ?? {};
    return DashboardStats(
      totalNetbars: ma['merchant_total'] ?? 0,
      offlineNetbars: ma['merchant_offline'] ?? 0,
      totalTerminals: ma['terminal_total'] ?? 0,
      recentTerminals: ma['terminal_7days'] ?? 0,
    );
  }
}
```

### 3.4 用户管理模块 (UserApi)

**文件位置**: `lib/features/user/data/user_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取列表 | `/users` | `/api/user` | GET |
| 创建 | `/users` | `/api/user` | POST |
| 更新 | `/users/$id` | `/api/user/$id` | PUT/POST |
| 删除 | `/users/$id` | `/api/user/$id` | DELETE |
| 详情 | `/users/$id` | `/api/user/$id` | GET |
| 绑定小程序 | (新增) | `/api/user/bindAccount` | POST |
| 解绑小程序 | (新增) | `/api/user/unbindAccount` | POST |
| 双因素认证获取密钥 | (新增) | `/api/user/twoFactorAuth/$id` | GET |
| 双因素认证绑定 | (新增) | `/api/user/twoFactorAuthCheck/$id` | POST |
| 修改Token有效期 | (新增) | `/api/user/refreshTtl/$id` | POST |

**后端用户数据结构**:

```dart
{
  "id": 1,
  "group_id": 0,
  "nickname": "管理员",
  "username": "admin",
  "is_manager": true,
  "is_enable": true,
  "phone_number": "138xxxx",
  "is_bind_wx": true,
  "is_bind_2fa": false,
  "token_refresh_ttl": 3600,
  "roles": [...],
  "created_at": "..."
}
```

### 3.5 分组管理模块 (GroupApi)

**文件位置**: `lib/features/netbar/data/group_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取列表 | `/groups` 或 `/netbars/$id/groups` | `/api/group` | GET |
| 创建 | `/groups` | `/api/group` | POST |
| 更新 | `/groups/$id` | `/api/group/$id` | PUT/POST |
| 删除 | `/groups/$id` | `/api/group/$id` | DELETE |
| 详情 | `/groups/$id` | `/api/group/$id` | GET |
| 设置密码 | (新增) | `/api/group/setPwd/$id` | POST |

**后端分组数据结构**:

```dart
{
  "id": 1,
  "name": "分组名称",
  "server_pwd": "密码",
  "users": [...],
  "districts": [...]
}
```

### 3.6 文件/资源管理模块 (ChannelApi / ResourceApi)

**文件位置**: `lib/features/channel/data/channel_api.dart`, `lib/features/channel/data/resource_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取文件列表 | `/resources` | `/api/file/view` | GET |
| 上传文件 | `/resources/upload` | `/api/file/upload` | POST |
| 秒传文件 | (新增) | `/api/file/instant` | POST |
| 删除文件 | `/resources/$id` | `/api/file/destroy` | POST |
| 重命名文件 | (新增) | `/api/file/rename` | POST |
| 隐藏文件 | (新增) | `/api/file/hide` | POST |
| 取消隐藏 | (新增) | `/api/file/unhide` | POST |
| 下载文件 | (新增) | `/api/file/down` | GET |
| 文件属性 | (新增) | `/api/file/attribute` | GET |
| 解压文件 | (新增) | `/api/file/extract` | POST |
| 共享文件 | (新增) | `/api/file/share` | POST |
| 取消共享 | (新增) | `/api/file/unshare` | POST |
| 接收共享 | (新增) | `/api/file/receive` | POST |
| 公共文件列表 | (新增) | `/api/file/shared` | GET |

**后端文件数据结构**:

```dart
{
  "id": 1,
  "user_id": 1,
  "group_id": 0,
  "file_id": 123,
  "parent_id": 0,
  "name": "文件名.exe",
  "is_folder": false,
  "is_share": false,
  "is_hide": false,
  "full_path": "/路径/文件名.exe",
  "file": {
    "id": 123,
    "size": 1024,
    "extension": "exe",
    "path": "/storage/..."
  },
  "user": {"id": 1, "nickname": "上传者"},
  "created_at": "...",
  "updated_at": "..."
}
```

**Flutter ChannelFile模型改造**:

```dart
class ChannelFile {
  final int id;
  final int? userId;
  final int? groupId;
  final int? fileId;
  final int? parentId;
  final String name;
  final bool isFolder;
  final bool isShare;
  final bool isHide;
  final String? fullPath;
  final FileInfo? file;
  final User? user;
  final String? createdAt;
  final String? updatedAt;

  factory ChannelFile.fromJson(Map<String, dynamic> json) {
    return ChannelFile(
      id: json['id'] ?? 0,
      userId: json['user_id'],
      groupId: json['group_id'],
      fileId: json['file_id'],
      parentId: json['parent_id'],
      name: json['name'] ?? '',
      isFolder: json['is_folder'] == true || json['is_folder'] == 1,
      isShare: json['is_share'] == true || json['is_share'] == 1,
      isHide: json['is_hide'] == true || json['is_hide'] == 1,
      fullPath: json['full_path'],
      file: json['file'] != null ? FileInfo.fromJson(json['file']) : null,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }
}
```

### 3.7 启动项管理模块 (StartupApi)

**文件位置**: `lib/features/channel/data/startup_item_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取列表 | `/startup-items` | `/api/startup` | GET |
| 禁用启动项 | (新增) | `/api/startup/disable/$id` | POST |
| 启用启动项 | (新增) | `/api/startup/enable/$id` | POST |
| 删除启动项 | `/startup-items/$id` | `/api/startup/$id` | DELETE |

**后端启动项数据结构**:

```dart
{
  "id": 1,
  "group_file_id": 123,
  "merchant_id": 1,
  "enabled_at": "2024-01-01 00:00:00",
  "disabled_at": null,
  "merchant": {
    "id": 1,
    "name": "网吧名",
    "terminal_count": 100,
    "groups": [...]
  },
  "created_at": "...",
  "updated_at": "..."
}
```

### 3.8 操作日志模块 (LogApi)

**文件位置**: `lib/features/logs/data/log_api.dart`

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取列表 | `/logs` | `/api/operationLog` | GET |
| 添加日志 | (新增) | `/api/operationLog` | POST |

**后端日志数据结构**:

```dart
{
  "paginator": {
    "current_page": 1,
    "data": [
      {
        "id": 1,
        "user_id": 1,
        "event": "startup_enable",
        "description": "操作描述",
        "payload": {"field": "old => new"},
        "user": {"id": 1, "nickname": "操作者"},
        "created_at": "..."
      }
    ],
    "per_page": 20,
    "total": 100
  },
  "eventMap": {
    "startup_enable": "启用启动项",
    "startup_disable": "禁用启动项",
    ...
  }
}
```

### 3.9 角色管理模块 (RoleApi)

| 功能 | Flutter当前路径 | 后端实际路径 | 请求方法 |
|------|----------------|--------------|----------|
| 获取角色列表 | (新增) | `/api/role` | GET |

---

## 四、后端缺失接口清单

根据Flutter前端设计，以下接口在后端不存在或需要新增：

### 4.1 终端监控相关 (后端完全缺失)

Flutter前端设计了完整的终端监控功能，但后端缺少对应接口：

| 功能 | Flutter期望路径 | 状态 |
|------|----------------|------|
| 获取终端列表 | `/terminals` | ❌ 缺失 |
| 获取终端详情 | `/terminals/$id` | ❌ 缺失 |
| 远程操作(重启/关机等) | `/terminals/$id/remote` | ❌ 缺失 |
| 获取终端心跳 | `/terminals/$id/heartbeat` | ❌ 缺失 |
| 获取进程列表 | `/terminals/$id/processes` | ❌ 缺失 |
| 结束进程 | `/terminals/$id/processes/$pid` | ❌ 缺失 |
| 获取文件列表 | `/terminals/$id/files` | ❌ 缺失 |
| 获取日志 | `/terminals/$id/logs` | ❌ 缺失 |
| 获取网络信息 | `/terminals/$id/network` | ❌ 缺失 |
| 获取硬件信息 | `/terminals/$id/hardware` | ❌ 缺失 |

**说明**: 后端有 `MachineController` 但功能有限，需要大幅扩展或实现新的终端监控接口。

### 4.2 桌面管理相关 (后端部分实现)

| 功能 | Flutter期望路径 | 后端路径 | 状态 |
|------|----------------|----------|------|
| 获取布局列表 | `/desktop-layouts` | `/api/layout` | ✅ 存在 |
| 创建布局 | `/desktop-layouts` | `/api/layout` | ✅ 存在 |
| 更新布局 | `/desktop-layouts/$id` | `/api/layout/$id` | ✅ 存在 |
| 删除布局 | `/desktop-layouts/$id` | `/api/layout/$id` | ✅ 存在 |
| 获取图标列表 | `/desktop-icons` | `/api/icon` | ✅ 存在 |
| 上传图标 | `/desktop-icons/upload` | `/api/icon` | ✅ 存在 |

### 4.3 通道管理 (后端部分实现)

| 功能 | Flutter期望路径 | 后端路径 | 状态 |
|------|----------------|----------|------|
| 通道/启动项列表 | `/channels` | `/api/channel` | ✅ 存在 |
| 创建启动项 | `/startup-items` | 需通过文件系统实现 | ⚠️ 需适配 |
| 更新启动项 | `/startup-items/$id` | 需通过文件系统实现 | ⚠️ 需适配 |

### 4.4 其他缺失接口

| 功能 | Flutter期望路径 | 状态 |
|------|----------------|------|
| 网络诊断 | `/dashboard/network-diagnose` | ❌ 缺失 |
| 全部重启 | `/dashboard/restart-all` | ❌ 缺失 |
| 用户分组管理 | `/netbars/$id/groups` | ⚠️ 需新增 |

---

## 五、Flutter代码改造清单

### 5.1 需要修改的文件列表

| 文件路径 | 改动类型 | 改动内容 |
|----------|----------|----------|
| `lib/core/config/app_config.dart` | 修改 | 更新baseUrl为`/api` |
| `lib/core/network/api_client.dart` | 修改 | 添加响应解包逻辑 |
| `lib/features/auth/data/auth_api.dart` | 重写 | 适配后端认证接口 |
| `lib/features/netbar/data/netbar_api.dart` | 重写 | 适配后端商户接口 |
| `lib/features/dashboard/data/dashboard_api.dart` | 重写 | 适配后端首页接口 |
| `lib/features/user/data/user_api.dart` | 重写 | 适配后端用户接口 |
| `lib/features/netbar/data/group_api.dart` | 重写 | 适配后端分组接口 |
| `lib/features/channel/data/channel_api.dart` | 重写 | 适配后端文件接口 |
| `lib/features/channel/data/startup_item_api.dart` | 重写 | 适配后端启动项接口 |
| `lib/features/logs/data/log_api.dart` | 重写 | 适配后端日志接口 |
| `lib/features/monitor/data/terminal_api.dart` | 保留Mock | 后端缺失，暂用Mock |
| `lib/features/desktop/data/desktop_api.dart` | 重写 | 适配后端布局/图标接口 |

### 5.2 需要新增的文件

| 文件路径 | 说明 |
|----------|------|
| `lib/features/auth/data/role_api.dart` | 角色管理API |
| `lib/features/netbar/data/district_api.dart` | 区域管理API |
| `lib/features/channel/data/file_share_api.dart` | 文件共享API |

### 5.3 数据模型改造

需要根据后端返回的实际字段名称调整所有Model类的fromJson方法，主要包括：

1. **字段名映射** (snake_case → camelCase)
2. **布尔值处理** (后端返回0/1，前端期望bool)
3. **嵌套对象处理** (后端返回关联数据的处理)

---

## 六、改造优先级建议

### 第一阶段：核心功能 (最高优先级)

1. `ApiClient` 响应格式适配
2. `AuthApi` 认证流程对接
3. `NetbarApi` 商户管理对接
4. `GroupApi` 分组管理对接

### 第二阶段：主要功能

5. `UserApi` 用户管理对接
6. `DashboardApi` 首页统计对接
7. `ChannelApi` 文件管理对接
8. `StartupItemApi` 启动项对接

### 第三阶段：辅助功能

9. `LogApi` 操作日志对接
10. `DesktopApi` 桌面管理对接

### 第四阶段：待后端实现

11. 终端监控功能 (需后端新增接口)
12. 网络诊断功能 (需后端新增接口)

---

## 七、测试建议

### 7.1 单元测试

为每个改造后的API类编写单元测试，验证：
- 请求路径正确
- 请求参数正确
- 响应解析正确

### 7.2 集成测试

使用真实后端服务测试完整流程：
1. 登录流程
2. 网吧列表获取
3. 文件上传下载
4. 启动项管理

---

## 八、附录：后端接口完整清单

基于接口文档整理的后端所有可用接口：

### 认证相关
- `POST /api/passport/login` - 预登录
- `GET /api/passport/login/qr` - 二维码登录
- `GET /api/passport/token` - 获取令牌
- `GET /api/passport/profile` - 获取/编辑资料
- `POST /api/passport/profile` - 编辑资料
- `POST /api/passport/refresh` - 刷新令牌
- `POST /api/passport/logout` - 登出
- `POST /api/passport/merchant/login` - 商户登录
- `POST /api/passport/merchant/refresh` - 商户刷新令牌
- `POST /api/passport/merchant/logout` - 商户登出

### 用户管理
- `GET /api/user` - 用户列表
- `POST /api/user` - 创建用户
- `GET /api/user/{id}` - 用户详情
- `POST /api/user/{id}` - 编辑用户
- `DELETE /api/user/{id}` - 删除用户
- `GET /api/user/twoFactorAuth/{id}` - 双因素认证获取密钥
- `POST /api/user/twoFactorAuthCheck/{id}` - 双因素认证绑定
- `POST /api/user/bindAccount` - 绑定小程序
- `POST /api/user/unbindAccount` - 解绑小程序
- `POST /api/user/refreshTtl/{id}` - 编辑Token有效期

### 分组管理
- `GET /api/group` - 分组列表
- `POST /api/group` - 创建分组
- `GET /api/group/{id}` - 分组详情
- `POST /api/group/{id}` - 编辑分组
- `DELETE /api/group/{id}` - 删除分组
- `POST /api/group/setPwd/{id}` - 设置分组密码

### 商户管理
- `GET /api/merchant` - 商户列表
- `POST /api/merchant` - 创建商户
- `GET /api/merchant/{id}` - 商户详情
- `POST /api/merchant/{id}` - 编辑商户
- `DELETE /api/merchant/{id}` - 删除商户
- `POST /api/merchant/setPwd/{id}` - 设置商户密码
- `POST /api/merchant/clearAllPwd` - 清空所有商户密码
- `GET /api/merchant/down/{id}` - 下载商户配置

### 首页统计
- `GET /api/home` - 首页数据

### 文件管理
- `GET /api/file/view` - 文件列表
- `POST /api/file/upload` - 上传文件
- `POST /api/file/instant` - 秒传文件
- `POST /api/file/rename` - 重命名
- `POST /api/file/destroy` - 删除文件
- `GET /api/file/attribute` - 文件属性
- `POST /api/file/hide` - 隐藏文件
- `POST /api/file/unhide` - 取消隐藏
- `GET /api/file/down` - 下载文件
- `POST /api/file/extract` - 解压文件
- `GET /api/file/shared` - 公共文件列表
- `POST /api/file/share` - 共享文件
- `POST /api/file/unshare` - 取消共享
- `POST /api/file/receive` - 接收共享文件
- `GET /api/file/shareAttr` - 共享文件属性
- `GET /api/file/icon` - 文件图标

### 启动项管理
- `GET /api/startup` - 启动项列表
- `POST /api/startup/disable/{id}` - 禁用启动项
- `POST /api/startup/enable/{id}` - 启用启动项
- `DELETE /api/startup/{id}` - 删除启动项

### 操作日志
- `GET /api/operationLog` - 日志列表
- `POST /api/operationLog` - 添加日志

### 角色管理
- `GET /api/role` - 角色列表

### 区域管理
- `GET /api/district/filter` - 区域筛选

### 配置管理
- `POST /api/config/global/frp` - FRP配置

### 布局管理
- `GET /api/layout` - 布局列表
- `POST /api/layout` - 创建布局
- `GET /api/layout/{id}` - 布局详情
- `POST /api/layout/{id}` - 编辑布局
- `DELETE /api/layout/{id}` - 删除布局

### 图标管理
- `GET /api/icon` - 图标列表
- `POST /api/icon` - 创建图标
- `DELETE /api/icon/{id}` - 删除图标
