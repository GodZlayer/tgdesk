; TGDesk Técnico — instalador do Hub (Admin/Técnico). Mesmo núcleo do
; TGDesk Client (tgdesk.exe), mas empacotado com o agente de túnel WireGuard
; do TÉCNICO (identidade de rede própria, ver ARCHITECTURE_FLOW.md) e com
; atalhos visíveis, já que aqui o usuário é quem opera o painel.

#define MyAppName "TGDesk Tecnico"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "TGDesk"

[Setup]
AppId={{3D2C9F41-6A8B-4E7C-BF2D-TGDESK-TECH}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TGDesk Tecnico
DefaultGroupName=TGDesk Tecnico
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=.\output
OutputBaseFilename=tgdevs-install-tech
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\tgdesk.exe
SetupIconFile=..\branding\app_icon.ico
WizardSmallImageFile=..\branding\wizard_small.bmp

[Files]
Source: "stage-tech\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\TGDesk Tecnico"; Filename: "{app}\tgdesk.exe"
Name: "{group}\Desinstalar TGDesk Tecnico"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TGDesk Tecnico"; Filename: "{app}\tgdesk.exe"

[Run]
Filename: "{app}\tgdesk.exe"; Description: "Iniciar TGDesk Tecnico agora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
