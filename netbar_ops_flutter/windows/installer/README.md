# Windows 安装包构建

## 前置条件

1. 安装 [Inno Setup 6](https://jrsoftware.org/isinfo.php)（默认路径 `C:\Program Files (x86)\Inno Setup 6\`）
2. 已执行 `flutter build windows --release`，确认 `build\windows\x64\runner\Release` 存在

## 一键打包

```powershell
cd windows\installer
.\build.ps1 -Version 1.0.5 -Build 105
# 输出: dist\netbar-setup-1.0.5-105.exe
```

## 自动升级流程

主程序下载到 setup.exe 后，调用：

```dart
Process.start(setupPath, [
  '/SILENT',
  '/CLOSEAPPLICATIONS',
  '/RESTARTAPPLICATIONS',
  '/NORESTART',
], mode: ProcessStartMode.detached);
exit(0);
```

setup.exe 会：
1. 自动 kill 主程序（`taskkill /F /IM netbar_ops_flutter.exe`）
2. 静默替换文件（只显示进度条）
3. 安装完成后自动重启主程序

## 手动测试

```powershell
# 用户首次安装：双击 setup.exe → 完整向导
.\dist\netbar-setup-1.0.5-105.exe

# 模拟自动升级
.\dist\netbar-setup-1.0.5-105.exe /SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NORESTART
```
