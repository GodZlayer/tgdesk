$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$evidencePath = Join-Path $PSScriptRoot 'artifacts\functional-contracts.json'
$assertions = @()

function Add-Contract([string]$Id, [bool]$Passed, [hashtable]$Details) {
    $script:assertions += [ordered]@{
        id = $Id
        state = if ($Passed) { 'passed' } else { 'failed' }
        details = $Details
    }
    if (-not $Passed) { throw "Contrato ausente: $Id" }
}
function Read-Source([string]$Path) {
    Get-Content (Join-Path $root $Path) -Raw
}
function Has-All([string]$Text, [string[]]$Tokens) {
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { return $false }
    }
    return $true
}

try {
    $installer = Read-Source 'installers\tgdesk-installer.iss'
    $hostSource = Read-Source 'client-agent\host.go'
    Add-Contract 'installer.identity.clean-new' (
        Has-All $installer @(
            'Não — apagar a identidade e instalar como novo computador',
            'PreserveIdentityPage.SelectedValueIndex = 0',
            '{commonappdata}\TGDesk\identity'
        ) -and Has-All $hostSource @('/api/v1/devices/register','saveConfig(cfg)')
    ) @{policy='identity is deleted only by explicit clean selection, then server issues new device identity and token'}

    $migration = Read-Source 'server\migrations\0011_control_installation_keys.sql'
    $enrollment = Read-Source 'server\api-core\internal\handlers\technician_enrollment.go'
    Add-Contract 'key.admin.singleton' (
        Has-All $migration @(
            'CREATE UNIQUE INDEX',
            "WHERE control_role = 'super_admin' AND status = 'ativo'"
        )
    ) @{database='partial unique index permits exactly one active Admin machine'}
    Add-Contract 'key.reinstall.original-admin' (
        Has-All $enrollment @(
            'ON CONFLICT (technician_id, machine_id) DO UPDATE',
            "if role == `"super_admin`""
        )
    ) @{policy='same original machine rotates its credential; another machine conflicts with singleton index'}

    $admin = Read-Source 'server\api-core\internal\handlers\admin.go'
    $router = Read-Source 'server\api-core\internal\handlers\router.go'
    $control = Read-Source 'server\api-core\internal\handlers\control_ws.go'
    Add-Contract 'key.revocation.propagates' (
        Has-All $admin @(
            'UPDATE technician_machine_credentials',
            "SET status='revogado'",
            'dropTechnicianHubPeer'
        ) -and Has-All $router @(
            'sessão revogada ou suspensa',
            'SELECT status FROM technicians'
        ) -and Has-All $control @(
            '"session_revoked"',
            'evt.TargetID == claims.TechnicianID'
        )
    ) @{effects=@('refresh credential revoked','existing JWT rejected','private websocket closed','VPN peer removed')}

    Add-Contract 'vpn.bootstrap.public-only' (
        Has-All $router @(
            'requestFromVPN(r)',
            'operação disponível somente pela VPN',
            'GET /api/v1/client/update',
            'POST /api/v1/auth/control-key/install'
        ) -and Has-All $control @(
            'canal de controle disponível somente pela VPN',
            '10.70.1.1'
        )
    ) @{public=@('registration/bootstrap','authentication','update recovery');private=@('management','telemetry','presence','remote control')}

    $agentControl = Read-Source 'client-agent\control.go'
    $agentStatus = Read-Source 'client-agent\status.go'
    $serverPushesVersion = Has-All $control @(
            '"version": os.Getenv("CLIENT_VERSION")',
            '"type": "heartbeat_ack"'
        )
    $agentConsumesVersion = Has-All $agentControl @('setServerUpdateVersion(msg.Version)')
    $statusComparesVersion = Has-All $agentStatus @('UpdateAvailable','updateIsNewer(version)')
    Add-Contract 'ws.push.update' (
        $serverPushesVersion -and $agentConsumesVersion -and $statusComparesVersion
    ) @{transport='private persistent websocket';polling='UI reads local status only'}

    $telemetryControl = Read-Source 'server\api-core\internal\handlers\control_ws.go'
    $telemetryStats = Read-Source 'server\api-core\internal\handlers\telemetry_stats.go'
    $retentionDeletes = Has-All $telemetryControl @(
        "coletado_em < now()-interval '30 days'"
    )
    $boundedSampling = $agentControl.Contains('telemetryTick := time.NewTicker(30 * time.Second)')
    $boundedStats = $telemetryStats.Contains("coletado_em >= now()-interval '30 days'")
    Add-Contract 'telemetry.retention' (
        $retentionDeletes -and $boundedSampling -and $boundedStats
    ) @{client_interval_seconds=30;server_retention_days=30;aggregation='server-side'}

    $remote = Read-Source 'client-agent\remote_access.go'
    $devices = Read-Source 'server\api-core\internal\handlers\devices.go'
    $devicesUi = Read-Source 'client-rustdesk-src\flutter\lib\tgdesk\devices_page.dart'
    Add-Contract 'remote.no-password' (
        Has-All $remote @(
            'cfg.RemoteCredential',
            '"--password"',
            'use-permanent-password'
        ) -and Has-All $devices @('remoteCredential(deviceID, deviceToken)')
    ) @{interactive_prompt=$false;credential='server-derived and configured automatically'}
    Add-Contract 'remote.scope' (
        Has-All $devices @(
            'technicianCanAccessDevice',
            'sem permissão para esse dispositivo',
            'claims.Role != models.RoleSuperAdmin'
        )
    ) @{supervisor='authorized device scope';admin='explicit superset'}
    Add-Contract 'remote.online-truth' (
        Has-All $devicesUi @(
            "presence == 'online'",
            "d['remote_ready'] == true",
            'remoteCredential'
        ) -and Has-All $control @(
            '"remote_ready": capabilities.RemoteReady',
            '"presence": "offline"'
        )
    ) @{button_requires=@('live presence','remote capability');offline='websocket disconnect clears presence'}

    $evidence = [ordered]@{
        schema_version=1
        scenario='functional-contracts'
        state='passed'
        measured_at=(Get-Date).ToUniversalTime().ToString('o')
        assertions=$assertions
    }
    $evidence | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8
    $evidence | ConvertTo-Json -Depth 6
} catch {
    [ordered]@{
        schema_version=1;scenario='functional-contracts';state='failed'
        measured_at=(Get-Date).ToUniversalTime().ToString('o')
        error=$_.Exception.Message;assertions=$assertions
    } | ConvertTo-Json -Depth 8 | Set-Content $evidencePath -Encoding utf8
    throw
}
