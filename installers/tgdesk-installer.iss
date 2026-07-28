; TGDesk 0.3.17 — instalador universal Client + Tech + Admin.
; O modo Tech não é uma variante de build: ele é ativado por uma chave de
; uso único validada pelo servidor dentro do próprio TGDesk.

#define MyAppName "TGDesk"
#define MyAppVersion "0.3.22"
#define MyAppPublisher "TGDesk"

[Setup]
AppId={{A582695B-1F46-4D8D-A434-9B0D2F42D6A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TGDesk
DefaultGroupName=TGDesk
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=.\output
OutputBaseFilename=tgdesk-installer-0.3.22
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\tgdesk.exe
SetupIconFile=..\branding\app_icon.ico
WizardSmallImageFile=..\branding\wizard_small.bmp
CloseApplications=no
RestartApplications=no
AlwaysRestart=yes

[Dirs]
Name: "{commonappdata}\TGDesk"
Name: "{commonappdata}\TGDesk\identity"; Permissions: users-modify
Name: "{commonappdata}\TGDesk\state"; Permissions: users-modify
Name: "{commonappdata}\TGDesk\logs"; Permissions: users-modify
Name: "{commonappdata}\TGDesk\updates"; Permissions: users-modify
Name: "{commonappdata}\TGDesk\updates\staging"; Permissions: users-modify
Name: "{commonappdata}\TGDesk\updates\rollback"; Permissions: users-modify

[InstallDelete]
; Hard cut dos pacotes 0.2.x. ProgramData é zerado apenas nesta migração;
; os updates 0.3.x posteriores preservam identity/.
Type: filesandordirs; Name: "{localappdata}\TGDeskAgent"
Type: filesandordirs; Name: "{localappdata}\TGDesk"
Type: filesandordirs; Name: "{userappdata}\RustDesk"
Type: filesandordirs; Name: "{localappdata}\RustDesk"
Type: filesandordirs; Name: "{commonappdata}\RustDesk"
Type: filesandordirs; Name: "{commonappdata}\WireGuard\Configurations\tgdesk*"
Type: files; Name: "{app}\tgdesk-agent.exe"
Type: files; Name: "{app}\tgdesk-agent-2.exe"
Type: files; Name: "{app}\tgdesk-host.exe"
Type: files; Name: "{app}\tgdesk-tunnel.exe"
Type: files; Name: "{app}\rustdesk.exe"
Type: files; Name: "{app}\tgdesk_mode_tech.marker"
Type: files; Name: "{app}\wintun.dll"
Type: files; Name: "{commonstartup}\TGDesk.lnk"
Type: files; Name: "{commonstartup}\TGDesk Tray.lnk"
Type: files; Name: "{userstartup}\TGDesk.lnk"
Type: files; Name: "{userstartup}\TGDesk Tray.lnk"

[Files]
Source: "stage-unified\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{group}\TGDesk"; Filename: "{app}\tgdesk.exe"
Name: "{group}\Desinstalar TGDesk"; Filename: "{uninstallexe}"
Name: "{autodesktop}\TGDesk"; Filename: "{app}\tgdesk.exe"

[Registry]
; Remove autostarts usados pelas arquiteturas 0.1/0.2.
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "TGDeskHostAgent"; Flags: deletevalue
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "TGDeskClient"; Flags: deletevalue
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "TGDesk"; ValueData: """{app}\tgdesk.exe"""; Check: ShouldInitializeAutoStart; Flags: uninsdeletevalue
Root: HKCU; Subkey: "SOFTWARE\TGDesk"; ValueType: dword; ValueName: "StartWithWindowsConfigured"; ValueData: "1"; Check: ShouldInitializeAutoStart
Root: HKCU; Subkey: "SOFTWARE\TGDesk"; ValueType: dword; ValueName: "StartWithWindows"; ValueData: "1"; Check: ShouldInitializeAutoStart

[Code]
const
  ControlInstallUrl =
    'http://168.232.199.161:8090/api/v1/auth/control-key/install';

var
  PreserveIdentityPage: TInputOptionWizardPage;
  HasControlKeyPage: TInputOptionWizardPage;
  ControlKeyFilePage: TInputFileWizardPage;
  EnrollmentResponse: string;
  ExistingControlIdentity: Boolean;
  ControlKeyParam: string;
  CleanupProgressPage: TOutputProgressWizardPage;

procedure InitializeWizard;
begin
  ExistingControlIdentity :=
    FileExists(ExpandConstant('{commonappdata}\TGDesk\identity\device.json')) or
    FileExists(ExpandConstant('{commonappdata}\TGDesk\identity\technician.dat'));
  PreserveIdentityPage := CreateInputOptionPage(wpWelcome,
    'Identidade deste computador', 'Deseja manter a identidade TGDesk existente?',
    'Recomendado para atualizações e reparações. Mantém Admin/Tech, dispositivo e vínculo com a rede.',
    True, False);
  PreserveIdentityPage.Add('Sim — preservar identidade e vínculo (recomendado)');
  PreserveIdentityPage.Add('Não — apagar a identidade e instalar como novo computador');
  PreserveIdentityPage.SelectedValueIndex := 0;

  HasControlKeyPage := CreateInputOptionPage(PreserveIdentityPage.ID,
    'Controle do TGDesk', 'Possui chave de controle?',
    'Sem uma chave válida este computador será instalado no modo Client.',
    True, False);
  HasControlKeyPage.Add('Não (instalar como Client)');
  HasControlKeyPage.Add('Sim (Admin ou Tech)');
  HasControlKeyPage.SelectedValueIndex := 0;
  ControlKeyFilePage := CreateInputFilePage(HasControlKeyPage.ID,
    'Chave de controle', 'Selecione o arquivo .tgdesk-key',
    'A chave será validada e consumida agora. Ela não será copiada para o computador.');
  ControlKeyFilePage.Add('Arquivo:', 'Arquivos TGDesk|*.tgdesk-key|Todos os arquivos|*.*', '.tgdesk-key');
  ControlKeyParam := ExpandConstant('{param:CONTROLKEY|}');
  if (ControlKeyParam <> '') and FileExists(ControlKeyParam) then
  begin
    HasControlKeyPage.SelectedValueIndex := 1;
    ControlKeyFilePage.Values[0] := ControlKeyParam;
  end;
  CleanupProgressPage := CreateOutputProgressPage(
    'Removendo versões anteriores',
    'Limpando serviços, drivers, registros e arquivos antigos do TGDesk.');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ExistingControlIdentity and
      (PreserveIdentityPage.SelectedValueIndex = 0) and
      ((PageID = HasControlKeyPage.ID) or (PageID = ControlKeyFilePage.ID));
  if not Result then
    Result := (PageID = ControlKeyFilePage.ID) and
      (HasControlKeyPage.SelectedValueIndex = 0);
end;

function ShouldInitializeAutoStart: Boolean;
var
  Configured: Cardinal;
begin
  if not (ExistingControlIdentity and
      (PreserveIdentityPage.SelectedValueIndex = 0)) then
    Result := True
  else
    Result := not RegQueryDWordValue(
      HKCU, 'SOFTWARE\TGDesk', 'StartWithWindowsConfigured', Configured);
end;

function JsonEscape(Value: string): string;
begin
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  StringChangeEx(Value, #13, '', True);
  StringChangeEx(Value, #10, '', True);
  Result := Value;
end;

function GetMachineFingerprint: string;
var
  MachineGuid, ResultCodeString: string;
  HardwareInfo: AnsiString;
  ResultCode: Integer;
  TempPath, CommandLine: string;
begin
  RegQueryStringValue(HKLM64, 'SOFTWARE\Microsoft\Cryptography',
    'MachineGuid', MachineGuid);
  TempPath := ExpandConstant('{tmp}\tgdesk-hardware.txt');
  CommandLine :=
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    '$u=(Get-CimInstance Win32_ComputerSystemProduct).UUID;' +
    '$b=(Get-CimInstance Win32_BIOS).SerialNumber;' +
    'Set-Content -LiteralPath ''' + TempPath + ''' -Value ($u+''|''+$b) -NoNewline"';
  if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      CommandLine, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
      (ResultCode = 0) then
    LoadStringFromFile(TempPath, HardwareInfo);
  ResultCodeString := MachineGuid + '|' + string(HardwareInfo);
  if ResultCodeString = '|' then
    ResultCodeString := GetComputerNameString;
  Result := ResultCodeString;
end;

function ConsumeControlKey: Boolean;
var
  RequestJson, ResponseText: string;
  KeyJson: AnsiString;
  Http: Variant;
begin
  Result := False;
  if (ControlKeyFilePage.Values[0] = '') or
      not FileExists(ControlKeyFilePage.Values[0]) then
  begin
    MsgBox('Selecione um arquivo .tgdesk-key válido.', mbError, MB_OK);
    exit;
  end;
  if not LoadStringFromFile(ControlKeyFilePage.Values[0], KeyJson) then
  begin
    MsgBox('Não foi possível ler a chave.', mbError, MB_OK);
    exit;
  end;
  RequestJson := '{"key":' + string(KeyJson) + ',"machine_id":"' +
    JsonEscape(GetMachineFingerprint) + '"}';
  try
    Http := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Http.SetTimeouts(5000, 5000, 10000, 10000);
    Http.Open('POST', ControlInstallUrl, False);
    Http.SetRequestHeader('Content-Type', 'application/json');
    Http.Send(RequestJson);
    ResponseText := Http.ResponseText;
    if Http.Status <> 200 then
    begin
      MsgBox('A chave foi recusada pelo servidor.' + #13#10 + ResponseText,
        mbError, MB_OK);
      exit;
    end;
    EnrollmentResponse := ResponseText;
    Result := True;
  except
    MsgBox('Não foi possível validar a chave no servidor. Verifique a conexão.',
      mbError, MB_OK);
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = ControlKeyFilePage.ID) and
      (HasControlKeyPage.SelectedValueIndex = 1) then
  begin
    if (ControlKeyFilePage.Values[0] = '') or
        not FileExists(ControlKeyFilePage.Values[0]) then
    begin
      MsgBox('Selecione um arquivo .tgdesk-key válido.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure StopLegacyTGDesk;
var
  ResultCode: Integer;
begin
  { Desativa primeiro a recuperação automática. Nas versões anteriores o
    taskkill disparava o restart/5000 do serviço antigo durante a remoção do
    Wintun, deixando o driver em uso e preso em STATUS_WAIT_2. }
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    '$names=@(''TGDesk'',''TGDeskService'',''TGDeskHost'');' +
    'foreach($n in $names){' +
    'sc.exe failure $n reset= 0 actions= '''' | Out-Null;' +
    'sc.exe config $n start= disabled | Out-Null;' +
    'Stop-Service -Name $n -Force -ErrorAction SilentlyContinue};' +
    'Start-Sleep -Seconds 2;' +
    'Get-Process -Name tgdesk,tgdesk-agent,tgdesk-agent-2,tgdesk-host,tgdesk-tunnel ' +
    '-ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue;' +
    'Start-Sleep -Seconds 2;' +
    'foreach($n in $names){sc.exe delete $n | Out-Null}"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'),
    '/C taskkill /F /IM tgdesk-agent.exe >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'),
    '/C taskkill /F /IM tgdesk-agent-2.exe >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'),
    '/C taskkill /F /IM tgdesk-host.exe >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'),
    '/C taskkill /F /IM tgdesk-tunnel.exe >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);

  Exec(ExpandConstant('{cmd}'),
    '/C sc stop RustDesk >nul 2>&1 & sc delete RustDesk >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{cmd}'),
    '/C sc stop "WireGuardTunnel$TGDesk" >nul 2>&1 & sc delete "WireGuardTunnel$TGDesk" >nul 2>&1', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    'Get-Service -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Name -match ''^(WireGuard|WireGuardTunnel)'' } | ' +
    'ForEach-Object { Stop-Service -Name $_.Name -Force -ErrorAction SilentlyContinue; ' +
    'sc.exe delete $_.Name | Out-Null }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -Command "Get-NetAdapter -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Name -match ''^(TGDesk|WireGuard|Wintun)'' } | ' +
    'Disable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  { Remove dispositivos Wintun órfãos. Apenas desabilitá-los mantém a entrada
    SWD\WINTUN e faz CreateTUN bloquear indefinidamente no próximo serviço. }
  Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    'Get-PnpDevice -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.InstanceId -like ''SWD\WINTUN\*'' } | ' +
    'ForEach-Object { & pnputil.exe /remove-device $_.InstanceId /subtree /force | Out-Null };' +
    'sc.exe stop wintun | Out-Null; sc.exe delete wintun | Out-Null;' +
    'Get-ScheduledTask -ErrorAction SilentlyContinue | ' +
    'Where-Object { ($_.TaskName+$_.TaskPath) -match ''TGDesk|RustDesk|WireGuard'' } | ' +
    'Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue;' +
    'Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | ' +
    'Where-Object { -not $_.Special -and $_.LocalPath } | ForEach-Object {' +
    '$p=$_.LocalPath;' +
    '@(''$p\AppData\Roaming\TGDesk'',''$p\AppData\Local\TGDesk'',' +
    '''$p\AppData\Local\TGDeskAgent'',''$p\AppData\Roaming\RustDesk'',' +
    '''$p\AppData\Local\RustDesk'') | ForEach-Object {' +
    '$x=$ExecutionContext.InvokeCommand.ExpandString($_);' +
    'Remove-Item -LiteralPath $x -Recurse -Force -ErrorAction SilentlyContinue }}"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\RustDesk');
  RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\WireGuard');
  RegDeleteKeyIncludingSubkeys(HKLM64, 'SOFTWARE\RustDesk');
  RegDeleteKeyIncludingSubkeys(HKLM64, 'SOFTWARE\WireGuard');
  RegDeleteKeyIncludingSubkeys(HKLM32, 'SOFTWARE\RustDesk');
  RegDeleteKeyIncludingSubkeys(HKLM32, 'SOFTWARE\WireGuard');
  DeleteFile(ExpandConstant('{sys}\drivers\wintun.sys'));
end;

procedure RemoveLegacyUninstallEntries;
begin
  RegDeleteKeyIncludingSubkeys(HKLM64,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8F1B1E2A-7C3D-4B2E-9A1F-TGDESK-CLIENT}_is1');
  RegDeleteKeyIncludingSubkeys(HKLM64,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3D2C9F41-6A8B-4E7C-BF2D-TGDESK-TECH}_is1');
  RegDeleteKeyIncludingSubkeys(HKLM32,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{8F1B1E2A-7C3D-4B2E-9A1F-TGDESK-CLIENT}_is1');
  RegDeleteKeyIncludingSubkeys(HKLM32,
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{3D2C9F41-6A8B-4E7C-BF2D-TGDESK-TECH}_is1');
end;

function PrepareToInstall(var NeedsRestart: Boolean): string;
begin
  Result := '';
  CleanupProgressPage.SetText(
    'Removendo instalações anteriores...',
    'TGDesk, RustDesk, WireGuard, serviços, drivers, registros, AppData e ProgramData.');
  CleanupProgressPage.SetProgress(0, 3);
  CleanupProgressPage.Show;
  try
    StopLegacyTGDesk;
    CleanupProgressPage.SetProgress(1, 3);
    RemoveLegacyUninstallEntries;
    if ExistingControlIdentity and
        (PreserveIdentityPage.SelectedValueIndex = 0) then
    begin
      DelTree(ExpandConstant('{commonappdata}\TGDesk\state'), True, True, True);
      DelTree(ExpandConstant('{commonappdata}\TGDesk\logs'), True, True, True);
      DelTree(ExpandConstant('{commonappdata}\TGDesk\updates'), True, True, True);
    end
    else
    begin
      DelTree(ExpandConstant('{commonappdata}\TGDesk'), True, True, True);
      RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\TGDesk');
      RegDeleteKeyIncludingSubkeys(HKLM64, 'SOFTWARE\TGDesk');
      RegDeleteKeyIncludingSubkeys(HKLM32, 'SOFTWARE\TGDesk');
    end;
    DelTree(ExpandConstant('{app}'), True, True, True);
    DelTree(ExpandConstant('{autopf}\RustDesk'), True, True, True);
    DelTree(ExpandConstant('{autopf}\WireGuard'), True, True, True);
    DelTree(ExpandConstant('{pf32}\RustDesk'), True, True, True);
    DelTree(ExpandConstant('{pf32}\WireGuard'), True, True, True);
    DelTree(ExpandConstant('{commonappdata}\RustDesk'), True, True, True);
    DelTree(ExpandConstant('{commonappdata}\WireGuard'), True, True, True);
    CleanupProgressPage.SetProgress(3, 3);
  finally
    CleanupProgressPage.Hide;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PendingPath, ProtectedPath, ProtectCommand, ServiceCommand: string;
begin
  if CurStep = ssInstall then
  begin
    WizardForm.StatusLabel.Caption :=
      'Validando e vinculando a chave ao servidor...';
    if not (ExistingControlIdentity and
        (PreserveIdentityPage.SelectedValueIndex = 0)) and
        (HasControlKeyPage.SelectedValueIndex = 1) and
        (EnrollmentResponse = '') and not ConsumeControlKey then
      RaiseException(
        'A instalação foi cancelada porque a chave de controle não pôde ser validada.');
  end;
  if CurStep = ssPostInstall then
  begin
    if EnrollmentResponse <> '' then
    begin
      PendingPath := ExpandConstant(
        '{commonappdata}\TGDesk\identity\pending-enrollment.json');
      ProtectedPath := ExpandConstant(
        '{commonappdata}\TGDesk\identity\technician.dat');
      SaveStringToFile(ExpandConstant(
        '{commonappdata}\TGDesk\identity\pending-enrollment.json'),
        EnrollmentResponse, False);
      ProtectCommand :=
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
        '$ErrorActionPreference=''Stop'';' +
        'Add-Type -AssemblyName System.Security;' +
        '$j=Get-Content -LiteralPath ''' + PendingPath + ''' -Raw|ConvertFrom-Json;' +
        '$o=@{credential_id=$j.credential_id;secret=$j.secret;machine_id=$j.machine_id}|ConvertTo-Json -Compress;' +
        '$b=[Text.Encoding]::UTF8.GetBytes($o);' +
        '$e=[Security.Cryptography.ProtectedData]::Protect($b,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine);' +
        '[IO.File]::WriteAllBytes(''' + ProtectedPath + ''',$e);' +
        'Remove-Item -LiteralPath ''' + PendingPath + ''' -Force"';
      if not Exec(ExpandConstant(
          '{sys}\WindowsPowerShell\v1.0\powershell.exe'),
          ProtectCommand, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) or
          (ResultCode <> 0) or not FileExists(ProtectedPath) then
        RaiseException(
          'Falha ao proteger a identidade Admin/Tech. O serviço não será iniciado.');
    end;
    SaveStringToFile(ExpandConstant(
      '{commonappdata}\TGDesk\layout-0.3.marker'), '0.3', False);

    { Cria o serviço diretamente. O antigo --install-service também abria o
      tray antes da página final do instalador. }
    ServiceCommand :=
      '/C sc.exe create TGDesk binPath= "\"' + ExpandConstant('{app}\tgdesk.exe') +
      '\" --service" start= auto DisplayName= "TGDesk Service" >nul 2>&1' +
      ' & sc.exe failure TGDesk reset= 60 actions= restart/5000 >nul 2>&1';
    if not Exec(ExpandConstant('{cmd}'), ServiceCommand, '', SW_HIDE,
        ewWaitUntilTerminated, ResultCode) or (ResultCode <> 0) then
      RaiseException('Falha ao instalar ou iniciar o serviço TGDesk.');
    { Atualização automática silenciosa: o instalador foi chamado pelo
      próprio TGDesk com /NORESTART. Reinicia somente serviço e interface;
      a instalação interativa continua aguardando o reboot final. }
    if WizardSilent then
    begin
      Exec(ExpandConstant('{cmd}'), '/C sc.exe start TGDesk >nul 2>&1',
        '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
      ExecAsOriginalUser(ExpandConstant('{app}\tgdesk.exe'), '',
        ExpandConstant('{app}'), SW_SHOWNORMAL, ewNoWait, ResultCode);
    end;
  end;
end;

[UninstallRun]
Filename: "{app}\tgdesk.exe"; Parameters: "--uninstall-service"; RunOnceId: "TGDeskService"; Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{commonappdata}\TGDesk"
