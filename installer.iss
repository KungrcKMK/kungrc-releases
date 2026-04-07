; ============================================================
;  KungRC EA — Inno Setup Installer Script
;  สร้าง installer: ISCC.exe installer.iss
; ============================================================

#define AppName    "KungRC EA"
#define AppVersion "1.0.75"
#define AppPublisher "Team Moon Mission Control"
#define AppExe     "KungRC_EA.exe"
#define DistDir    "dist\KungRC_EA"

[Setup]
AppId={{B2F4C1A0-7E3D-4F8B-9C2A-1D5E6F7A8B9C}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisherURL=
AppSupportURL=
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\KungRC_EA
DefaultGroupName={#AppName}
OutputDir=dist
OutputBaseFilename=KungRC_EA_install
SetupIconFile=kungrc.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
InfoAfterFile=CHANGELOG.txt
LicenseFile=
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#DistDir}\*";          DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "version.txt";           DestDir: "{app}"; Flags: ignoreversion
Source: "build_date.txt";       DestDir: "{app}"; Flags: ignoreversion
Source: "mql_template_mt5.mq5"; DestDir: "{app}"; Flags: ignoreversion
; ── Default profiles → %APPDATA%\KungRC_EA\ (ไม่ทับถ้ามีอยู่แล้ว) ──
Source: "aggressive.json";   DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist
Source: "balanced.json";     DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist
Source: "conservative.json"; DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist
Source: "turbo.json";        DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion
Source: "sniper.json";       DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist
Source: "custom.json";       DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist
Source: "session.json";      DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion
Source: "settings.json";     DestDir: "{userappdata}\KungRC_EA"; Flags: ignoreversion onlyifdoesntexist

[Icons]
Name: "{group}\{#AppName}";         Filename: "{app}\{#AppExe}"; IconFilename: "{app}\{#AppExe}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; IconFilename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
