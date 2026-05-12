# 一键打包 Windows setup.exe
# 用法：
#   .\build.ps1 -Version 1.0.5 -Build 105
#
# 前置：
#   - 已执行 flutter build windows --release
#   - 已安装 Inno Setup 6（默认路径 C:\Program Files (x86)\Inno Setup 6\）

param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][int]$Build,
    [string]$InnoSetupPath = "D:\Inno Setup 6\ISCC.exe",
    [string]$SourceDir = "..\..\build\windows\x64\runner\Release",
    [string]$OutputDir = ".\dist"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InnoSetupPath)) {
    Write-Error "未找到 Inno Setup 编译器: $InnoSetupPath"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$absSource = Resolve-Path (Join-Path $scriptDir $SourceDir) -ErrorAction SilentlyContinue
if (-not $absSource) {
    Write-Error "未找到 Flutter 构建产物目录: $SourceDir，请先执行 flutter build windows --release"
}

Write-Host "==> 打包 NetBar-Ops $Version (build $Build)" -ForegroundColor Cyan
Write-Host "    Source : $absSource"
Write-Host "    Output : $OutputDir"

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

& $InnoSetupPath `
    "/DMyAppVersion=$Version" `
    "/DMyAppBuild=$Build" `
    "/DSourceDir=$absSource" `
    "/DOutputDir=$OutputDir" `
    "installer.iss"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Inno Setup 编译失败 (exit $LASTEXITCODE)"
}

$exeName = "netbar-setup-$Version-$Build.exe"
$outFile = Join-Path $OutputDir $exeName
if (Test-Path $outFile) {
    $size = (Get-Item $outFile).Length / 1MB
    Write-Host "==> 生成: $outFile ({0:N2} MB)" -ForegroundColor Green -f $size
} else {
    Write-Warning "未找到预期输出文件: $outFile"
}
