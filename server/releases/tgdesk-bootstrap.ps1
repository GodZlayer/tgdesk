[CmdletBinding()]
param(
    [string]$ApiBase = 'http://168.232.199.161:8090',
    [string]$CurrentVersion = '0.0.0',
    [string]$InstallDir = 'C:\Program Files\TGDesk',
    [string]$EnrollmentKeyPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Execute este comando em um PowerShell aberto como Administrador.'
    }
}

function Get-SafeModulePath([string]$Root, [string]$Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or
        [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains('..')) {
        throw "Caminho inválido no manifesto: $Relative"
    }
    $full = [IO.Path]::GetFullPath((Join-Path $Root ($Relative -replace '/', '\')))
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Módulo fora do staging: $Relative"
    }
    return $full
}

function Get-PublicFile([string]$Uri, [string]$Destination) {
    $parent = Split-Path -Parent $Destination
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $temporary = "$Destination.download"
    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $temporary
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

Assert-Administrator
$ApiBase = $ApiBase.TrimEnd('/')
$identityPath = 'C:\ProgramData\TGDesk\identity\device.json'
$identityBefore = if (Test-Path -LiteralPath $identityPath) {
    (Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash
} else { '' }

$manifest = Invoke-RestMethod -Uri "$ApiBase/api/v1/client/modules?version=$CurrentVersion"
if ($manifest.format_version -ne 1 -or -not $manifest.version -or
    @($manifest.files).Count -eq 0) {
    throw 'Manifesto modular público inválido ou atualização indisponível.'
}

$stagingRoot = "C:\ProgramData\TGDesk\updates\public-bootstrap-$($manifest.version)"
$filesRoot = Join-Path $stagingRoot 'files'
[IO.Directory]::CreateDirectory($filesRoot) | Out-Null

foreach ($file in @($manifest.files)) {
    $relative = [string]$file.path
    $target = Get-SafeModulePath $filesRoot $relative
    $escaped = (($relative -split '/') | ForEach-Object {
        [Uri]::EscapeDataString($_)
    }) -join '/'
    Get-PublicFile `
        "$ApiBase/api/v1/client/modules/$($manifest.version)/$escaped" $target
    $actual = Get-Item -LiteralPath $target
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual.Length -ne [int64]$file.size -or
        $hash -ne ([string]$file.sha256).ToLowerInvariant()) {
        throw "Integridade inválida: $relative"
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText(
    (Join-Path $stagingRoot 'manifest.json'), $manifestJson,
    [Text.UTF8Encoding]::new($false))

$updaterInfo = Invoke-RestMethod -Uri "$ApiBase/api/v1/client/updater"
$updater = Join-Path $stagingRoot 'tgdesk-updater.exe'
Get-PublicFile "$ApiBase$($updaterInfo.url)" $updater
$updaterHash = (Get-FileHash -LiteralPath $updater -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Get-Item -LiteralPath $updater).Length -ne [int64]$updaterInfo.size -or
    $updaterHash -ne ([string]$updaterInfo.sha256).ToLowerInvariant()) {
    throw 'Integridade do updater standalone inválida.'
}

# O bootstrap roda fora do updater e e o unico fluxo autorizado a renovar
# esse componente sem autorreferencia. A copia baixada continua sendo a
# executada nesta atualizacao.
$installedUpdater = Join-Path $InstallDir 'tgdesk-updater.exe'
$installedUpdaterNew = Join-Path $InstallDir 'tgdesk-updater.exe.bootstrap-new'
Copy-Item -LiteralPath $updater -Destination $installedUpdaterNew -Force
if ((Get-FileHash -LiteralPath $installedUpdaterNew -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    $updaterHash) {
    throw 'Falha de integridade ao preparar o updater instalado.'
}
Move-Item -LiteralPath $installedUpdaterNew -Destination $installedUpdater -Force

& $updater -apply-staged -staging $stagingRoot -install-dir $InstallDir -parent 0
if ($LASTEXITCODE -ne 0) { throw "Updater terminou com código $LASTEXITCODE." }

$installedVersion = (Get-Content -LiteralPath (Join-Path $InstallDir 'version.txt') -Raw).Trim()
$service = (Get-Service TGDesk -ErrorAction SilentlyContinue).Status
$identityAfter = if (Test-Path -LiteralPath $identityPath) {
    (Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash
} else { '' }
if ($installedVersion -ne [string]$manifest.version) { throw 'Versão instalada divergente.' }
if ($service -ne 'Running') { throw 'Serviço TGDesk não reiniciou.' }
if ($identityBefore -and $identityBefore -ne $identityAfter) {
    throw 'A identidade do dispositivo foi alterada.'
}

$identityRecognized = $false
$identityRecreated = $false
$identityBackup = ''
$pairingCode = ''
if (Test-Path -LiteralPath $identityPath) {
    $deviceIdentity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    try {
        $heartbeat = Invoke-RestMethod -Method Post `
            -Uri "$ApiBase/api/v1/devices/heartbeat" `
            -ContentType 'application/json' `
            -Body (@{
                device_id = [string]$deviceIdentity.device_id
                device_token = [string]$deviceIdentity.device_token
            } | ConvertTo-Json -Compress)
        $identityRecognized = [string]$heartbeat.state -in @('guest', 'ativo', 'suspenso')
        $pairingCode = [string]$heartbeat.pairing_code
    } catch {
        $statusCode = 0
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -notin @(401, 404)) { throw }
    }
}

if (-not $identityRecognized) {
    Stop-Service TGDesk -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $identityPath) {
        $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $identityBackup = "C:\ProgramData\TGDesk\updates\orphaned-device-$stamp.json"
        Copy-Item -LiteralPath $identityPath -Destination $identityBackup -Force
        Remove-Item -LiteralPath $identityPath -Force
    }
    Start-Service TGDesk
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Milliseconds 750
        if (Test-Path -LiteralPath $identityPath) {
            try {
                $newIdentity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
                $identityRecreated = -not [string]::IsNullOrWhiteSpace(
                    [string]$newIdentity.device_id)
                $pairingCode = [string]$newIdentity.pairing_code
            } catch {}
        }
    } while (-not $identityRecreated -and (Get-Date) -lt $deadline)
    if (-not $identityRecreated) {
        throw 'O servidor não reconheceu a identidade antiga e o novo registro não foi concluído.'
    }
}

$controlRole = ''
$controlIdentityInstalled = $false
$controlToken = ''
$deviceAutoBound = $false
if (-not [string]::IsNullOrWhiteSpace($EnrollmentKeyPath)) {
    if (-not (Test-Path -LiteralPath $EnrollmentKeyPath)) {
        throw "Chave de inscrição não encontrada: $EnrollmentKeyPath"
    }
    Add-Type -AssemblyName System.Security
    $enrollmentKey = Get-Content -LiteralPath $EnrollmentKeyPath -Raw | ConvertFrom-Json
    $machineID = (Get-ItemProperty `
        'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid.Trim()
    $redeemed = Invoke-RestMethod -Method Post `
        -Uri "$ApiBase/api/v1/auth/technician/redeem" `
        -ContentType 'application/json' `
        -Body (@{key=$enrollmentKey;machine_id=$machineID} |
            ConvertTo-Json -Depth 5 -Compress)
    if ([string]$redeemed.role -ne 'supervisor') {
        throw "A chave não retornou o papel supervisor: $($redeemed.role)"
    }
    $controlToken = [string]$redeemed.token
    $controlCredential = @{
        credential_id = [string]$redeemed.credential_id
        secret = [string]$redeemed.secret
        machine_id = [string]$redeemed.machine_id
    }
    $credentialBytes = [Text.Encoding]::UTF8.GetBytes(
        ($controlCredential | ConvertTo-Json -Compress))
    try {
        $protected = [Security.Cryptography.ProtectedData]::Protect(
            $credentialBytes, $null,
            [Security.Cryptography.DataProtectionScope]::LocalMachine)
        $credentialPath = 'C:\ProgramData\TGDesk\identity\technician.dat'
        if (Test-Path -LiteralPath $credentialPath) {
            $oldControl = "C:\ProgramData\TGDesk\updates\orphaned-technician-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).dat"
            Copy-Item -LiteralPath $credentialPath -Destination $oldControl -Force
        }
        [IO.File]::WriteAllBytes("$credentialPath.new", $protected)
        Move-Item -LiteralPath "$credentialPath.new" `
            -Destination $credentialPath -Force
        $controlRole = [string]$redeemed.role
        $controlIdentityInstalled = $true
    } finally {
        if ($credentialBytes) {
            [Array]::Clear($credentialBytes, 0, $credentialBytes.Length)
        }
        $controlCredential = $null
        $redeemed = $null
    }
    Restart-Service TGDesk -Force
    $service = (Get-Service TGDesk).Status

    $privateReady = $false
    $privateDeadline = (Get-Date).AddSeconds(60)
    do {
        try {
            $tcp = [Net.Sockets.TcpClient]::new()
            $connect = $tcp.BeginConnect('10.70.0.1', 8080, $null, $null)
            $privateReady = $connect.AsyncWaitHandle.WaitOne(1000) -and $tcp.Connected
            $tcp.Dispose()
        } catch { $privateReady = $false }
        if (-not $privateReady) { Start-Sleep -Seconds 1 }
    } while (-not $privateReady -and (Get-Date) -lt $privateDeadline)
    if (-not $privateReady) { throw 'A VPN da supervisora não ficou disponível.' }

    $privateApi = 'http://10.70.0.1:8080'
    $controlHeaders = @{Authorization="Bearer $controlToken"}
    if (-not [string]::IsNullOrWhiteSpace($pairingCode)) {
        $organizations = @(Invoke-RestMethod `
            -Uri "$privateApi/api/v1/organizations" -Headers $controlHeaders)
        $ownOrganization = $organizations | Where-Object {
            $_.can_manage -eq $true -and $_.name -ine 'TGDevs'
        } | Select-Object -First 1
        if (-not $ownOrganization) { throw 'Organização da supervisora não encontrada.' }
        $networks = @(Invoke-RestMethod `
            -Uri "$privateApi/api/v1/networks?organization_id=$($ownOrganization.id)" `
            -Headers $controlHeaders)
        $principalNetwork = $networks | Where-Object {
            $_.organization_id -eq $ownOrganization.id -and $_.name -eq 'Principal'
        } | Select-Object -First 1
        if (-not $principalNetwork) { throw 'Rede Principal da supervisora não encontrada.' }
        $bound = Invoke-RestMethod -Method Post `
            -Uri "$privateApi/api/v1/pairing/bind" `
            -Headers $controlHeaders -ContentType 'application/json' `
            -Body (@{pairing_code=$pairingCode;network_id=$principalNetwork.id} |
                ConvertTo-Json -Compress)
        $deviceAutoBound = [string]$bound.state -eq 'ativo'
    }
    $currentDevice = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    Invoke-RestMethod -Method Post `
        -Uri "$privateApi/api/v1/devices/$($currentDevice.device_id)/control-machine" `
        -Headers $controlHeaders | Out-Null
}

[pscustomobject]@{
    updated = $true
    from = $CurrentVersion
    to = $installedVersion
    service = [string]$service
    identity_preserved = $identityRecognized -and (
        (-not $identityBefore) -or $identityBefore -eq $identityAfter)
    identity_recognized = $identityRecognized
    identity_recreated = $identityRecreated
    identity_backup = $identityBackup
    pairing_code = $pairingCode
    control_identity_installed = $controlIdentityInstalled
    control_role = $controlRole
    device_auto_bound = $deviceAutoBound
} | ConvertTo-Json
