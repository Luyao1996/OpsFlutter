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

# 发布新版本（交互式）
.\netbar-release.exe publish

# 查看历史
.\netbar-release.exe list

# 回滚（删除最新一条）
.\netbar-release.exe rollback --platform=android

# 调整 minSupportedBuild
.\netbar-release.exe set-min --platform=android --build=100
```

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
