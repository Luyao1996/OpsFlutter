# webrtc_remote 远控崩溃根治方案 + 符号化实锤指南

> 交付对象：`webrtc_remote`(WebRtcGo) 组件开发者
> 适用版本：`ref=feature/optimization`（resolved-ref `c2ca5b3d7bd00b09d77185164e66d1e0efbf2280`）
> 改动范围：全部在 `webrtc_remote` 组件内（含其内置 `plugins/flutter_webrtc` fork 与 `examples/FlutterUi/lib/`）。主项目 `netbar_ops_flutter` 无需改动。
> 宿主 Flutter：framework revision `66dd93f9a27ffe2a9bfc8297506ce066ff51265f`（stable）
> 证据来源：现场 minidump `crash_20260527_221410.dmp` / `crash_20260528_222840.dmp` + webrtc 日志 + 源码审查（多 agent 交叉验证）

---

## 1. 问题摘要

网吧后台机的 Flutter Windows 客户端在**远程控制（WebRTC 投屏）退出 / 切换会话时频繁崩溃**。

- **崩溃签名**：`0xC0000005` 访问冲突、**READ 空地址 `0x0`（空指针解引用）**、故障指令 `flutter_windows.dll + 0x463E5`、崩溃在**主线程（platform/UI thread）消息泵**。两份 dump 字节级一致。
- **根因（一句话）**：`FlutterVideoRenderer` 没有生命周期屏障。`OnFrame()` 跑在 libwebrtc 解码线程，在 `videoRendererDispose` 期间/之后，仍无保护地调用 `registrar_->MarkTextureFrameAvailable(texture_id_)`；引擎随后在主线程派发这个**已被注销的纹理**，内部纹理表项为空 → 读空指针 → 崩溃。

---

## 2. 已确证事实（证据）

### 2.1 两份 dump 是同一引擎二进制的同一指令（可复现铁证）

| 项 | 27 日 dump | 28 日 dump |
|---|---|---|
| 异常码 | `0xC0000005` | `0xC0000005` |
| 操作 / 访问地址 | READ / `0x0` | READ / `0x0` |
| 故障 RIP | `flutter_windows.dll+0x463E5` | `flutter_windows.dll+0x463E5` |
| 崩溃线程 | 主线程消息泵（栈含 `flutter_windows.dll+0x6B849C`） | 同 |
| `flutter_windows.dll` TimeDateStamp | `0x6930ABAE` | `0x6930ABAE` |
| `flutter_windows.dll` SizeOfImage | `0x11C6000` | `0x11C6000` |
| PDB GUID+Age | `727032ECD3C64DF086F21CEBD1C22F97` + `1` | 同 |

> 同一引擎二进制 + 同一偏移 ⇒ 必是同一函数同一条指令；这解释了"为什么每次都崩在固定位置、可稳定复现"。

### 2.2 时间线（webrtc 日志，注意 grep 大日志须加 `-a`）

- **28 日（最干净）**：`22:25:03 exited_screen resume_heartbeat`（用户退出远控画面，心跳恢复 ⇒ 引擎仍存活）→ `peerConnectionClose` + **`videoRendererDispose textureId=1830078480`** + `dataChannelClose` → 静默 2~3 分钟 → 崩溃 → watchdog 重启。
- **27 日**：建立会话中探测 PC 走 `peerConnectionClose/Dispose` → 崩溃。
- ⇒ **两次崩溃都紧跟"WebRTC 纹理/连接销毁"动作**，且发生在引擎存活期间（不是关窗销毁引擎）。

### 2.3 判别性证据：事件路径有保护，唯独纹理路径裸奔

- 事件投递 `EventChannelProxyImpl::PostEvent`（`common/cpp/src/flutter_common.cc:116-128`）：用 `std::weak_ptr<EventSink>` + `weak_sink.lock()` 空判保护，且经插件自有 TaskRunner 的独立消息窗口派发（不落引擎主泵）。
- 纹理路径 `OnFrame`（`common/cpp/src/flutter_video_renderer.cc:81`）：`registrar_->MarkTextureFrameAvailable(texture_id_)` **无 disposed 判断、`registrar_` 是裸指针、`mutex_` 只护 `frame_`**，且 `MarkTextureFrameAvailable` 正是唯一落入引擎主线程消息泵的路径——与崩溃栈完全吻合。

### 2.4 已排除项

| 怀疑 | 结论 | 依据 |
|---|---|---|
| 第二种 native 崩溃 | 未发现 | 仅有的 2 个 dump 同签名 |
| 内存溢出 OOM | 误报 | "OoM/OOM" 全是 SDP 里 ICE 密码随机串 |
| 崩溃循环 | 无 | 秒级重启基本是升级安装（带 download/install 日志） |
| 自定义 `LoggingBinaryMessenger` | 无关 | 纯透传、不二次回复、不持引擎指针 |
| Dart `String not Uint8List` 异常 | 非致命 | 被 zone 捕获写入 `dart_crash`，不产生 `0xC0000005` |
| 子窗口引擎被销毁 | 非这两次主因 | 28 日 `resume_heartbeat` 证明引擎退出后仍存活数分钟 |

> 残留缺口（如实告知）：5-27 之前无 dump（minidump 似 1.1.9 才启用），早期若有别种崩溃无法取证；代码中还存在 2~3 条同源潜在崩溃路径（见 B 节）。

---

## 3. 根因详述

```
libwebrtc 解码线程: OnFrame(frame)
   -> registrar_->MarkTextureFrameAvailable(texture_id_)   // flutter_video_renderer.cc:81，无任何保护
                       |
主线程消息泵: 引擎按 texture_id 查纹理表 -> 该纹理已被 UnregisterTexture 注销 -> 表项为空 -> READ 0x0
                       |
              crash @ flutter_windows.dll+0x463E5
```
销毁侧 `VideoRendererDispose`（`flutter_video_renderer.cc:165-183`）只做 `SetVideoTrack(nullptr)`（切源，但不保证解码线程没有一帧正在 `OnFrame` 执行），随后异步 `UnregisterTexture(texture_id, [&, it]{ renderers_.erase(it); })`——制造了"纹理已注销/对象待释放，但解码线程仍可投帧"的竞争窗口。

---

## 4. 修改方案

### A. Native 主修（必做，直接消除崩溃）
文件：`plugins/flutter_webrtc/common/cpp/include/flutter_video_renderer.h` + `src/flutter_video_renderer.cc`

> 说明：代码块内注释一律英文（该项目 native 开启 `/WX`，中文注释会触发 C4819 编译失败）。

**A1. 头文件：新增 `disposed_` 标志与 `Shutdown()`**
```cpp
// flutter_video_renderer.h  (top)
#include <atomic>

// class FlutterVideoRenderer : public section
void Shutdown();                 // stop frame source + invalidate engine handles

// class FlutterVideoRenderer : private section
std::atomic<bool> disposed_{false};
```

**A2. `OnFrame` 加屏障（核心）—— `flutter_video_renderer.cc:47-82`**
```cpp
void FlutterVideoRenderer::OnFrame(scoped_refptr<RTCVideoFrame> frame) {
  std::lock_guard<std::mutex> lock(mutex_);                 // NEW: whole-function lock
  if (disposed_ || registrar_ == nullptr || !event_channel_) return;  // NEW: barrier
  // ... keep original first_frame / rotation / size blocks (event_channel_->Success) ...
  // remove the original standalone mutex_.lock()/unlock() at lines 78-80 (covered by lock_guard)
  frame_ = frame;
  registrar_->MarkTextureFrameAvailable(texture_id_);
}
```
> `MarkTextureFrameAvailable` 持锁调用不会回调进 `OnFrame`，无死锁；`CopyPixelBuffer` 本就持 `mutex_`，二者天然互斥。

**A3. `Shutdown()` + `VideoRendererDispose` 串行化 —— `flutter_video_renderer.cc:165-183`**
```cpp
void FlutterVideoRenderer::Shutdown() {
  SetVideoTrack(nullptr);                     // 1) detach from libwebrtc (RemoveRenderer)
  std::lock_guard<std::mutex> lock(mutex_);   // 2) serialize with any in-flight OnFrame
  disposed_ = true;
  registrar_ = nullptr;                       // 3) subsequent OnFrame returns early
  event_channel_.reset();
}

void FlutterVideoRendererManager::VideoRendererDispose(
    int64_t texture_id, std::unique_ptr<MethodResultProxy> result) {
  auto it = renderers_.find(texture_id);
  if (it != renderers_.end()) {
    it->second->Shutdown();                   // stop frames / set barrier BEFORE unregister
#if defined(_WINDOWS)
    base_->textures_->UnregisterTexture(texture_id,
        [this, texture_id] {                  // A4: capture by value + re-find on main thread
          auto it2 = renderers_.find(texture_id);
          if (it2 != renderers_.end()) renderers_.erase(it2);
        });
#else
    base_->textures_->UnregisterTexture(texture_id);
    renderers_.erase(it);
#endif
    result->Success();
    return;
  }
  result->Error("VideoRendererDisposeFailed",
                "VideoRendererDispose() texture not found!");
}
```
> **A4 已含在上面**：原 `[&, it]` 同时按引用捕获 manager `this` 和**可能失效的 map 迭代器**；改为按值捕获 `texture_id`、回调内重新 `find` 再 `erase`，消除悬垂迭代器/引用。

**A5. `CopyPixelBuffer` 防御性早退 —— `flutter_video_renderer.cc:21-45`**
```cpp
const FlutterDesktopPixelBuffer* FlutterVideoRenderer::CopyPixelBuffer(
    size_t width, size_t height) const {
  mutex_.lock();
  if (disposed_) { mutex_.unlock(); return nullptr; }   // NEW
  // ... keep original body ...
}
```

### B. Native 加固（同源潜在崩溃路径，建议一并修）

**B1+B2. DataChannel observer —— `flutter_data_channel.cc:17` / `:97-106`**
```cpp
// :17  empty destructor -> unregister from libwebrtc before teardown
FlutterRTCDataChannelObserver::~FlutterRTCDataChannelObserver() {
  if (data_channel_) data_channel_->UnregisterObserver();   // interface: rtc_data_channel.h:94
}
```
> `DataChannelClose`（:97-106）的 `erase` 用 `base_->lock()/unlock()` 包裹（与 `CreateDataChannel:60-62` 对称），避免与信令线程竞争。

**B3. EventChannel 取消/析构 —— `flutter_common.cc:95-99`**
```cpp
// OnCancel callback
on_listen_called_ = false;
sink_.reset();          // NEW: drop sink so late PostEvent finds null and is skipped
```
> 可再加 `std::atomic<bool> cancelled_`，`Success()/PostEvent()` 在置位后直接 return。

**B4. PeerConnectionClose —— `flutter_peerconnection.cc:388-403`**
> 现状：同步 `Close()` + `erase` observer，**无锁、不解注册 observer**。改为 `base_->lock()` 保护下先解注册 observer（若有对称的 `UnregisterRTCPeerConnectionObserver`），再 `erase`/`Close`；observer 各回调入口加"已关闭"守卫。

### C. Dart 配合（缩小竞争窗口 + 清噪声）

**C1. 修正销毁顺序 —— `lib/screens/remote_screen.dart:406-431`**
> 现状：`:416 _renderer.dispose()`（销毁纹理）在 `:427 webRTCService.disconnect()`（停帧源）**之前**，顺序反了。
```dart
// stop the frame source first, dispose the texture last
_renderer.srcObject = null;            // detach track
if (_mySessionId == _activeSessionId) {
  webRTCService.disconnect();          // close PC -> stop pushing frames
}
statsService.stop();
p2pAssistService.dispose();
_renderer.dispose();                   // dispose texture LAST
```

**C2. 消除 `message.binary` 噪声异常 —— `p2p_assist_service.dart:1201 / 1220 / 1294`**
> `binary` getter 是 `_data as Uint8List`，对文本消息会先抛 `String is not Uint8List`，`??` 拦不住。
```dart
_handleQualityTestData(
  session,
  message.isBinary ? message.binary : Uint8List.fromList(message.text.codeUnits),
);
```

---

## 5. 注意事项

1. **不要改动 `flutter_data_channel.cc:142-163` `OnMessage` 的 `type`/`data` 表达**——`data` 故意永远用 `Uint8List`、`type` 标 `binary/text`，是为修"非 UTF-8 字节导致整条 EventChannel 崩 FormatException"（见注释 :149-157）。C2 是在 Dart 端正确消费它，不是回退它。
2. **C++ 注释一律英文/ASCII**（`/WX` + C4819）。
3. **不在 WSL 运行 flutter/dart/pub**；构建用 `powershell.exe`，不自动编译。
4. **发布链路**：改 `WebRtcGo` fork → push → 主项目 `pubspec.yaml` 更新 `ref`/重新解析 `resolved-ref` → `pub get` → 重新构建 Windows Release。

## 6. 验证与回归

- **压测**：反复"进入远控→退出"、快速切换不同终端会话、在退出瞬间仍有画面传输时关闭——重点压 `videoRendererDispose` 路径。
- **判定**：修复后运行数日，`crash_logs/` 不再产生 `+0x463E5` 的 dump。
- **回归**：远控画面正常显示、旋转/分辨率变化正常、剪贴板/中文数据通道不报 FormatException。

---

## 7. 附：把根因从"排除法推断"升级到"100% 实锤"

### 7.0 当前确证程度

目前结论由"**多路证据收敛 + 排除法**"得出，置信度高但非反汇编级实锤。三条路径可补强，**强烈推荐 7.2（行为级验证）**——它最快、不依赖引擎符号，且直接证明因果。

### 7.1 你需要匹配的二进制指纹（已从 dump 提取）

```
flutter_windows.dll
  TimeDateStamp = 0x6930ABAE
  SizeOfImage   = 0x11C6000
  PE 符号服务器键 (dll) = 6930ABAE11C6000
  PDB 文件名    = flutter_windows.dll.pdb
  PDB GUID+Age  = 727032ECD3C64DF086F21CEBD1C22F97  + 1
  CI 构建路径   = C:\b\s\w\ir\cache\builder\engine\src\out\ci\host_release\
  故障偏移      = +0x463E5    (RIP)
  关联栈偏移簇  = +0x41xxx ~ +0x4Cxxx (embedder 纹理/平台派发区), 消息泵 +0x6B849C
```
> 注意：`host_release` + 不公开的 CI 内网 PDB 路径说明这是 **Flutter 官方 release engine**，其 PDB **不在公共符号服务器发布**。因此"完全符号化"通常需要 7.4 的本地手段。

### 7.2 方法一（推荐·最快·不依赖引擎符号）：native 行为级验证

在 `flutter_webrtc` fork 里临时加日志（用现有 `WebRtcCrashLogger`，或 `OutputDebugStringA` / `std::cerr`），**先不加修复**，复现一次崩溃，用日志直接证明"销毁后仍在推帧"：

- `OnFrame` 入口（`flutter_video_renderer.cc:47`）：打印 `texture_id_` + `disposed_`（先临时加 `disposed_` 仅用于观测）。
- `registrar_->MarkTextureFrameAvailable` 前（:81）：打印 `texture_id_`。
- `VideoRendererDispose`（:165）：进入与 `UnregisterTexture` 完成回调各打印 `texture_id` + 时间戳。

**判定**：若日志出现 `VideoRendererDispose(texid=N)` 之后，仍有 `OnFrame(texid=N)` / `MarkTextureFrameAvailable(texid=N)` ——即**销毁后仍推帧**，因果链当场坐实。配合崩溃时间点对齐 `texid`（如 28 日 `1830078480`）即为实锤。

> 进阶（既验证又修复）：加 `disposed_` 屏障后，统计"被屏障拦下的迟到帧"计数；上线后该计数 > 0 且不再崩，反证屏障正是拦住了原崩溃路径。

### 7.3 方法二：WinDbg / cdb 离线分析 dump（部分不依赖引擎符号）

安装 **Debugging Tools for Windows**（Windows SDK 组件）。即使没有引擎 PDB，也能确认"故障指令是读空指针"与精确调用栈：

```
:: 在 Windows 上（PowerShell），打开 28 日 dump
& "C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe" ^
  -z "C:\Users\Administrator\Desktop\opsLog\crash_logs\crash_20260528_222840.dmp" ^
  -c ".sympath srv*C:\symbols*https://msdl.microsoft.com/download/symbols; .reload; .ecxr; r; u @rip L3; k; lmvm flutter_windows; q"
```
关注输出：
- `.ecxr` 切到崩溃现场；`r` 看寄存器，确认某寄存器为 `0`。
- `u @rip L3` 反汇编故障指令：应是形如 `mov rax,[rcx+XX]` 且 `rcx=0`（读 NULL+偏移）——确认"读空指针"。
- `k` 为引擎用 dump context 做的**精确调用栈**（比启发式扫描准），观察纹理/呈现相关帧及 `flutter_webrtc_plugin.dll` 帧。

### 7.4 方法三：完全符号化（拿到函数名）

目标是让 `+0x463E5` 显示为引擎函数名（预期落在 `TextureRegistrar` / 纹理呈现路径）。可选途径：

1. **本地编译同版本带符号引擎**（最权威，成本高）：取宿主 framework revision `66dd93f9...` 对应的 engine commit（`flutter --version` 末尾的 `Engine • revision`，或 `<SDK>\bin\internal\engine.version`），用 `depot_tools` 同步 engine 到该 commit，`gn`+`ninja` 构建 `host_release`（或 `host_debug_unopt` 符号更全），得到带 PDB 的 `flutter_windows.dll`，在 WinDbg `.sympath` 指向它再 `.reload`。
2. **用 debug/profile 引擎复现**（更省事）：以 debug 模式跑客户端（debug 的 `flutter_windows.dll` 符号更全），按 7.2 的压测复现崩溃抓新 dump，`k` 直接出函数名。
3. **上报 Flutter**：带 7.1 指纹 + dump 提 issue / 在 flutter 引擎仓库用相同 commit 比对。

### 7.5 实锤判定标准（满足任一即可定案）

- 7.2 日志显示 `videoRendererDispose` 后同 `texture_id` 仍触发 `OnFrame`/`MarkTextureFrameAvailable`；**且**加 `disposed_` 屏障后崩溃消失。
- 7.3/7.4 反汇编显示 `+0x463E5` 是读 NULL+偏移、栈帧落在引擎纹理/呈现路径。

---

## 8. 优先级 / 风险

| 项 | 必要性 | 风险 |
|---|---|---|
| A（纹理屏障 `disposed_`） | **必做，直接止血** | 低-中：注意锁粒度，按 A2 全程持锁即可 |
| C1（Dart 销毁顺序） | 强烈建议 | 低：纯 Dart |
| B（observer/PC/取消） | 建议，堵同源隐患 | 中：需熟悉 libwebrtc 回调线程 |
| C2（binary 噪声） | 建议，清异常日志 | 低 |
| 7.2 行为级验证 | 上线前强烈建议 | 低：临时日志 |
