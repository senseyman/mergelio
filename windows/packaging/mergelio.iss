; Inno Setup script for Mergelio.
;
; Not built by hand — scripts/build-windows.ps1 supplies the values below with
; /D switches and runs ISCC. Compile it directly only for a smoke test:
;
;   ISCC.exe /DAppVersion=1.4.0 /DAppArch=x64 ^
;            /DSourceDir=..\..\build\windows\x64\runner\Release ^
;            /DOutputDir=..\..\dist windows\packaging\mergelio.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppArch
  #define AppArch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#ifndef AppName
  #define AppName "Mergelio"
#endif
#define AppExe "mergelio.exe"
#define AppPublisher "Neo"
#define AppUrl "https://github.com/senseyman/mergelio"

[Setup]
; Never change AppId: it is how Windows recognises an existing install and
; upgrades it in place instead of stacking a second copy.
AppId={{625A1A4C-4114-431C-AB59-CF6DED3EF051}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases
VersionInfoVersion={#AppVersion}

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename={#AppName}-{#AppVersion}-windows-{#AppArch}-setup

; The icon on setup.exe itself, on the Start menu and desktop shortcuts, and
; in Apps & Features. The one compiled into mergelio.exe comes from
; windows/runner/Runner.rc, which is a separate mechanism.
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}

Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

; Defaults to a per-machine install under Program Files; the user can choose a
; per-user install instead, which needs no administrator rights.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

#if AppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
#endif

; Offer to close a running copy rather than failing on a locked mergelio.exe.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release directory: the exe, flutter_windows.dll, the
; plugin DLLs and data\. Missing any of them and the app will not start.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
