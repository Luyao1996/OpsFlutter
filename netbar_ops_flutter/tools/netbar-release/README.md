# netbar-release

NetBar-Ops Flutter 客户端发布工具。维护 OSS 上的 `version.json` + 上传安装包。

## 发布模型（重要）

本工具采用 **预览版 → 正式版 两阶段发布**：

1. `release` 命令编译/打包/上传安装包，并将版本写入 `version.json` 的 `preview` 字段（不影响正式版用户）
2. 测试通过后，`release-preview-promote` 命令把 `preview` 提升为正式版（无需重新上传安装包）

```
┌── release ──────────┐         ┌── release-preview-promote ──┐
│ 编译 + 上传 apk/exe │  ───→  │ preview 移入 releases，      │
│ 写入 preview 字段   │         │ 清空 preview，上传 manifest │
└─────────────────────┘         └─────────────────────────────┘
       (预览版用户尝鲜)                  (所有正式版用户收到更新)
```

## 构建

```powershell
# 在 Windows 上构建
cd tools\netbar-release
go mod tidy
go build -o netbar-release.exe ./cmd
```

## 使用

```powershell
# 拷贝配置
copy config.example.yaml config.yaml

# ⭐ 步骤 1：发布预览版（编译 + 打包 + 上传，写入 preview 字段）
.\netbar-release.exe release

# 半自动 - 指定平台和版本号
.\netbar-release.exe release --platform=windows --version=1.0.2

# 完全无人值守（CI 友好）
.\netbar-release.exe release `
    --platform=both `
    --version=1.0.2 `
    --changelog-file=CHANGELOG.txt `
    --yes

# ⭐ 步骤 2：把预览版提升为正式版（不重新编译/上传安装包）
.\netbar-release.exe release-preview-promote
.\netbar-release.exe release-preview-promote --platform=windows
.\netbar-release.exe release-preview-promote -y    # CI 跳过确认

# 上传已编译好的安装包（兜底用，直接写入 releases）
.\netbar-release.exe publish

# 查看历史（含 preview）
.\netbar-release.exe list

# 回滚（删除最新一条 release）
.\netbar-release.exe rollback --platform=android

# 调整 minSupportedBuild
.\netbar-release.exe set-min --platform=android --build=100
```

## release 子命令工作流程

```
1. 拉取当前 version.json，显示各平台正式版 + preview 状态
2. 用户选择平台（windows / android / both）
3. 用户输入版本号，工具自动推算 buildNumber（max(releases[0], preview) + 1）
4. 用户输入是否强制更新、minSupportedBuild、changelog
5. 预览所有信息，等用户确认（preview 已存在时额外提示覆盖）
6. 自动执行：
   - flutter build apk/windows --release --build-name=X --build-number=Y
   - (Windows) Inno Setup 打包 setup.exe
   - 计算 MD5 + 文件大小
   - 申请 OSS 签名 URL → PUT 上传到 OSS
   - 写入 version.json 的 preview 字段（覆盖式）→ 上传
7. 提示用户："使用 release-preview-promote 将预览版升级为正式版"
```

## release-preview-promote 子命令工作流程

```
1. 拉取当前 version.json，列出待升级的 preview
2. 用户确认（CI 用 -y 跳过）
3. 备份当前 version.json
4. 对每个平台：preview → releases[0]，按 buildNumber 降序排，截断到 max_releases
5. 上传 version.json
```

**核心收益**：
- 三个版本号（编译参数 / Inno Setup / version.json）由工具统一管理
- 两阶段发布模型：预览版用户先验证，再向所有用户铺开，降低翻车风险
- promote 不重传安装包，预览版/正式版的 OSS 文件物理上是同一份

## 工作流程

1. 选择平台（Android / Windows）
2. 选择本地安装包文件（apk / exe）
3. 输入版本号与 buildNumber
4. 输入 changelog
5. 工具自动：
   - 备份当前 `version.json` → `/backups/version-<时间>.json`
   - 调用签名服务申请上传 URL
   - POST 上传安装包到 OSS
   - 更新并上传 `version.json`

## 签名服务约定

```
GET <base_url>/OSS/Signature.php?file=/netbaropsflutter/xxx.apk

→ {"code": 0, "msg": "...", "url": "<预签名 URL>"}
```

随后客户端 `POST <预签名 URL>`，`Content-Type: application/octet-stream`，body 为文件二进制。
