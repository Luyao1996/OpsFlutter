# iOS App Store 发布脚本使用手册（零基础版）

> 给**从没发布过 iOS App** 的人。脚本 `release_ios.sh` 把"环境检查 → 编译 → 上传 → 提审"
> 串成 6 个阶段，失败会停下来用中文告诉你"哪错了、为什么、下一步敲什么命令"。
> **本脚本只能在 macOS 上运行**（iOS 编译/上传是苹果独占，Windows/WSL/Linux 都不行）。

---

## 〇、一句话流程

```
在 Mac 上:  cd 到本脚本目录  ->  ./release_ios.sh  ->  跟着提示走
```

中途要你去网页/Xcode 操作的地方，脚本会自动打开网页并暂停等你回车。

---

## 一、开工前要准备的 4 样东西

| # | 东西 | 怎么搞 / 在哪 | 没有会怎样 |
|---|------|--------------|-----------|
| 1 | 一台 **Mac** + **Xcode 16 或更高** | Mac App Store 搜 "Xcode" 安装（约十几 GB，很慢，提前装好） | 低于 16 脚本直接拦截，因为 App Store 2025-04-24 起强制 |
| 2 | **付费 Apple 开发者账号**（99 美元/年） | https://developer.apple.com/programs/enroll 用 Apple ID（需开双重认证）注册付费，等 1-2 天审核通过 | 免费账号**无法上架**，只能真机调试 |
| 3 | **App Store Connect API Key** 三件套：`.p8` 文件 + Key ID + Issuer ID | 见下方 "二、生成 API Key" | 脚本上传时无法认证 |
| 4 | 项目代码已在 **Mac 上** | 用 git clone 或拷贝到 Mac（WSL 里的路径在 Mac 上是另一份） | 没代码没法编译 |

---

## 二、生成 App Store Connect API Key（最容易卡住的一步，单独讲）

1. 浏览器登录 https://appstoreconnect.apple.com （首次要双重认证，输信任设备上的 6 位码）。
2. 点 **Users and Access（用户和访问）**。
3. 点顶部 **Integrations（集成）** 标签 → 左侧选 **App Store Connect API**。
   - （2023 年改版前这里叫 "Keys"，意思一样）
4. 选 **Team Keys** 子标签 → 点 **+（生成）**。
5. 弹窗里：
   - **Name（名称）**：随便起，如 `NetbarOps-Upload`（只给你自己看）。
   - **Access（角色）**：选 **App Manager**（够用且安全；不要选 Developer，权限不够会被拒）。
6. 点生成。列表里出现新 Key，记下它的 **Key ID**（一串字母数字）。
7. 该行右侧点 **Download（下载）** → 得到 `AuthKey_<KeyID>.p8` 文件。
   - ⚠️ **这个文件全网只能下载一次！** 刷新页面后下载链接消失。丢了只能撤销重建。
8. 页面**顶部**有个 **Issuer ID**（UUID，形如 `57246542-96fe-...`），点 Copy 记下来。

到这里你应该有：`AuthKey_XXXX.p8` 文件 + Key ID + Issuer ID。脚本阶段 B 会问你这三样，并自动把 `.p8` 放到 `~/.appstoreconnect/private_keys/`。

---

## 三、运行脚本

```bash
# 在 Mac 终端里
cd <项目>/scripts/ios
chmod +x release_ios.sh          # 第一次需要给执行权限
./release_ios.sh                 # 跑完整流程
```

常用变体：

```bash
./release_ios.sh --from D        # 从"构建"阶段开始（改完代码重跑，不用从头）
./release_ios.sh --only A        # 只做环境体检
./release_ios.sh --only F        # TestFlight 测好后，单独回来提交审核
./release_ios.sh --help          # 看帮助
```
（阶段字母大小写都行，如 `--only f` 等价 `--only F`）

### 各阶段都在干嘛

| 阶段 | 干嘛 | 是否需要你动手 |
|------|------|--------------|
| **A 体检** | 检查 macOS / Xcode≥16 / Flutter / CocoaPods / 磁盘 / 网络 | 全自动 |
| **B 配置** | 问你 Team ID / Key ID / Issuer ID，**立刻验证能不能认证** | 输入三要素 |
| **C 网页/Xcode** | 签协议 → 新建 App 记录 → Xcode 登录并生成证书 | **要你去网页和 Xcode 操作**，脚本会暂停等你 |
| **D 构建** | 处理 4 条上架红线 → 自增 build 号 → 生成 ExportOptions → `flutter build ipa` | 会停下问你权限文案/出口合规 |
| **E 上传** | 先校验再上传，失败自动诊断 | 全自动 |
| **TF TestFlight** | 引导你先把包装到手机测试；默认停下等你测，测好用 `--only F` 提审 | **要你去 TestFlight 测**（见第 ⑨ 节） |
| **F 提审** | 给你网页提审清单 | **要你去网页填资料、提交审核** |

> 💡 **先测后发**：上传一次，先 TestFlight 测，测好的**同一个包**直接提审发布，全程不重新编译。详见第 ⑨ 节。

---

## 四、阶段 D 会停下来问你的 3 件事（都涉及改 iOS 配置，脚本先问再改）

1. **出口合规**（`ITSAppUsesNonExemptEncryption`）
   - 你的 App 含 WebRTC（DTLS-SRTP 加密）。
   - 若只用 HTTPS/TLS 和 WebRTC 标准加密、没有自研加密算法 → 一般可选 `1` 写 `false`（豁免）。
   - 拿不准就选 `3` 中止，去问清楚再来。**这是有法律效力的声明，别乱填。**

2. **权限用途串**（`NSCameraUsageDescription` 等）
   - 脚本逐个问：相机 / 麦克风 / 本地网络 / 相册。
   - App **确实会用到**的，填一句中文用途（如"用于远程协助时采集摄像头画面"）；用不到的**直接回车跳过**。
   - 填错/缺失会被苹果以 **ITMS-90683** 拒。

3. **隐私清单**（`.xcprivacy`）
   - 脚本只**检测+提示**，不自动建文件。
   - 原则：靠插件自带的 `.xcprivacy`，**不要自己在 Runner 里建空的**（反而触发 ITMS-91061）。
   - 若上传报 ITMS-91053/91061，去升级 `shared_preferences` / `path_provider` 等插件到新版本。

> 改动 `Info.plist` / `pubspec.yaml` 前脚本都会先备份成 `*.bak.<时间戳>`。

---

## 五、常见报错速查（脚本也会自动提示，这里是完整版）

| 报错关键字 | 含义 | 怎么修 |
|-----------|------|--------|
| `requires Xcode ... command line tools instance` | 命令行没指向完整 Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `You have not agreed to the Xcode license` | 没同意 Xcode 许可 | `sudo xcodebuild -license accept` |
| `requires a development team` / `No profiles` | 没选团队/没生成描述文件 | 回阶段 C3：Xcode 勾自动签名 + 选付费 Team |
| `(Personal Team) cannot be used ... App Store` | 用了免费账号 | 必须加入付费开发者计划（99 美元/年） |
| `Unable to authenticate` / `Could not find the API key` | API Key 认证失败 | 查 Key ID/Issuer ID 是否填反；`.p8` 文件名须为 `AuthKey_<KeyID>.p8`；角色须 App Manager |
| `ITMS-90186` / `ITMS-90189` / `already been used` | build 号重复 | 递增 build 号（脚本会自动 +1 重试一次） |
| `ITMS-90683` / `ITMS-90713` | 缺隐私用途串 | 回阶段 D 给对应权限补 `NSxxxUsageDescription` |
| `ITMS-91053` / `ITMS-91061` | 缺隐私清单 | 升级相关插件到自带 `.xcprivacy` 的版本 |
| `ITMS-90426` / `SwiftSupport` | 缺 SwiftSupport | 用正式版 Xcode + app-store 方式导出（脚本默认已如此） |
| `ITMS-90022` / `ITMS-90023` | 缺图标 | 补齐 AppIcon 全尺寸（从 1024 一键生成，去 alpha 透明通道） |
| `CocoaPods could not find` / `pod install` 失败 | Pod 依赖问题 | 删 `ios/Pods` 和 `ios/Podfile.lock` → `pod repo update` → `flutter clean` → 重试 |
| 安装 CocoaPods 报 `write permissions ... Ruby` | 系统 Ruby 权限 | 别用 `sudo gem`，改用 `brew install cocoapods` |

> ⚠️ **别用错工具**：iOS 上传 App Store 用的是 `xcrun altool --upload-app`（脚本已用）。
> `notarytool` 是给 **macOS app 公证** 用的，**不用于 iOS App Store**，网上有教程搞混了，别跟着用。

---

## 六、安全注意

- `.p8` 私钥等同账号凭证，泄露后别人能冒名上传/管理你的 App。
- 脚本已自动把 `*.p8` / `AuthKey_*.p8` / `.ipa_release.env` / `logs/` 加进 `.gitignore`。
- 千万**别把 `.p8` 提交进 git**。万一提交过，去 App Store Connect 撤销该 Key 重建。

---

## 七、产物与路径

| 东西 | 路径 |
|------|------|
| 编译出的 IPA | `build/ios/ipa/*.ipa` |
| 导出配置 | `ios/ExportOptions.plist`（脚本生成） |
| 发布配置 | `scripts/ios/.ipa_release.env`（不入 git） |
| 运行日志 | `scripts/ios/logs/release_<时间戳>.log` |
| API 私钥 | `~/.appstoreconnect/private_keys/AuthKey_<KeyID>.p8` |

---

## 八、首次发布的完整顺序（串起来看）

```
装 Xcode16+  →  注册付费开发者(等审核)  →  生成 API Key 拿到 .p8/KeyID/IssuerID
   ↓
./release_ios.sh
   ↓ A 体检通过
   ↓ B 填三要素, 认证通过
   ↓ C 签协议 → 新建App记录 → Xcode生成证书
   ↓ D 答出口合规/权限文案 → 自动构建出 IPA
   ↓ E 自动校验 + 上传成功
   ↓ TF 先去 TestFlight 装手机测试（默认脚本停在这一步，见第九节）
   ↓    测好后运行 ./release_ios.sh --only F 回来提审
   ↓ F 网页填截图/描述/隐私 → 选构建 → 提交审核（用你测过的同一个包，不重编）
   ↓
等审核(1-3天) → 通过 → 上架 🎉
```

---

## 九、TestFlight：先测后发（重点，对应阶段 TF）

iOS 没有"像 apk 那样能随便装的测试包"——装真机必须签名授权。**TestFlight 就是 iOS 官方的"先测后发"机制**：脚本上传的那个包先进 TestFlight 供你测，测好后**同一个包**直接提审发布，不用重新编译。

### 脚本里怎么走

阶段 E 上传成功后，脚本进入 **阶段 TF**，打印 TestFlight 指引并问你：

```
现在就进入【提交审核/发布】(阶段 F)吗? [y/N]
```

- **直接回车（默认 N）** → 脚本停下，你去 TestFlight 测；测好后运行 `./release_ios.sh --only F` 回来提审。
- **输入 y** → 不测，直接进入提审。

### TestFlight 测试操作步骤

**A. 在 App Store Connect 网页（https://appstoreconnect.apple.com）**
1. 进你的 App → **TestFlight** 标签，等构建从「正在处理(Processing)」变为可用（一般几分钟，**首个构建可能几小时**，会收到 Apple 邮件）。
2. 首个构建若提示补「测试信息 / 出口合规」，按提示填一次。
3. 选测试方式：
   - **内部测试（最快，推荐自测用）**：TestFlight → 内部测试群组 → 加测试员（**必须是你团队里的成员 Apple ID**）→ **无需 Beta 审核，几分钟就能装**。
   - **外部测试（给团队外的人测）**：需提交一次 **Beta App Review**，通过后才能测。

**B. 在 iPhone 上**
4. App Store 搜索并安装 Apple 官方的 **TestFlight** app。
5. 用被加为测试员的 Apple ID 登录 TestFlight → 看到你的 app → 安装 → 像正式版一样跑着测。

### 测完两条路

| 结果 | 操作 |
|------|------|
| ✅ 满意 | `./release_ios.sh --only F` → 用**测过的同一个构建**直接提审发布（不重编） |
| ❌ 要改 | 改代码 → `./release_ios.sh --from D` 出新构建 → 再上传、再测 |

> **关键点**：TestFlight 测试用的 build 和最终上架的 build 是**同一个**。你在 TestFlight 验证过的，就是用户最终下载的。
