# Build Windows setup.exe
# Usage:
#   .\build.ps1 -Version 1.0.5 -Build 105
#
# Prerequisite:
#   - flutter build windows --release has been executed
#   - Inno Setup 6 installed (default path: C:\Program Files (x86)\Inno Setup 6\)

param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][int]$Build,
    [string]$InnoSetupPath = "D:\Inno Setup 6\ISCC.exe",
    [string]$SourceDir = "..\..\build\windows\x64\runner\Release",
    [string]$OutputDir = ".\dist"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InnoSetupPath)) {
    Write-Error "Inno Setup compiler not found: $InnoSetupPath"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

$absSource = Resolve-Path (Join-Path $scriptDir $SourceDir) -ErrorAction SilentlyContinue
if (-not $absSource) {
    Write-Error "Flutter build output not found: $SourceDir. Run 'flutter build windows --release' first."
}

Write-Host "==> Packaging NetBar-Ops $Version (build $Build)" -ForegroundColor Cyan
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
    Write-Error "Inno Setup compile failed (exit $LASTEXITCODE)"
}

$exeName = "netbar-setup-$Version-$Build.exe"
$outFile = Join-Path $OutputDir $exeName
if (Test-Path $outFile) {
    $size = (Get-Item $outFile).Length / 1MB
    Write-Host ("==> Generated: {0} ({1:N2} MB)" -f $outFile, $size) -ForegroundColor Green
} else {
    Write-Warning "Expected output file not found: $outFile"
}
