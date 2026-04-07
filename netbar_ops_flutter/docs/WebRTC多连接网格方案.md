# WebRTC 多连接网格方案

## 1. 背景与问题

### 客户需求

- 同时运行 **10+** 个 WebRTC 远程桌面连接
- 同时**显示**所有远程画面（监控墙模式）
- 同一时刻只**操控**一个远程桌面

### 当前架构

```
主窗口 (Flutter Engine #0)
├── NetbarOpsApp (主应用)
└── TerminalWindowBridge.openTerminalWindow()
    ├── 子窗口 1 (Flutter Engine #1) → TerminalDetailPage → WebRTC RemoteScreen
    ├── 子窗口 2 (Flutter Engine #2) → TerminalDetailPage → WebRTC RemoteScreen
    ├── ...
    └── 子窗口 N (Flutter Engine #N) → WebRTC RemoteScreen
```

使用 `desktop_multi_window` 包，每个终端详情页在独立子窗口中运行，每个子窗口对应一个独立的 Flutter 引擎。

### 为什么当前架构无法支持 10 个窗口

**根因：Windows 消息队列溢出（错误码 1816 = ERROR_NOT_ENOUGH_QUOTA）**

- `desktop_multi_window` 的所有子窗口运行在**同一个进程**中
- Windows 线程消息队列硬上限为 **10,000 条**
- 每个 Flutter 引擎通过 `PostMessage` 向主线程投递：
  - WebRTC 视频帧纹理更新（每帧一条，30fps × N 路）
  - Platform channel 回调
  - Timer 调度消息
  - `setState` / `scheduleFrame` 渲染消息
- 4 个窗口即触发溢出，10 个窗口完全不可行
- **CPU 和内存充足时仍然崩溃**，因为瓶颈是消息队列而非硬件资源

## 2. 目标架构

### 总体思路

**单窗口 + 单引擎 + 网格布局**，消除多引擎消息队列竞争。

```
主窗口 (Flutter Engine #0)
├── NetbarOpsApp
│   ├── 监控页 (monitor_page)
│   └── 远程网格页 (RemoteGridPage)  ← 新增
│       ├── 缩略图: RTCVideoView × N (小尺寸，所有连接)
│       └── 焦点区: RTCVideoView × 1 (大尺寸，可交互)
│
│   内部管理:
│   ├── WebRTCSession #1 (连接+渲染器+服务实例)
│   ├── WebRTCSession #2
│   ├── ...
│   └── WebRTCSession #N
```

### 布局示意

```
┌──────────────────────────────────────────────────────────┐
│  网吧名 - 分组名                    [最小化] [全屏] [关闭] │
├──────────┬──────────┬──────────┬─────────────────────────┤
│  1号机   │  2号机   │  3号机   │                         │
│  (缩略)  │  (缩略)  │  (缩略)  │                         │
├──────────┼──────────┼──────────┤     5号机 (焦点)         │
│  4号机   │  6号机   │  7号机   │     ┌─────────────────┐ │
│  (缩略)  │  (缩略)  │  (缩略)  │     │                 │ │
├──────────┼──────────┼──────────┤     │  全尺寸视频流    │ │
│  8号机   │  9号机   │  10号机  │     │  可交互操控      │ │
│  (缩略)  │  (缩略)  │  (缩略)  │     │                 │ │
│          │          │          │     └─────────────────┘ │
└──────────┴──────────┴──────────┴─────────────────────────┘
```

- **左侧网格**：所有连接的缩略图，实时显示视频画面
- **右侧焦点区**：当前选中的连接，大尺寸，可交互（鼠标、键盘）
- **点击缩略图**：切换焦点到该连接
- **双击缩略图**：全屏显示该连接

## 3. webrtc_remote 库改造

### 3.1 核心问题：全局单例

当前 `webrtc_remote` 库的所有服务都是**全局单例**，无法在同一引擎内创建多个连接：

| 服务类 | 文件 | 单例模式 |
|--------|------|----------|
| `WebRTCService` | `services/webrtc_service.dart` | `static final _instance` |
| `SignalingService` | `services/signaling_service.dart` | `static final _instance` |
| `InputService` | `services/input_service.dart` | `static final _instance` |
| `StatsService` | `services/stats_service.dart` | `static final _instance` |
| `EventBus` | `services/event_bus.dart` | `static final _instance` |
| `NetworkAdaptiveService` | `services/network_adaptive_service.dart` | `static final _instance` |
| `FileTransferService` | `services/file_transfer_service.dart` | `static final _instance` |
| `IceRacingService` | `services/ice_racing_service.dart` | `static final _instance` |
| `ClipboardDownloadService` | `services/clipboard_download_service.dart` | `static final _instance` |
| `ClipboardReaderService` | `services/clipboard_reader_service.dart` | `static final _instance` |
| `VirtualClipboardService` | `services/virtual_clipboard_service.dart` | `static final _instance` |
| `P2PAssistService` | `services/p2p_assist_service.dart` | `static final _instance` |

### 3.2 改造方案：引入 Session 概念

#### 3.2.1 新增 `WebRTCSession` 类

```dart
/// 一个 WebRTC 远程连接会话，包含该连接所需的全部服务实例
class WebRTCSession {
  final String sessionId;
  final ServerConfig server;
  
  late final EventBus eventBus;
  late final SignalingService signalingService;
  late final WebRTCService webrtcService;
  late final InputService inputService;
  late final StatsService statsService;
  late final NetworkAdaptiveService networkAdaptiveService;
  late final FileTransferService fileTransferService;
  // ... 其他服务

  WebRTCSession({required this.sessionId, required this.server}) {
    // 每个 session 创建独立的服务实例（非单例）
    eventBus = EventBus.create();
    signalingService = SignalingService.create(eventBus: eventBus);
    webrtcService = WebRTCService.create(
      eventBus: eventBus,
      signalingService: signalingService,
    );
    // ... 依次初始化，通过构造函数注入依赖
  }

  Future<void> connect() async { ... }
  Future<void> disconnect() async { ... }
  void dispose() { ... }
}
```

#### 3.2.2 服务类改造：单例 → 可实例化

每个服务类需要同时支持两种使用方式（保持向后兼容）：

```dart
class WebRTCService {
  // 保留原有单例（向后兼容，独立应用场景）
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  // 新增：创建独立实例（多连接场景）
  WebRTCService.create({
    required EventBus eventBus,
    required SignalingService signalingService,
  }) : _eventBus = eventBus,
       _signalingService = signalingService;

  // 原来直接调用 EventBus() 的地方改为使用 _eventBus 字段
  late final EventBus _eventBus;
  late final SignalingService _signalingService;
}
```

**改造原则**：
- 所有服务类新增 `.create()` 命名构造函数，接受依赖注入
- 内部不再直接调用 `SomeService()` 获取单例，改为使用注入的实例引用
- 原有单例 `factory` 构造函数保留不动，确保向后兼容
- `EventBus` 是最底层依赖，每个 session 一个独立 EventBus，事件隔离

#### 3.2.3 RemoteScreen 改造

```dart
class RemoteScreen extends StatefulWidget {
  final ServerConfig server;
  final VoidCallback onDisconnect;
  
  // 新增参数
  final bool interactive;        // 是否接收输入（焦点模式 vs 预览模式）
  final WebRTCSession? session;  // 外部传入 session（网格模式）
  
  const RemoteScreen({
    required this.server,
    required this.onDisconnect,
    this.interactive = true,
    this.session,                 // null 时内部自建（兼容旧逻辑）
  });
}
```

- `interactive: true` — 焦点模式：启用键盘钩子、鼠标输入、手势识别、全功能
- `interactive: false` — 预览模式：只渲染 `RTCVideoView`，禁用 `InputService`、`KeyboardHookService`、手势识别等
- `session` — 从外部注入已建立的 session，使得焦点切换时不需要重新连接

### 3.3 改造优先级

按依赖关系从底层到上层改造：

```
第 1 层（无依赖）: EventBus
第 2 层: SignalingService (依赖 EventBus)
第 3 层: WebRTCService (依赖 EventBus, SignalingService)
第 4 层: InputService, StatsService, NetworkAdaptiveService (依赖 EventBus, WebRTCService)
第 5 层: FileTransferService, IceRacingService 等 (依赖上层)
第 6 层: RemoteScreen (组装所有服务)
```

### 3.4 非焦点连接的资源优化

为降低 10 路连接的总负载，非焦点连接应减少资源消耗：

| 服务 | 焦点连接 | 非焦点连接 |
|------|---------|-----------|
| 视频渲染 | 全帧率全尺寸 | 缩小尺寸渲染（自然降低 GPU 负载）|
| `InputService` | 启用 | **禁用** |
| `KeyboardHookService` | 启用 | **禁用** |
| `StatsService` | 1s 轮询 | **5s 或暂停** |
| `NetworkAdaptiveService` | 1s 检查 | **暂停** |
| `FileTransferService` | 按需 | **暂停** |
| WebRTC 连接 | 保持 | 保持 |
| WebSocket 信令 | 保持 | 保持 |

## 4. NetBar-Ops 主项目改造

### 4.1 新增文件

```
lib/features/monitor/presentation/
├── remote_grid_page.dart          # 远程网格页面（核心新增）
├── widgets/
│   ├── remote_thumbnail.dart      # 单个远程连接缩略图组件
│   └── remote_focus_panel.dart    # 焦点区域组件（大尺寸可交互）

lib/features/monitor/data/
├── remote_session_manager.dart    # 管理多个 WebRTCSession 的生命周期

lib/shared/providers/
├── remote_grid_provider.dart      # Riverpod 状态：活跃连接列表、焦点 ID
```

### 4.2 RemoteGridPage 设计

```dart
class RemoteGridPage extends ConsumerStatefulWidget {
  // 可选：初始连接列表
  final List<RemoteTarget>? initialTargets;
}

class _RemoteGridPageState extends ConsumerState<RemoteGridPage> {
  final RemoteSessionManager _sessionManager = RemoteSessionManager();
  String? _focusedSessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 标题栏（常驻）
          _buildTitleBar(),
          // 主体
          Expanded(
            child: Row(
              children: [
                // 左侧：缩略图网格
                SizedBox(
                  width: 300, // 或自适应
                  child: _buildThumbnailGrid(),
                ),
                // 右侧：焦点区
                Expanded(
                  child: _buildFocusPanel(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### 4.3 RemoteSessionManager 设计

```dart
class RemoteSessionManager {
  final Map<String, WebRTCSession> _sessions = {};
  
  /// 添加并连接一个远程终端
  Future<WebRTCSession> addSession({
    required String sessionId,
    required ServerConfig server,
  }) async {
    if (_sessions.containsKey(sessionId)) {
      return _sessions[sessionId]!;
    }
    final session = WebRTCSession(sessionId: sessionId, server: server);
    await session.connect();
    _sessions[sessionId] = session;
    return session;
  }
  
  /// 断开并移除一个会话
  Future<void> removeSession(String sessionId) async {
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await session.disconnect();
      session.dispose();
    }
  }
  
  /// 切换焦点（启用/禁用输入服务）
  void setFocus(String? sessionId) {
    for (final entry in _sessions.entries) {
      entry.value.setInteractive(entry.key == sessionId);
    }
  }
  
  /// 销毁全部
  Future<void> disposeAll() async {
    for (final session in _sessions.values) {
      await session.disconnect();
      session.dispose();
    }
    _sessions.clear();
  }
}
```

### 4.4 入口改造

当前流程：
```
monitor_page → 点击终端 → openTerminalWindow() → 新窗口 → TerminalDetailPage → WebRTC
```

新流程（桌面端多连接场景）：
```
monitor_page → 点击终端"远程"按钮 → RemoteGridPage.addSession() → 网格中新增一路
```

- 第一次点击"远程"时打开 `RemoteGridPage`（或在新窗口中打开一个）
- 后续点击其他终端的"远程"时，向已有的 `RemoteGridPage` 添加连接
- 单窗口即可容纳所有远程连接

### 4.5 与现有 TerminalDetailPage 的关系

- `TerminalDetailPage` 保留不动，仍用于单终端详情查看
- `RemoteGridPage` 是新增页面，专门用于多路远程桌面管理
- 两者可以共存：单路远程仍可走旧路径，多路远程走网格页面
- 后续可根据需要合并或迁移

## 5. 实施计划

### 阶段 1：webrtc_remote 库多实例改造（核心基础）

**目标**：所有服务类支持 `.create()` 非单例构造，新增 `WebRTCSession` 容器。

**步骤**：
1. `EventBus` 添加 `.create()` 构造函数
2. `SignalingService` 改造：注入 `EventBus`
3. `WebRTCService` 改造：注入 `EventBus`、`SignalingService`
4. `InputService`、`StatsService`、`NetworkAdaptiveService` 改造
5. `FileTransferService`、`IceRacingService`、`P2PAssistService` 改造
6. 剩余服务改造
7. 新建 `WebRTCSession` 类，组装所有服务
8. 验证：同一进程内创建 2 个 `WebRTCSession`，各自独立连接、独立断开

**验收标准**：
- 原有单例模式不受影响（独立应用仍正常）
- 两个 Session 可同时连接不同终端，事件互不干扰

### 阶段 2：RemoteScreen 支持 interactive 模式

**目标**：`RemoteScreen` 支持仅渲染模式（预览）和完全交互模式。

**步骤**：
1. `RemoteScreen` 新增 `interactive` 和 `session` 参数
2. `interactive: false` 时不初始化 `InputService`、`KeyboardHookService`
3. `interactive: false` 时不注册键盘/鼠标事件处理器
4. 运行时支持动态切换 `interactive` 状态（焦点切换）
5. 验证：一个 `RemoteScreen(interactive: true)` + 一个 `RemoteScreen(interactive: false)` 同屏显示

**验收标准**：
- 预览模式只显示视频，不拦截键盘/鼠标
- 切换焦点后输入立即跟随

### 阶段 3：NetBar-Ops 主项目集成

**目标**：新增 `RemoteGridPage`，实现网格布局 + 焦点切换。

**步骤**：
1. 新建 `RemoteSessionManager`
2. 新建 `remote_grid_provider.dart`（Riverpod 状态管理）
3. 新建 `RemoteGridPage` 页面
4. 新建 `RemoteThumbnail` 和 `RemoteFocusPanel` 组件
5. 改造 monitor_page 中的远程按钮入口
6. 标题栏集成（网吧名、分组、连接列表）
7. 全屏/最小化/关闭逻辑适配

**验收标准**：
- 同时连接 10 个终端，全部显示缩略图
- 点击切换焦点，输入正确跟随
- 无 `Failed to post message` 错误
- 程序不卡顿

### 阶段 4：优化与完善

**目标**：性能调优和 UX 完善。

**步骤**：
1. 非焦点连接降低 `StatsService` / `NetworkAdaptiveService` 轮询频率
2. 缩略图尺寸自适应（根据连接数量动态调整网格列数）
3. 连接断开/重连状态在缩略图上显示
4. 拖拽排序缩略图顺序
5. 右键菜单：断开、重新连接、移除
6. 全屏模式：双击缩略图进入单路全屏，ESC 退回网格

## 6. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 单引擎 10 路 RTCVideoView 渲染压力 | 可能帧率下降 | 缩略图尺寸小（如 240×135），GPU 纹理负载低；焦点区全尺寸 |
| 服务单例改多实例引入 bug | 事件串台、资源泄漏 | 每个 Session 独立 EventBus，事件天然隔离；dispose 时逐一释放 |
| 10 路 WebSocket 信令连接 | 网络连接数多 | WebSocket 本身轻量，10 路无压力 |
| 向后兼容性 | 独立应用模式可能受影响 | 保留原有单例构造函数，新增 `.create()` 不影响旧逻辑 |
| 键盘钩子冲突 | 多个 Session 抢占键盘钩子 | 只有焦点 Session 启用钩子，其余禁用 |

## 7. 参考信息

### 相关文件路径

```
# NetBar-Ops 主项目
lib/features/monitor/presentation/terminal_detail_page.dart    # 当前 WebRTC 入口
lib/features/monitor/presentation/monitor_page.dart            # 监控页面
lib/shared/services/terminal_window_bridge_desktop.dart         # 当前多窗口管理
lib/main.dart                                                   # 多窗口入口分支

# webrtc_remote 库
E:/luyao/flutter/PubCache/git/WebRtcGo-.../examples/FlutterUi/
├── lib/
│   ├── webrtc_remote.dart              # 库入口/导出
│   ├── screens/remote_screen.dart      # RemoteScreen 组件
│   ├── services/
│   │   ├── webrtc_service.dart         # WebRTC 连接管理（单例）
│   │   ├── signaling_service.dart      # WebSocket 信令（单例）
│   │   ├── input_service.dart          # 键鼠输入（单例）
│   │   ├── stats_service.dart          # 统计轮询（单例）
│   │   ├── event_bus.dart              # 事件总线（单例）
│   │   ├── network_adaptive_service.dart
│   │   ├── file_transfer_service.dart
│   │   ├── ice_racing_service.dart
│   │   ├── p2p_assist_service.dart
│   │   ├── keyboard_hook_service.dart
│   │   ├── gesture_handler.dart
│   │   ├── clipboard_download_service.dart
│   │   ├── clipboard_reader_service.dart
│   │   └── virtual_clipboard_service.dart
│   └── models/
│       ├── server_config.dart
│       ├── connection_state.dart
│       └── ...
```

### 技术依赖

- `flutter_webrtc` — WebRTC 底层实现
- `desktop_multi_window` — 当前多窗口方案（网格方案下可保留用于其他窗口，但远程桌面不再使用）
- `window_manager` — 窗口管理
- Flutter Windows embedder — 底层消息循环
