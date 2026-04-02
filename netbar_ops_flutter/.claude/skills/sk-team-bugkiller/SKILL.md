---
name: sk-team-bugkiller
description: "Agent Team 协作修 Bug。调查员深度分析 → 评审员质疑方案 → 调查员实施修改 → 验证员编译测试。agent 持久存活，上下文完整保留，最多重试 3 次。关键词：修 bug、agent team、团队修复、bugkiller"
allowed-tools: "*"
allowed-bash-commands:
  - "powershell.exe *"
  - "curl *"
  - "git *"
---

# Bug Killer Team

> 调查员(A) ↔ 评审员(B) ↔ 验证员(D)，全程持久存活，上下文完整保留，最多 3 轮。

## CLAUDE.md 规则覆盖

> 本 skill 执行期间以下规则不适用：
> - "禁止自动编译、测试" / "先方案后动手"
> 其他规则仍有效（如禁止在 WSL 直接运行 flutter/dart、禁止 push 到远程）。

## 项目上下文

- **项目**：netbar_ops_flutter — 网吧运营管理 Flutter 客户端
- **技术栈**：Flutter/Dart + C++ 插件（desktop_multi_window）
- **平台**：Web / Windows / Android / iOS / macOS
- **架构**：features/ 按业务模块划分（auth, channel, dashboard, desktop, logs, monitor, netbar, resource, user），core/ 通用基础，shared/ 共享组件
- **状态管理**：flutter_riverpod
- **路由**：go_router
- **网络**：dio
- **序列化**：freezed + json_serializable
- **特殊依赖**：webrtc_remote（远程桌面）、desktop_multi_window（多窗口）

## 编排器铁律

1. **绝不自己读代码、分析代码、修改代码** — 全部通过 SendMessage 交给 agent
2. **绝不跳过任何步骤**
3. **只用 SendMessage 与 agent 通信** — 不要重新 spawn 已有成员
4. **验证员是必经步骤** — 代码修改后必须让验证员编译测试
5. **出错时重新发消息** — 不要自己接手
6. **不要自动 shutdown 成员** — 仅在用户明确说"关闭团队"/"shutdown"/"结束团队"时才 shutdown 所有成员
7. **每个 phase/step 完成后必须输出摘要给用户**
8. **用户随时可以打断** — 见"用户中途介入"
9. **绝不调用 Edit/Write 工具修改代码** — 如果你发现自己即将调用 Edit 或 Write（写执行日志除外），立刻停下来，改为 SendMessage 给 investigator。这是硬性限制，没有例外。

## Flutter 命令规则

**所有 Flutter/Dart 命令必须通过 powershell.exe 执行，禁止在 WSL 直接运行。**

```bash
# 正确
powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter analyze"

# 错误 — 禁止
flutter analyze
dart analyze
flutter pub get
```

路径转换规则：`/mnt/e/xxx` → `E:\xxx`

## 用户可见输出

agent 工作期间用户看不到内部操作。**编排器收到每个 agent 的回复后，必须立刻输出摘要给用户**：

```
--- {角色} Phase/Step N 完成 ---
操作: {从 agent 操作日志中提取}
结果: {关键结论}
下一步: {即将执行什么}
```

## 用户中途介入

用户可以随时发消息打断。编排器收到后：
1. 通过 SendMessage 转发给当前正在工作的 agent
2. agent 处理完后流程从当前步骤继续

用户说"停止"或"取消"→ 暂停当前流程，等待用户进一步指令。
用户明确说"关闭团队"/"shutdown"/"结束团队"→ `rm -f /tmp/claude-team-active`，shutdown 所有成员并写执行日志。

---

## 启动流程

### 1. 参数检查

必填：`bug_description`（未提供则提醒用户描述 bug）。
可选：`platform`（web/windows/android/ios，影响验证命令）。

### 2. 创建团队 + Spawn 调查员

```
Bash: rm -f /tmp/claude-team-active && touch /tmp/claude-team-active
TeamDelete(team_name: "bugkiller")   # 清理上次可能残留的团队，报错则忽略
TeamCreate(team_name: "bugkiller")
```

Spawn investigator 并给 **Phase 1 任务**（reviewer/verifier 在需要时再 spawn）：

```
Agent(
  name: "investigator",
  team_name: "bugkiller",
  subagent_type: "bug-investigator",
  description: "Bug investigator - {简短描述}",
  prompt: "你是 Bug 调查员，已加入 Bug Killer Team。

## 项目信息
- 项目：netbar_ops_flutter（网吧运营管理 Flutter 客户端）
- 路径：/mnt/e/luyao/GoProjects/NetbarOps/NetBar-Ops/netbar_ops_flutter
- 架构：lib/features/{auth,channel,dashboard,desktop,logs,monitor,netbar,resource,user}
- 状态管理：flutter_riverpod，路由：go_router，网络：dio，序列化：freezed
- 特殊：plugins/desktop_multi_window（C++ 多窗口插件）、webrtc_remote（远程桌面）

## Phase 1 任务：搜索相关代码
**问题描述**: {bug_description}
**目标平台**: {platform}

请执行：
1. 确定调查范围（涉及哪些 feature 模块和组件）
2. 使用 Explore 子 agent 并行搜索与 bug 相关的代码
3. 如果涉及 UI：检查 Widget 树结构、状态管理（Provider/Notifier）
4. 如果涉及网络：检查 dio 请求、API 模型（freezed）
5. 如果涉及多窗口/插件：检查 plugins/desktop_multi_window 的 C++ 代码

输出你找到的相关文件列表和初步发现。**这只是 Phase 1，后续还有 Phase 2 和 3。**"
)
```

输出启动信息，等待返回。

---

## 核心流程

```
Step 1（分 3 个 Phase）→ Step 2 → (Step 3) → Step 4 → Step 5
                                                        ├─ PASS → 结束
                                                        ├─ 编译失败 → Step 4（调查员修编译错误）→ Step 5
                                                        └─ 测试 FAIL → 下一轮（回 Step 1）
```

### Step 1：调查员调查（分 3 个 Phase）

#### Phase 1：搜索代码（第 1 轮在 spawn 时已给出任务）

第 2+ 轮时通过 SendMessage 发起，带上失败上下文。

等待返回 → **编排器输出摘要给用户** → 发 Phase 2。

#### Phase 2：分析日志和上下文

```
SendMessage(
  to: "investigator",
  summary: "Phase 2: 分析日志和上下文",
  message: "## Phase 2：分析日志和上下文

根据你 Phase 1 找到的线索，进一步分析：
- 检查项目根目录的日志文件（flutter_01.log、flutter_02.log 等）是否有相关错误
- 检查 git log 中相关文件的最近改动
- 如果涉及平台特定问题：检查对应平台目录（android/、ios/、windows/、web/、macos/）的配置
- 如果涉及插件：检查 plugins/desktop_multi_window 的 C++ 源码和 CMakeLists.txt
- 如果是纯 UI/逻辑问题且 Phase 1 已足够定位：说明理由，直接输出当前发现

输出与 bug 相关的关键发现。"
)
```

等待返回 → **编排器输出摘要给用户** → 发 Phase 3。

#### Phase 3：综合分析，输出调查报告

```
SendMessage(
  to: "investigator",
  summary: "Phase 3: 输出报告",
  message: "## Phase 3：综合分析

基于 Phase 1（代码）和 Phase 2（日志/上下文）的发现，输出完整调查报告：
现象 → 代码定位 → 根因分析 → 修复方案 → 影响范围

修复方案需明确：
- 改哪些文件，改什么内容
- 是否需要 build_runner 重新生成代码（freezed/json_serializable）
- 是否影响多平台（web/windows/android）
- 是否涉及状态管理变更（Provider/Notifier）

**暂不修改代码**，等待评审通过。"
)
```

等待返回 `investigation_report` → **编排器输出摘要给用户**。

### Step 2：评审员评审

**第 1 轮先 spawn**：
```
Agent(
  name: "reviewer",
  team_name: "bugkiller",
  subagent_type: "bug-reviewer",
  description: "Bug reviewer",
  prompt: "你是 Bug 方案评审员，已加入 Bug Killer Team。

## 任务
**Bug 描述**: {bug_description}
**调查员的调查报告：**
{investigation_report}

请按以下清单审查：
1. 根因分析是否有代码证据支撑（不能凭猜测）
2. 修复方案是否完整（覆盖所有相关文件）
3. 是否有遗漏的边界情况（空值、异常状态、平台差异）
4. 修复是否会引入新问题（状态管理副作用、路由变更影响、Widget 重建性能）
5. 如果涉及 freezed 模型变更：是否需要重新 build_runner
6. 如果涉及插件 C++ 代码：改动是否安全（内存、线程）

输出 APPROVE / NEEDS_REVISION，附理由。"
)
```

**第 2+ 轮**：SendMessage，附带新的 investigation_report。

等待返回 → **编排器输出摘要给用户**。

### Step 3：A-B 补充论证（仅 NEEDS_REVISION 时）

1. SendMessage → investigator："评审员质疑：{review_result}，请补充证据或调整方案"
2. **编排器输出摘要给用户**
3. SendMessage → reviewer："调查员补充：{revised_report}，请给最终裁决 APPROVE/REJECT"
4. **编排器输出摘要给用户**

REJECT 时：有方向 → 告知调查员按建议修改；无方向 → 记为失败进下一轮。

### Step 4：调查员实施修改

```
SendMessage(
  to: "investigator",
  summary: "实施修改",
  message: "方案已通过评审，请修改代码。

注意事项：
- 遵循项目 analysis_options.yaml 规范
- 如果修改了 freezed 模型，提醒需要运行 build_runner
- 如果修改了插件 C++ 代码，确保 CMakeLists.txt 同步
- 完成后列出所有改动文件"
)
```

等待返回 `changed_files` → **编排器输出摘要给用户**。

### Step 5：验证员编译 + 运行测试

分为两个阶段：**编译验证** 和 **运行测试**。

#### 阶段 A：编译验证

编排器根据 `changed_files` 判断改动了哪些组件，在 prompt 中写入对应的**必执行命令**。

**按组件的命令块（编排器按需插入）：**

改动了 `lib/` 下的 Dart 代码：
```
1. 静态分析:
   powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter analyze"
2. 单元/Widget 测试（如果 test/ 下有相关测试）:
   powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter test"
3. 目标平台构建:
   - Windows: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build windows"
   - Web: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build web"
   - Android: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build apk"
   （根据 bug 涉及的平台选择，默认 Windows）
```

改动了 freezed 模型（`*.freezed.dart` 或 `*.g.dart` 相关的源文件）：
```
0. 先执行代码生成（在其他步骤之前）:
   powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; dart run build_runner build --delete-conflicting-outputs"
```

改动了 `plugins/desktop_multi_window/`（C++ 代码）：
```
1. 通过 Flutter Windows 构建间接验证:
   powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build windows"
2. 检查构建输出中是否有 C++ 编译警告/错误
```

改动了平台配置（`android/`、`ios/`、`windows/`、`web/`、`macos/`）：
```
1. 对应平台构建:
   - android/: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build apk"
   - windows/: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build windows"
   - web/: powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter build web"
```

编译通过后进入阶段 B。

#### 阶段 B：运行测试（用户操作）

验证员启动应用并捕获日志，然后**交给用户操作**：

1. **验证员启动应用 + 捕获日志**：
   ```
   powershell.exe -NoProfile -Command "cd 'E:\luyao\GoProjects\NetbarOps\NetBar-Ops\netbar_ops_flutter'; flutter run -d windows 2>&1 | Tee-Object -FilePath flutter_test_run.log"
   ```
   （或用 `run_in_background` 后台启动）

2. **编排器输出给用户**：
   - 告知应用已启动
   - 列出测试步骤（根据 bug/功能描述生成）
   - 请用户按步骤操作

3. **用户操作完成后回复**（描述操作结果、是否复现 bug 等）

4. **编排器将用户回复转发给验证员**

5. **验证员分析日志**：
   - 读取运行日志
   - 结合用户操作描述分析
   - 生成测试报告（PASS/FAIL + 证据）
   - 将报告发送给编排器

6. **编排器输出测试报告给用户**

等待返回 → **编排器输出摘要给用户**。

---

## 结果处理

### PASS

输出成功报告，写执行日志。团队成员保持存活，等待用户后续指令或明确要求关闭。

### 编译失败（特殊短路）

如果验证员报告的是**编译失败**（而非测试失败），不需要重走完整调查流程，**且不计入 3 轮重试次数**：
1. SendMessage → investigator："编译失败，错误信息：{编译错误}，请修复编译问题，完成后列出改动文件。"
2. 等待返回 → 直接回到 Step 5 让验证员重新编译测试

### FAIL（N < 3）

输出失败摘要，回到 Step 1 Phase 1。SendMessage 给 investigator 必须包含：
- 验证员的完整 FAIL 报告（失败现象 + 证据）
- 验证员的建议方向
- 上一轮改了哪些文件
- 明确要求：在上次基础上深入，不要重复相同方案

### 3 次均失败

输出总结报告（3 轮方案/改动/失败原因 + 共同模式分析 + 建议方向），写执行日志。团队成员保持存活，等待用户后续指令或明确要求关闭。

---

## 执行日志

流程结束时（PASS 或 3 次失败后），写入文件：

**路径**：`/mnt/e/luyao/GoProjects/NetbarOps/NetBar-Ops/netbar_ops_flutter/sk-team-bugkiller-record/{bug简述}.md`
- 文件名：英文下划线连接，如 `monitor_page_crash_on_refresh`
- 已存在则加时间戳：`{bug简述}_mmdd_HHmmss`

**内容**：日期、问题、目标平台、结果、总轮次，每轮的（调查摘要 + 评审结果 + 代码修改 + 验证结果），最终的根因/方案/经验教训。

---

## 编排器自检

- 每个 phase/step 完成后：是否输出了摘要给用户？
- 每次 SendMessage 前：是否跳步？上下文是否完整？
- 流程结束时：执行日志是否已写入？
- 所有 Flutter 命令：是否通过 powershell.exe 执行？
