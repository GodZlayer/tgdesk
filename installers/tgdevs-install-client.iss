; TGDesk Client (Host) — instalador silencioso, estilo AnyDesk.
; Instala o núcleo TGDesk (RustDesk + Hub, mesmo binário) e o agente Go que
; cuida de registro/pareamento/túnel WireGuard como device Host. Sem ícones
; de desktop — a máquina do cliente final não deve expor nada além do
; necessário (Seção 6 do plano de arquitetura).

#define MyAppName "TGDesk Client"
#define MyAppVersion "0.2.4"
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
; Atualização: encerra somente o agente legado. A identidade permanece nos
; arquivos JSON e será reutilizada pelo agente versionado novo.
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM tgdesk-agent.exe >nul 2>&1"; Flags: runhidden waituntilterminated
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM tgdesk-agent-2.exe >nul 2>&1"; Flags: runhidden waituntilterminated
Filename: "{app}\tgdesk.exe"; Description: "Iniciar TGDesk agora"; Flags: nowait postinstall

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    { O instalador já está elevado neste ponto. Encerra todas as instâncias
      do núcleo, bandeja e agente antes de substituir qualquer binário. }
    Exec(ExpandConstant('{cmd}'),
      '/C taskkill /F /IM tgdesk.exe >nul 2>&1',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Exec(ExpandConstant('{cmd}'),
      '/C taskkill /F /IM tgdesk-agent-2.exe >nul 2>&1',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(800);
  end;
end;

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
