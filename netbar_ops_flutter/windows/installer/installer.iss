; ============================================================
; NetBar-Ops Flutter Windows Installer
; 使用 Inno Setup 6 编译
;   - 首次安装：完整向导
;   - 自动升级：传 /SILENT /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /NORESTART
; ============================================================

#define MyAppName "NetBar-Ops"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef MyAppBuild
  #define MyAppBuild "1"
#endif
#define MyAppExeName "netbar_ops_flutter.exe"
#define MyAppPublisher "WangKaGuanLi"
#define MyAppURL "https://wangkaguanli.com"

; 构建产物源目录（相对 .iss 文件位置）
; 默认 Flutter Release 构建产物路径
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef OutputDir
  #define OutputDir ".\dist"
#endif

[Setup]
AppId={{B7E2C6F1-2D8A-4F23-9C7B-F1A2B3C4D5E6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion} (build {#MyAppBuild})
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=netbar-setup-{#MyAppVersion}-{#MyAppBuild}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin
UninstallDisplayName={#MyAppName}
; 自动检测并关闭运行中的主程序，安装完成后重启
CloseApplications=yes
RestartApplications=yes
CloseApplicationsFilter=*.exe,*.dll

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
; 如需中文界面：
;   1. 从 https://raw.githubusercontent.com/jrsoftware/issrc/main/Files/Languages/Unofficial/ChineseSimplified.isl 下载
;   2. 放到 <InnoSetup安装目录>\Languages\Unofficial\ChineseSimplified.isl
;   3. 把下面这行的前导分号去掉
;Name: "chinesesimplified"; MessagesFile: "compiler:Languages\Unofficial\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; 整个 Flutter Release 目录
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; First install: let user choose to launch (skipped in silent mode)
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; \
    Flags: nowait postinstall skipifsilent
; Silent upgrade: force restart the app
Filename: "{app}\{#MyAppExeName}"; Flags: nowait; Check: WasSilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
function WasSilent: Boolean;
begin
  Result := WizardSilent;
end;

// 双保险：安装前强制 kill 主程序，避免文件被占用
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec('taskkill.exe', '/F /IM {#MyAppExeName}', '',
       SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := '';
end;
