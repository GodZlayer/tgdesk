; TGDesk Client (Host) — instalador silencioso, estilo AnyDesk.
; Instala o núcleo TGDesk (RustDesk + Hub, mesmo binário) e o agente Go que
; cuida de registro/pareamento/túnel WireGuard como device Host. Sem ícones
; de desktop — a máquina do cliente final não deve expor nada além do
; necessário (Seção 6 do plano de arquitetura).

#define MyAppName "TGDesk Client"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "TGDesk"

[Setup]
AppId={{8F1B1E2A-7C3D-4B2E-9A1F-TGDESK-CLIENT}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TGDesk Client
DefaultGroupName=TGDesk Client
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=admin
OutputDir=.\output
OutputBaseFilename=tgdevs-install-client
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\tgdesk.exe
SetupIconFile=..\branding\app_icon.ico
WizardSmallImageFile=..\branding\wizard_small.bmp

[Files]
Source: "stage-client\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
; Sem atalho de Desktop/Menu Iniciar de propósito — só entradas de
; desinstalação e inicialização automática.
Name: "{group}\Desinstalar TGDesk Client"; Filename: "{uninstallexe}"
; Só o tgdesk.exe no autostart — ele extrai e inicia o agente embutido
; (%LOCALAPPDATA%\TGDesk). Não existe mais tgdesk-agent.exe solto na pasta.
Name: "{commonstartup}\TGDesk Core"; Filename: "{app}\tgdesk.exe"

[Run]
Filename: "{app}\tgdesk.exe"; Description: "Iniciar TGDesk agora"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
