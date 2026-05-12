# netbar-release

NetBar-Ops Flutter 客户端发布工具。维护 OSS 上的 `version.json` + 上传安装包。

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

# ⭐ 一键发布：编译 + 打包 + 上传（推荐）
.\netbar-release.exe release

# 一键发布 - 半自动（指定平台和版本号）
.\netbar-release.exe release --platform=windows --version=1.0.2

# 一键发布 - 完全无人值守（CI 友好）
.\netbar-release.exe release `
    --platform=both `
    --version=1.0.2 `
    --changelog-file=CHANGELOG.txt `
    --yes

# 上传已编译好的安装包（兜底用）
.\netbar-release.exe publish

# 查看历史
.\netbar-release.exe list

# 回滚（删除最新一条）
.\netbar-release.exe rollback --platform=android

# 调整 minSupportedBuild
.\netbar-release.exe set-min --platform=android --build=100
```

## release 子命令工作流程

```
1. 拉取当前 version.json，显示各平台最新版本
2. 用户选择平台（windows / android / both）
3. 用户输入版本号，工具自动推算 buildNumber（当前 +1）
4. 用户输入是否强制更新、minSupportedBuild、changelog
5. 预览所有信息，等用户确认
6. 自动执行：
   - flutter build apk/windows --release --build-name=X --build-number=Y
   - (Windows) Inno Setup 打包 setup.exe
   - 计算 MD5 + 文件大小
   - 申请 OSS 签名 URL
   - PUT 上传到 OSS
   - 更新并上传 version.json
```

**核心收益**：三个版本号（编译参数 / Inno Setup / version.json）由工具统一管理，不会再因为人为遗漏 `--build-number` 而出现"版本号说是 1.0.2 但 exe 报告自己是 1.0.0"的 bug。

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
