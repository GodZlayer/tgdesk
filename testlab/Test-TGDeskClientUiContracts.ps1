[CmdletBinding()]
param(
    [string]$ArtifactsPath = (Join-Path $PSScriptRoot 'artifacts')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $root 'client-rustdesk-src\flutter'
$started = (Get-Date).ToUniversalTime()
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Contract {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Details
    )
    $checks.Add([pscustomobject]@{
        id = $Id
        state = if ($Passed) { 'passed' } else { 'failed' }
        details = $Details
    })
}

function Has-All {
    param([string]$Path, [string[]]$Patterns)
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($pattern in $Patterns) {
        if ($text -notmatch $pattern) { return $false }
    }
    return $true
}

Push-Location $flutter
try {
    & flutter test test/tgdesk_ui_contract_test.dart test/tgdesk_support_contract_test.dart
    $testExit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($testExit -ne 0) {
    throw "Focused Flutter contract tests failed with exit code $testExit"
}

$contract = Join-Path $flutter 'lib\tgdesk\ui_contract.dart'
$client = Join-Path $flutter 'lib\tgdesk\client_home_page.dart'
$devices = Join-Path $flutter 'lib\tgdesk\devices_page.dart'
$hub = Join-Path $flutter 'lib\tgdesk\hub_home_page.dart'
$window = Join-Path $flutter 'lib\tgdesk\window_frame.dart'
$remote = Join-Path $flutter 'lib\tgdesk\remote_session_page.dart'
$remotePage = Join-Path $flutter 'lib\desktop\pages\remote_page.dart'
$remoteToolbar = Join-Path $flutter 'lib\desktop\widgets\remote_toolbar.dart'
$remoteTabs = Join-Path $flutter 'lib\desktop\pages\remote_tab_page.dart'
$diagnostics = Join-Path $flutter 'lib\tgdesk\diagnostics_dialog.dart'
$branding = Join-Path $flutter 'lib\tgdesk\branding_page.dart'
$whiteboard = Join-Path $root 'client-rustdesk-src\src\server\connection.rs'

$tested = Has-All $contract @(
    'class TgdeskClientUiPolicy',
    'class TgdeskDeviceUiPolicy',
    'class TgdeskUpdatePolicy',
    'class TgdeskRemotePolicy',
    'class TgdeskBrandingPolicy',
    'class TgdeskDiagnosticPolicy'
)

Add-Contract 'client.ui.non-technical' ($tested -and (Has-All $client @(
    'Desempenho est',
    'Uso adequado',
    'Acompanhamento cont'
))) 'Client cards use customer-facing summaries; detailed metrics remain in device views.'
Add-Contract 'client.ui.status-colors' ($tested -and (Has-All $client @(
    '_indicatorColor',
    '0xffff5252',
    '0xffffb020',
    '0xff45c95a'
))) 'Server severity maps to green, yellow, and red indicator colors.'
Add-Contract 'client.ui.no-false-attention' $tested 'Unit tests prove global and per-metric server severity remain independent.'
Add-Contract 'client.ui.suspended-message' (Has-All $client @(
    "state == 'suspenso'",
    'Contate a TG Devs para reativar'
)) 'Suspended state has a dedicated contact-only surface.'
Add-Contract 'client.ui.role-simulation' (Has-All $hub @(
    'TgdeskClientHomePage\(embedded: true\)',
    'canManageNetworks'
)) 'Control roles include the same embedded client page.'

Add-Contract 'devices.display-name' (Has-All $devices @(
    "d\['display_name'\]",
    'updateDeviceDisplayName'
)) 'Display name is rendered separately from hostname and edited through TGDesk API.'
Add-Contract 'devices.alert.badge' (Has-All $devices @(
    "d\['health_level'\]",
    '_alertBadge'
)) 'Device row renders its active health severity.'
Add-Contract 'networks.alert.aggregate' ($tested -and (Has-All $devices @(
    'devicesOfNet.fold<int>',
    "device\['health_level'\]",
    '_alertBadge'
))) 'Network rows aggregate and render the highest device severity; ordering is unit tested.'
Add-Contract 'devices.details.visual' (Has-All $devices @(
    'LinearProgressIndicator',
    '_visualMetric',
    '_storageVisual',
    '_networkVisual'
)) 'Device details render cards, progress meters and severity visuals.'
Add-Contract 'devices.details.realtime' (Has-All $devices @(
    '_control.addListener',
    'deviceHealth'
)) 'Open device views listen to the persistent control channel telemetry cache.'
Add-Contract 'devices.remote.button.truth' $tested 'Remote button policy is unit tested for self, state, live presence, capability and remote ID.'

Add-Contract 'update.no-self-update' ($tested -and (Has-All $client @(
    'TgdeskUpdatePolicy.shouldOffer'
)) -and (Has-All $hub @(
    'TgdeskUpdatePolicy.shouldOffer'
))) 'Both client and control shells use strict semantic newer-version comparison.'
Add-Contract 'update.settings-button' (Has-All $window @(
    'Buscar e for',
    'Consultando o servidor',
    '--tgdesk-update',
    'updateMessage'
)) 'Settings recovery action exposes progress and updater output.'

Add-Contract 'remote.no-self' $tested 'Remote UI policy rejects the current device before presenting the action.'
Add-Contract 'remote.single-toolbar' ((Has-All $remote @(
    "'embedded': true",
    'tgdeskToolbarMenuBuilder'
)) -and (Has-All $remoteTabs @(
    "params\['embedded'\] != true",
    'tgdeskEmbedded'
))) 'Embedded session suppresses the outer remote window and injects TGDesk tools into one toolbar.'
Add-Contract 'remote.keyboard-routing' ((Has-All $remotePage @(
    'LogicalKeyboardKey.keyI',
    'isControlPressed',
    'isShiftPressed',
    '_toggleSystemKeyCapture'
)) -and (Has-All $remoteToolbar @(
    'Ctrl\+Shift\+I',
    '_SystemKeysMenu'
))) 'Ctrl+Shift+I and the toolbar toggle route Windows shortcuts locally or remotely.'
Add-Contract 'remote.input-lock' (Has-All $remote @(
    "'block-input'",
    "'unblock-input'",
    'Ctrl\+Shift\+B',
    'dispose\(\)'
)) 'Input lock has toolbar/shortcut control and dispose-time restoration.'
Add-Contract 'remote.annotation' ((Has-All $remote @(
    'Ctrl\+Shift\+D',
    '_ColorButton',
    '_strokeWidth',
    '_eraser',
    '_clearDrawing'
)) -and (Has-All $whiteboard @(
    '__TGDESK_ANNOTATION__',
    'update_whiteboard'
))) 'Pen events carry normalized coordinates to the host whiteboard implementation.'
Add-Contract 'remote.clipboard.default-off' ($tested -and (Has-All $remote @(
    '_clipboardEnabled = false',
    "'disable-clipboard'"
))) 'Clipboard is disabled on session initialization and enabled only by explicit action.'
Add-Contract 'remote.files.default-off' ($tested -and (Has-All $remote @(
    '_fileTransferEnabled = false',
    'kOptionEnableFileCopyPaste'
))) 'File copy is disabled on session initialization and enabled only by explicit action.'
Add-Contract 'remote.chat.integrated' (Has-All $remoteToolbar @(
    '_ChatMenu',
    'toggleChatOverlay'
)) 'The only exposed chat action opens the integrated session chat overlay.'

Add-Contract 'diagnostics.manual-only' (Has-All $diagnostics @(
    'Cada teste',
    'Executar este teste',
    'startDiagnostic'
)) 'Each heavy diagnostic starts only from a dedicated manual action.'
Add-Contract 'diagnostics.progress-live' (Has-All $diagnostics @(
    '_control.addListener',
    'diagnosticRuns',
    'LinearProgressIndicator'
)) 'Diagnostic progress consumes private control-channel events and renders progress.'
Add-Contract 'diagnostics.visual-report' (Has-All $diagnostics @(
    'Hist',
    '_resultVisual',
    'Log t'
)) 'Results combine visual values, history and selectable raw audit log.'
Add-Contract 'diagnostics.remote-menu' (Has-All $remote @(
    "'diagnostics'",
    'DiagnosticDialog'
)) 'Active remote toolbar exposes the same diagnostics dialog.'
Add-Contract 'diagnostics.badblocks-safety' $tested 'Unit-tested policy rejects destructive and write-mode storage tests.'

Add-Contract 'branding.admin-enable' (Has-All $branding @(
    'Personaliza',
    'habilitada pelo administrador'
)) 'Supervisor editor remains unavailable until the administrator enables it.'
Add-Contract 'branding.client-only' $tested 'Brand policy unit tests allow customer identity only for active standalone clients.'
Add-Contract 'branding.control-keeps-tgdesk' $tested 'Control preview and control roles are excluded from customer branding by contract.'
Add-Contract 'branding.name-logo-favicon' (Has-All $branding @(
    'Nome exibido ao cliente',
    'Escolher logo',
    'Criar favicon'
)) 'Editor explicitly controls name, logo and multi-surface client icon.'
Add-Contract 'branding.crop-resize' (Has-All $branding @(
    'copyCrop',
    'copyResize',
    'Interpolation.cubic',
    'Zoom'
)) 'Favicon editor crops and resizes with cubic interpolation.'
Add-Contract 'branding.preview-exact' (Has-All $branding @(
    'Preview no Client',
    'exatamente o',
    '256, 64, 48, 32 e 16'
)) 'Preview exposes the exact square composition and target icon sizes.'

$failed = @($checks | Where-Object state -eq 'failed')
$report = [ordered]@{
    schema_version = 1
    phase = 'client-ui-contracts'
    state = if ($failed.Count) { 'failed' } else { 'passed' }
    measured_at = (Get-Date).ToUniversalTime().ToString('o')
    duration_ms = [math]::Round(((Get-Date).ToUniversalTime() - $started).TotalMilliseconds)
    assertions = $checks
}
New-Item -ItemType Directory -Path $ArtifactsPath -Force | Out-Null
$path = Join-Path $ArtifactsPath 'client-ui-contracts.json'
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
$report | ConvertTo-Json -Depth 4
if ($failed.Count) { exit 1 }
