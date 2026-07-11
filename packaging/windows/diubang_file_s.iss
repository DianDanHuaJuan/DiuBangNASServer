; 铥棒文件S Windows 安装包脚本（Inno Setup 6）
; 编译前请先执行 flutter build windows --release，或使用 build_installer.ps1

#ifndef MyAppVersion
  #define MyAppVersion "1.0.2"
#endif

#ifndef MyAppVersionFull
  #define MyAppVersionFull "1.0.2+2"
#endif

#define MyAppName "铥棒文件S"
#define MyAppDirName "DiuBangWenJianS"
#define MyAppPublisher "铥棒文件S"
#define MyAppExeName "diubang_file_s.exe"
#define MyAppId "{{A3F8C2E1-9B4D-4A6F-8E2C-1D5B7F9A0C3E}"
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersionFull}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppDirName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=output
OutputBaseFilename=DiuBangFileS-Setup-{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=admin
AppMutex=Local\DiuBangFileS.SingleInstance
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll,*.so
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加图标:"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "vc_redist.x64.exe"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Messages]
chinesesimplified.BeveledLabel=铥棒文件S NAS 服务端（Windows 10/11 x64，已附带 MSVC 运行库）

; 兜底清理安装目录残留（仅限 {app}，不触及用户共享目录 Documents\NASServer）
[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  AppMutexName = 'Local\DiuBangFileS.SingleInstance';
  LaunchAtStartupValueName = '{#MyAppName}';
  ERROR_ALREADY_EXISTS = 183;

function CreateMutex(lpMutexAttributes: Cardinal; bInitialOwner: Boolean;
  lpName: String): THandle;
  external 'CreateMutexW@kernel32 stdcall';

function GetLastError: DWORD;
  external 'GetLastError@kernel32 stdcall';

function CloseHandle(h: THandle): Boolean;
  external 'CloseHandle@kernel32 stdcall';

procedure TryTaskKill(const ImageName: String);
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'),
    '/F /T /IM ' + ImageName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function IsAppMutexHeld: Boolean;
var
  MutexHandle: THandle;
begin
  MutexHandle := CreateMutex(0, False, AppMutexName);
  if MutexHandle = 0 then
  begin
    Result := False;
    Exit;
  end;
  Result := (GetLastError = ERROR_ALREADY_EXISTS);
  CloseHandle(MutexHandle);
end;

procedure TerminateAppProcesses;
begin
  TryTaskKill('{#MyAppExeName}');
  TryTaskKill('ffmpeg.exe');
end;

procedure WaitForAppExit(const MaxWaitMs: Integer);
var
  Elapsed: Integer;
begin
  Elapsed := 0;
  while IsAppMutexHeld and (Elapsed < MaxWaitMs) do
  begin
    Sleep(200);
    Elapsed := Elapsed + 200;
  end;
end;

procedure CleanupLaunchAtStartup;
begin
  if RegValueExists(HKEY_CURRENT_USER,
    'Software\Microsoft\Windows\CurrentVersion\Run', LaunchAtStartupValueName) then
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run', LaunchAtStartupValueName);
end;

procedure ForceRemoveInstallDir;
var
  AppDir: String;
begin
  AppDir := ExpandConstant('{app}');
  if DirExists(AppDir) then
    DelTree(AppDir, True, True, True);
end;

function InitializeUninstall(): Boolean;
begin
  { Must run before usAppMutexCheck so silent uninstall does not abort early. }
  TerminateAppProcesses;
  WaitForAppExit(5000);
  if IsAppMutexHeld then
  begin
    TerminateAppProcesses;
    WaitForAppExit(2000);
  end;

  Result := True;
  if IsAppMutexHeld and not WizardSilent then
  begin
    MsgBox(
      '无法完全关闭 {#MyAppName}。请从系统托盘右键选择「退出」后重试卸载。',
      mbError, MB_OK);
    Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    TerminateAppProcesses;
    WaitForAppExit(3000);
  end
  else if CurUninstallStep = usPostUninstall then
  begin
    TerminateAppProcesses;
    Sleep(500);
    ForceRemoveInstallDir;
    CleanupLaunchAtStartup;
  end;
end;
