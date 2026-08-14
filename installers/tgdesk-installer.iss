; TGDesk 0.3.17 — instalador universal Client + Tech + Admin.
; O modo Tech não é uma variante de build: ele é ativado por uma chave de
; uso único validada pelo servidor dentro do próprio TGDesk.

#define MyAppName "TGDesk"
#define MyAppVersion "1.2.78"
#define MyAppPublisher "TGDesk"
#ifndef TGDeskServerHost
  #define TGDeskServerHost "127.0.0.1"
#endif

[Setup]
AppId={{A582695B-1F46-4D8D-A434-9B0D2F42D6A8}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\TGDesk
; AppName fica fixo de proposito: ele nomeia as janelas do proprio wizard, que
; sao montadas antes de o tecnico ter sido escolhido. O que o usuario ve depois
; de instalar — grupo do menu, atalhos, icones e Programas e Recursos — usa
; {code:} e resolve com a marca ja baixada.
DefaultGroupName={code:BrandDisplayName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=.\output
; Literal de proposito, e nao {#MyAppVersion}: Publish-TGDeskRelease.ps1 confere
; esta linha por texto exato para garantir que o instalador esta identificado
; com a versao publicada. Derivar aqui apagaria essa verificacao. As duas
; versoes deste arquivo sobem juntas, no passo 1 do fluxo de release.
OutputBaseFilename=tgdesk-installer-1.2.78
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={code:BrandIconFile}
UninstallDisplayName={code:BrandDisplayName}
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
Type: files; Name: "{app}\tgdesk-tech.exe"
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
Name: "{group}\{code:BrandDisplayName}"; Filename: "{app}\tgdesk.exe"; IconFilename: "{code:BrandIconFile}"
Name: "{group}\Desinstalar {code:BrandDisplayName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{code:BrandDisplayName}"; Filename: "{app}\tgdesk.exe"; IconFilename: "{code:BrandIconFile}"

[Registry]
; Remove autostarts usados pelas arquiteturas 0.1/0.2.
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "TGDeskHostAgent"; Flags: deletevalue
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "TGDeskClient"; Flags: deletevalue
Root: HKCU; Subkey: "SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "TGDesk"; ValueData: """{app}\tgdesk.exe"" --minimized"; Check: ShouldInitializeAutoStart; Flags: uninsdeletevalue
Root: HKCU; Subkey: "SOFTWARE\TGDesk"; ValueType: dword; ValueName: "StartWithWindowsConfigured"; ValueData: "1"; Check: ShouldInitializeAutoStart
Root: HKCU; Subkey: "SOFTWARE\TGDesk"; ValueType: dword; ValueName: "StartWithWindows"; ValueData: "1"; Check: ShouldInitializeAutoStart

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""$a=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ''''{app}\tgdesk-recovery.ps1''''';Register-ScheduledTask -TaskName 'TGDesk Update Recovery' -Action $a -Trigger (New-ScheduledTaskTrigger -AtStartup) -User 'SYSTEM' -RunLevel Highest -Force"""; Flags: runhidden waituntilterminated

[Code]
{ O instalador resolve o destino da máquina antes de instalar: quem é técnico
  entrega a chave, quem é cliente escolhe entre a empresa dele e o atendimento
  avulso. Com isso a tela de bifurcação do primeiro início do TGDesk deixa de
  existir — a pergunta já foi respondida aqui.

  A identidade do técnico só é substituída quando isso é decidido de fato, e a
  chave, que é de uso único, só é consumida depois da remoção da instalação
  anterior ter dado certo: queimá-la antes deixaria o técnico sem chave e sem
  instalação se a remoção falhasse. }

const
  ServerBaseUrl = 'http://{#TGDeskServerHost}:8090';
  ControlInstallUrl = 'http://{#TGDeskServerHost}:8090/api/v1/auth/control-key/install';
  ControlValidateUrl = 'http://{#TGDeskServerHost}:8090/api/v1/auth/control-key/validate';
  TechnicianSearchUrl = 'http://{#TGDeskServerHost}:8090/api/v1/public/technicians/search?q=';
  MinSearchLength = 3;

var
  InstallTypePage: TInputOptionWizardPage;
  OverwriteIdentityPage: TInputOptionWizardPage;
  ControlKeyFilePage: TInputFileWizardPage;
  ClientKindPage: TInputOptionWizardPage;
  TechnicianPage: TWizardPage;
  TechnicianSearchEdit: TNewEdit;
  TechnicianSearchButton: TNewButton;
  TechnicianList: TNewListBox;
  TechnicianIDs: TStringList;
  SelectedTechnicianID: string;
  SelectedTechnicianName: string;
  BrandingPayload: string;
  BrandIconWritten: Boolean;
  EnrollmentResponse: string;
  ExistingControlIdentity: Boolean;
  ControlKeyParam: string;
  CleanupProgressPage: TOutputProgressWizardPage;

{ O icone da marca mora no mesmo arquivo que o agente mantem atualizado
  depois (syncBrandFavicon, em client-agent/cmd/agent/status.go). Assim o
  atalho e a bandeja nunca divergem: quem instala escreve, quem roda renova. }
function BrandIconPath: string;
begin
  Result := ExpandConstant('{commonappdata}\TGDesk\branding\favicon.ico');
end;

{ Chamadas pelo motor do Inno, inclusive antes de o wizard existir — dai as
  guardas contra pagina nula. Sem marca escolhida, tudo cai no padrao TGDesk. }
function BrandBaseName: string;
var
  Index: Integer;
  Clean: string;
begin
  Result := 'TGDesk';
  if SelectedTechnicianName = '' then
    exit;
  { O nome vira arquivo .lnk e nome de pasta do menu Iniciar. Caractere
    proibido em caminho faria a criacao do atalho falhar e derrubaria a
    instalacao inteira por causa de um nome cadastrado no servidor.
    Espacos e pontuacao neutra saem para formar o padrao MarcaDesk/MarcaAssist. }
  Clean := '';
  for Index := 1 to Length(SelectedTechnicianName) do
    if Pos(SelectedTechnicianName[Index], '\/:*?"<>| -_.') = 0 then
      Clean := Clean + SelectedTechnicianName[Index];
  Clean := Trim(Clean);
  if Length(Clean) > 48 then
    Clean := Trim(Copy(Clean, 1, 48));
  if Clean <> '' then
    Result := Clean;
end;

function BrandDisplayName(Param: string): string;
begin
  Result := BrandBaseName;
end;

function BrandIconFile(Param: string): string;
begin
  if BrandIconWritten then
    Result := BrandIconPath
  else
    Result := ExpandConstant('{app}\tgdesk.exe');
end;

function IsTechnicianInstall: Boolean;
begin
  Result := InstallTypePage.SelectedValueIndex = 1;
end;

{ A identidade de controle existente é preservada só quando o usuário disse
  que este continua sendo o mesmo computador de técnico. Escolher "Cliente"
  já é, por si, a decisão de descartá-la. }
function ReplacesIdentity: Boolean;
begin
  Result := (not ExistingControlIdentity) or (not IsTechnicianInstall) or
    (OverwriteIdentityPage.SelectedValueIndex = 1);
end;

function IsCorporateClient: Boolean;
begin
  Result := (not IsTechnicianInstall) and (ClientKindPage.SelectedValueIndex = 0);
end;

function HttpGetText(Url: string; var Body: string): Boolean;
var
  Http: Variant;
begin
  Result := False;
  try
    Http := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Http.SetTimeouts(5000, 5000, 10000, 15000);
    Http.Open('GET', Url, False);
    Http.Send('');
    Body := Http.ResponseText;
    Result := Http.Status = 200;
  except
    Body := '';
  end;
end;

{ Extração pontual de campo de JSON. O instalador consome duas respostas de
  formato conhecido e fixo; embutir um parser completo aqui seria peso morto. }
function JsonStringAfter(Source: string; var Cursor: Integer; Field: string): string;
var
  Marker: string;
  Start, Stop: Integer;
begin
  Result := '';
  Marker := '"' + Field + '":"';
  Start := Pos(Marker, Copy(Source, Cursor, Length(Source)));
  if Start = 0 then
    exit;
  Start := Cursor + Start - 1 + Length(Marker);
  Stop := Start;
  while (Stop <= Length(Source)) and (Source[Stop] <> '"') do
    Stop := Stop + 1;
  Result := Copy(Source, Start, Stop - Start);
  Cursor := Stop;
end;

{ Nome de tecnico tem espaco e acento, e os dois quebram a query string se
  forem enviados crus. A conversao para UTF-8 e feita a mao de proposito: um
  cast para AnsiString usaria a codepage do Windows, e o servidor leria os
  acentos errados. }
function PercentByte(Value: Integer): string;
begin
  Result := Format('%%%.2x', [Value]);
end;

function UrlEncode(Value: string): string;
var
  Index, Code: Integer;
begin
  Result := '';
  for Index := 1 to Length(Value) do
  begin
    Code := Ord(Value[Index]);
    if ((Code >= 48) and (Code <= 57)) or ((Code >= 65) and (Code <= 90)) or
        ((Code >= 97) and (Code <= 122)) or (Code = 45) or (Code = 46) or
        (Code = 95) or (Code = 126) then
      Result := Result + Chr(Code)
    else if Code < $80 then
      Result := Result + PercentByte(Code)
    else if Code < $800 then
      Result := Result + PercentByte($C0 or (Code shr 6)) +
        PercentByte($80 or (Code and $3F))
    else
      Result := Result + PercentByte($E0 or (Code shr 12)) +
        PercentByte($80 or ((Code shr 6) and $3F)) +
        PercentByte($80 or (Code and $3F));
  end;
end;

procedure SearchTechnicians(Sender: TObject);
var
  Query, Body, TechID, TechName: string;
  Cursor: Integer;
begin
  Query := Trim(TechnicianSearchEdit.Text);
  if Length(Query) < MinSearchLength then
  begin
    MsgBox('Digite ao menos 3 letras do nome do técnico.', mbInformation, MB_OK);
    exit;
  end;
  TechnicianList.Items.Clear;
  TechnicianIDs.Clear;
  SelectedTechnicianID := '';
  if not HttpGetText(TechnicianSearchUrl + UrlEncode(Query), Body) then
  begin
    MsgBox('Não foi possível consultar o servidor. Verifique a conexão.',
      mbError, MB_OK);
    exit;
  end;
  Cursor := 1;
  repeat
    TechID := JsonStringAfter(Body, Cursor, 'id');
    if TechID = '' then
      break;
    TechName := JsonStringAfter(Body, Cursor, 'name');
    TechnicianIDs.Add(TechID);
    TechnicianList.Items.Add(TechName);
  until False;
  if TechnicianList.Items.Count = 0 then
    MsgBox('Nenhum técnico encontrado com esse nome.', mbInformation, MB_OK);
end;

procedure InitializeWizard;
begin
  ExistingControlIdentity :=
    FileExists(ExpandConstant('{commonappdata}\TGDesk\identity\technician.dat'));
  TechnicianIDs := TStringList.Create;

  InstallTypePage := CreateInputOptionPage(wpWelcome,
    'Tipo de instalação', 'Este computador é de um técnico ou de um cliente?',
    'Cliente recebe suporte. Técnico e Admin controlam, e precisam de uma chave.',
    True, False);
  InstallTypePage.Add('Cliente — recebe suporte');
  InstallTypePage.Add('Técnico ou Admin — tenho chave de controle');
  InstallTypePage.SelectedValueIndex := 0;

  OverwriteIdentityPage := CreateInputOptionPage(InstallTypePage.ID,
    'Identidade de controle', 'Este computador já tem uma identidade registrada.',
    'Manter é o caminho da atualização. Substituir exige uma nova chave.',
    True, False);
  OverwriteIdentityPage.Add('Manter a identidade atual');
  OverwriteIdentityPage.Add('Substituir por uma nova chave');
  OverwriteIdentityPage.SelectedValueIndex := 0;

  ControlKeyFilePage := CreateInputFilePage(OverwriteIdentityPage.ID,
    'Chave de controle', 'Selecione o arquivo .tgdesk-key',
    'A chave é conferida agora e consumida só depois da limpeza da instalação anterior.');
  ControlKeyFilePage.Add('Arquivo:', 'Arquivos TGDesk|*.tgdesk-key|Todos os arquivos|*.*', '.tgdesk-key');

  ClientKindPage := CreateInputOptionPage(ControlKeyFilePage.ID,
    'Como você usa o TGDesk', 'Este computador é atendido por uma empresa?',
    'A escolha define para onde este computador vai — e não precisa ser refeita depois.',
    True, False);
  ClientKindPage.Add('Minha empresa tem TGDesk');
  ClientKindPage.Add('Sou particular — atendimento TGDesk');
  ClientKindPage.SelectedValueIndex := 1;

  TechnicianPage := CreateCustomPage(ClientKindPage.ID,
    'Técnico responsável', 'Procure pelo nome do técnico que atende a sua empresa.');

  TechnicianSearchEdit := TNewEdit.Create(TechnicianPage);
  TechnicianSearchEdit.Parent := TechnicianPage.Surface;
  TechnicianSearchEdit.Left := 0;
  TechnicianSearchEdit.Top := 0;
  TechnicianSearchEdit.Width := TechnicianPage.SurfaceWidth - ScaleX(90);

  TechnicianSearchButton := TNewButton.Create(TechnicianPage);
  TechnicianSearchButton.Parent := TechnicianPage.Surface;
  TechnicianSearchButton.Left := TechnicianPage.SurfaceWidth - ScaleX(80);
  TechnicianSearchButton.Top := TechnicianSearchEdit.Top - ScaleY(1);
  TechnicianSearchButton.Width := ScaleX(80);
  TechnicianSearchButton.Height := TechnicianSearchEdit.Height + ScaleY(2);
  TechnicianSearchButton.Caption := 'Procurar';
  TechnicianSearchButton.OnClick := @SearchTechnicians;

  TechnicianList := TNewListBox.Create(TechnicianPage);
  TechnicianList.Parent := TechnicianPage.Surface;
  TechnicianList.Left := 0;
  TechnicianList.Top := TechnicianSearchEdit.Top + TechnicianSearchEdit.Height + ScaleY(10);
  TechnicianList.Width := TechnicianPage.SurfaceWidth;
  TechnicianList.Height := TechnicianPage.SurfaceHeight - TechnicianList.Top;

  ControlKeyParam := ExpandConstant('{param:CONTROLKEY|}');
  if (ControlKeyParam <> '') and FileExists(ControlKeyParam) then
  begin
    InstallTypePage.SelectedValueIndex := 1;
    OverwriteIdentityPage.SelectedValueIndex := 1;
    ControlKeyFilePage.Values[0] := ControlKeyParam;
  end;

  CleanupProgressPage := CreateOutputProgressPage(
    'Removendo versões anteriores',
    'Limpando serviços, drivers, registros e arquivos antigos do TGDesk.');
end;

procedure DeinitializeSetup;
begin
  { Roda mesmo quando o setup aborta antes de montar o wizard. }
  if TechnicianIDs <> nil then
    TechnicianIDs.Free;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = OverwriteIdentityPage.ID then
    Result := (not ExistingControlIdentity) or (not IsTechnicianInstall)
  else if PageID = ControlKeyFilePage.ID then
    Result := (not IsTechnicianInstall) or (not ReplacesIdentity)
  else if PageID = ClientKindPage.ID then
    Result := IsTechnicianInstall
  else if PageID = TechnicianPage.ID then
    Result := not IsCorporateClient;
end;

function ShouldInitializeAutoStart: Boolean;
var
  Configured: Cardinal;
begin
  if ReplacesIdentity then
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

{ Confere a chave sem gastá-la, para que um arquivo errado seja recusado aqui
  e não depois da máquina já ter sido limpa. }
function ValidateControlKey: Boolean;
var
  ResponseText, BrandName: string;
  KeyJson: AnsiString;
  Http: Variant;
  Cursor: Integer;
begin
  Result := False;
  if not LoadStringFromFile(ControlKeyFilePage.Values[0], KeyJson) then
  begin
    MsgBox('Não foi possível ler a chave.', mbError, MB_OK);
    exit;
  end;
  try
    Http := CreateOleObject('WinHttp.WinHttpRequest.5.1');
    Http.SetTimeouts(5000, 5000, 10000, 10000);
    Http.Open('POST', ControlValidateUrl, False);
    Http.SetRequestHeader('Content-Type', 'application/json');
    Http.Send('{"key":' + string(KeyJson) + '}');
    ResponseText := Http.ResponseText;
    if Http.Status <> 200 then
    begin
      MsgBox('A chave foi recusada pelo servidor.' + #13#10 + ResponseText,
        mbError, MB_OK);
      exit;
    end;
    { A resposta traz a marca do dono da chave. O computador do técnico ganha
      a marca dele pelo mesmo caminho que o do cliente — quem personaliza o
      atendimento personaliza a ferramenta inteira. }
    BrandingPayload := ResponseText;
    Cursor := 1;
    BrandName := JsonStringAfter(ResponseText, Cursor, 'name');
    if Trim(BrandName) <> '' then
      SelectedTechnicianName := BrandName;
    Result := True;
  except
    MsgBox('Não foi possível conferir a chave no servidor. Verifique a conexão.',
      mbError, MB_OK);
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Body, BrandName: string;
  Cursor: Integer;
begin
  Result := True;
  if (CurPageID = ControlKeyFilePage.ID) and IsTechnicianInstall and
      ReplacesIdentity then
  begin
    if (ControlKeyFilePage.Values[0] = '') or
        not FileExists(ControlKeyFilePage.Values[0]) then
    begin
      MsgBox('Selecione um arquivo .tgdesk-key válido.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    Result := ValidateControlKey;
  end
  else if CurPageID = TechnicianPage.ID then
  begin
    if TechnicianList.ItemIndex < 0 then
    begin
      MsgBox('Selecione o técnico que atende a sua empresa.', mbError, MB_OK);
      Result := False;
      exit;
    end;
    SelectedTechnicianID := TechnicianIDs.Strings[TechnicianList.ItemIndex];
    SelectedTechnicianName := TechnicianList.Items[TechnicianList.ItemIndex];
    { O branding vem do servidor porque o instalador é um binário único e
      assinado: recompilar por cliente criaria variantes sem reputação no
      SmartScreen. Falhar aqui não impede a instalação — o TGDesk busca o
      mesmo branding em runtime. }
    if HttpGetText(ServerBaseUrl + '/api/v1/public/technicians/' +
        SelectedTechnicianID + '/branding', Body) then
    begin
      BrandingPayload := Body;
      { O nome de aplicacao/atalho escolhido pelo supervisor ganha do nome
        tecnico. Se ele nao configurou composicao, usa a marca base. }
      Cursor := 1;
      BrandName := JsonStringAfter(Body, Cursor, 'shortcut_name');
      if Trim(BrandName) = '' then
      begin
        Cursor := 1;
        BrandName := JsonStringAfter(Body, Cursor, 'application_name');
      end;
      if Trim(BrandName) = '' then
      begin
        Cursor := 1;
        BrandName := JsonStringAfter(Body, Cursor, 'name');
      end;
      if Trim(BrandName) <> '' then
        SelectedTechnicianName := BrandName;
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
    '$names=@(Get-Service -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Name -match ''^TGDesk'' } | Select-Object -ExpandProperty Name);' +
    '$names += @(''TGDesk'',''TGDeskService'',''TGDeskHost'');' +
    '$names = $names | Select-Object -Unique;' +
    'foreach($n in $names){' +
    'sc.exe failure $n reset= 0 actions= '''' | Out-Null;' +
    'sc.exe config $n start= disabled | Out-Null;' +
    'Stop-Service -Name $n -Force -ErrorAction SilentlyContinue};' +
    'Start-Sleep -Seconds 2;' +
    'Get-Process -Name tgdesk,tgdesk-agent,tgdesk-agent-2,tgdesk-host,tgdesk-tunnel,tgdesk-tech ' +
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
    '/C taskkill /F /IM tgdesk-tech.exe >nul 2>&1', '',
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

{ Varre uma raiz por QUALQUER pasta "TGDesk*", apagando tudo que encontrar
  exceto o nome exato em SkipExactName (deixe '' para apagar tudo). Usado
  tanto em Program Files (onde nada precisa ser preservado) quanto em
  AppData/ProgramData (onde a pasta "TGDesk" exata guarda a identidade
  Admin/Tech e do dispositivo — essa nunca pode ser varrida por aqui). }
procedure RemoveLegacyTGDeskFoldersIn(RootPath, SkipExactName: string);
var
  FindRec: TFindRec;
  FullPath: string;
begin
  if RootPath = '' then Exit;
  if FindFirst(RootPath + '\TGDesk*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Attributes and $10) <> 0 then
        begin
          if (SkipExactName = '') or
              (CompareText(FindRec.Name, SkipExactName) <> 0) then
          begin
            FullPath := RootPath + '\' + FindRec.Name;
            DelTree(FullPath, True, True, True);
          end;
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

{ Cobre toda pasta "TGDesk*" órfã que já existiu: a antiga "TGDesk Client"
  (sem serviço formal), e resíduos do TGDESKLAB (infraestrutura de VMs de
  teste removida do código-fonte em 30/07, mas cuja limpeza no Windows nunca
  chegou a rodar — ver .godzmind/objetivos/obj-20260730-remover-tgdesklab.md).
  Program Files não tem nada a preservar; em AppData/ProgramData a pasta
  "TGDesk" exata é pulada porque é onde mora identity/ (technician.dat e
  device.json) que o resto do instalador já trata com cuidado. }
procedure RemoveLegacyTGDeskFolders;
begin
  RemoveLegacyTGDeskFoldersIn(ExpandConstant('{autopf}'), '');
  RemoveLegacyTGDeskFoldersIn(ExpandConstant('{pf32}'), '');
  RemoveLegacyTGDeskFoldersIn(ExpandConstant('{localappdata}'), 'TGDesk');
  RemoveLegacyTGDeskFoldersIn(ExpandConstant('{userappdata}'), 'TGDesk');
  RemoveLegacyTGDeskFoldersIn(ExpandConstant('{commonappdata}'), 'TGDesk');
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
    RemoveLegacyTGDeskFolders;
    { identity/ guarda duas coisas: technician.dat, que e a identidade de
      CONTROLE, e device.json, que e a identidade do DISPOSITIVO. Apagar o
      diretorio inteiro leva as duas, e sem device.json o agente esquece quem
      e, tenta se registrar como novo e o servidor recusa (409) porque o MAC
      ja pertence a um dispositivo existente.
      Por isso a remocao e cirurgica: o dispositivo sobrevive sempre, e so a
      identidade de controle cai quando substitui-la foi decidido de fato. }
    DelTree(ExpandConstant('{commonappdata}\TGDesk\state'), True, True, True);
    DelTree(ExpandConstant('{commonappdata}\TGDesk\logs'), True, True, True);
    DelTree(ExpandConstant('{commonappdata}\TGDesk\updates'), True, True, True);
    if ReplacesIdentity then
    begin
      DeleteFile(ExpandConstant('{commonappdata}\TGDesk\identity\technician.dat'));
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

{ Grava o icone da marca. O Pascal do Inno nao decodifica base64, e o PowerShell
  ja e usado aqui para impressao digital da maquina e para a DPAPI — reusa o
  mesmo caminho em vez de trazer mais uma dependencia.

  Falhar aqui nao interrompe nada: BrandIconWritten continua falso e os atalhos
  caem no icone do proprio tgdesk.exe. }
procedure WriteBrandIcon;
var
  Encoded, IconPath, Command: string;
  Cursor, ResultCode: Integer;
begin
  BrandIconWritten := False;
  if BrandingPayload = '' then
    exit;
  Cursor := 1;
  Encoded := JsonStringAfter(BrandingPayload, Cursor, 'favicon_base64');
  if Encoded = '' then
    exit;
  IconPath := BrandIconPath;
  ForceDirectories(ExtractFileDir(IconPath));
  Command :=
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    '$ErrorActionPreference=''Stop'';' +
    '[IO.File]::WriteAllBytes(''' + IconPath + ''',' +
    '[Convert]::FromBase64String(''' + Encoded + '''))"';
  if Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Command, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and
      (ResultCode = 0) and FileExists(IconPath) then
    BrandIconWritten := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PendingPath, ProtectedPath, ProtectCommand, ServiceCommand: string;
begin
  if CurStep = ssInstall then
  begin
    { Antes dos arquivos e dos atalhos, porque [Icons] ja precisa do .ico
      existindo em disco para apontar para ele. }
    WriteBrandIcon;
    WizardForm.StatusLabel.Caption :=
      'Validando e vinculando a chave ao servidor...';
    if IsTechnicianInstall and ReplacesIdentity and
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
    { A escolha do cliente vira intencao em disco em vez de uma chamada aqui:
      exigir servidor durante a instalacao deixaria uma maquina instalada
      offline sem destino. O agente materializa na primeira conexao, e tenta
      de novo enquanto nao conseguir. Instalacao de tecnico nao passa por
      aqui - la a chave e obrigatoria e a falta de rede aborta mesmo. }
    if IsTechnicianInstall then
    begin
      { A maquina do tecnico tambem tem destino, e ate agora nao tinha nenhum:
        redimir a chave criava a credencial e nao tocava no cadastro do
        dispositivo, entao o computador ficava 'guest' para sempre e fora de
        tudo que depende de estar numa rede — inclusive de receber atualizacao.

        O instalador nao decide QUAL rede: ele so diz que e instalacao de
        tecnico. O nivel (tecnico, supervisor, admin) vem da credencial, e quem
        escolhe a rede de sistema correspondente e o servidor. }
      SaveStringToFile(ExpandConstant(
        '{commonappdata}\TGDesk\identity\install-intent.json'),
        '{"kind":"tecnico"}', False);
    end
    else
    begin
      if IsCorporateClient then
        SaveStringToFile(ExpandConstant(
          '{commonappdata}\TGDesk\identity\install-intent.json'),
          '{"kind":"empresarial","technician_id":"' +
          JsonEscape(SelectedTechnicianID) + '"}', False)
      else
        SaveStringToFile(ExpandConstant(
          '{commonappdata}\TGDesk\identity\install-intent.json'),
          '{"kind":"particular"}', False);
    end;
    { O TGDesk busca o branding em runtime; o pacote baixado aqui so evita
      que a primeira tela apareca sem marca enquanto a rede nao responde. }
    if BrandingPayload <> '' then
      SaveStringToFile(ExpandConstant(
        '{commonappdata}\TGDesk\identity\install-branding.json'),
        BrandingPayload, False);
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
    { O instalador termina mandando o TGDesk se atualizar.
      O pacote embutido aqui envelhece: quem instala com um instalador de
      semanas atras nasce naquela versao e so sai dela na proxima verificacao
      periodica. Pedir a atualizacao no fim da instalacao faz a maquina nova
      convergir para a versao atual em minutos, e nao em horas.
      Sem esperar: o download decide sozinho se ha algo novo e nao ha nada que
      a instalacao precise dele. Se nao houver rede agora, a verificacao
      periodica do agente resolve depois. }
    Exec(ExpandConstant('{app}\tgdesk.exe'), '--tgdesk-update',
      ExpandConstant('{app}'), SW_HIDE, ewNoWait, ResultCode);
  end;
end;

[UninstallRun]
Filename: "{app}\tgdesk.exe"; Parameters: "--uninstall-service"; RunOnceId: "TGDeskService"; Flags: runhidden waituntilterminated skipifdoesntexist
; O TGDesk instala o driver de display virtual (usbmmidd_v2) sob demanda,
; quando a maquina nao tem tela fisica. Ele nao sai junto com os arquivos,
; entao precisa ser removido explicitamente na desinstalacao.
Filename: "{app}\tgdesk.exe"; Parameters: "--uninstall-amyuni-idd"; RunOnceId: "TGDeskVirtualDisplay"; Flags: runhidden waituntilterminated skipifdoesntexist

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{commonappdata}\TGDesk"
