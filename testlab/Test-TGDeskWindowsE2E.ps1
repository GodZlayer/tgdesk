[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    ),
    [int]$ServiceRestartCycles = 3,
    [string]$EvidencePath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot 'artifacts\windows-e2e-0.3.48.json'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)

function New-Assertion {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('passed','failed','blocked')][string]$State,
        [Parameter(Mandatory)][string]$Detail
    )
    [ordered]@{ id = $Id; state = $State; detail = $Detail }
}

$startedAt = [DateTime]::UtcNow
$guests = @()
foreach ($name in $VMName) {
    $guest = Invoke-Command -VMName $name -Credential $credential `
        -ArgumentList $ServiceRestartCycles -ScriptBlock {
        param($RestartCycles)
        $ErrorActionPreference = 'Stop'
        $statusPath = 'C:\ProgramData\TGDesk\state\status.json'
        $identityRoot = 'C:\ProgramData\TGDesk\identity'
        $agentLog = 'C:\ProgramData\TGDesk\logs\agent.log'
        $service = Get-CimInstance Win32_Service -Filter "Name='TGDesk'"
        $serviceExe = if ($service.PathName) {
            [regex]::Match($service.PathName, '^"([^"]+)"').Groups[1].Value
        } else { '' }
        $initial = [ordered]@{
            service_state = [string]$service.State
            service_start_mode = [string]$service.StartMode
            service_path = [string]$service.PathName
            service_exe = $serviceExe
            service_exe_version = if ($serviceExe -and (Test-Path $serviceExe)) {
                [string](Get-Item $serviceExe).VersionInfo.FileVersion
            } else { '' }
            version = if (Test-Path 'C:\Program Files\TGDesk\version.txt') {
                (Get-Content 'C:\Program Files\TGDesk\version.txt' -Raw).Trim()
            } else { '' }
            status = if (Test-Path $statusPath) {
                Get-Content $statusPath -Raw | ConvertFrom-Json
            } else { $null }
            processes = @(Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'" |
                Select-Object ProcessId,ParentProcessId,SessionId,ExecutablePath,CommandLine,
                    CreationDate)
            adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -match 'TGDesk|Wintun|WireGuard' -or
                    $_.InterfaceDescription -match 'TGDesk|Wintun|WireGuard'
                } | Select-Object Name,InterfaceDescription,Status,MacAddress,ifIndex)
            vpn_addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object IPAddress -Like '10.70.*' |
                Select-Object IPAddress,PrefixLength,InterfaceAlias,InterfaceIndex)
            identity = @(Get-ChildItem $identityRoot -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [ordered]@{
                        name = $_.Name
                        length = $_.Length
                        sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                    }
                })
            autostart = [ordered]@{
                machine = [string]((Get-ItemProperty `
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
                    -ErrorAction SilentlyContinue).TGDesk)
                user = [string]((Get-ItemProperty `
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
                    -ErrorAction SilentlyContinue).TGDesk)
            }
            critical_events = @(Get-WinEvent -FilterHashtable @{
                    LogName = 'Application'
                    StartTime = (Get-Date).AddHours(-2)
                    Level = 1,2
                } -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProviderName -match 'Application Error|Windows Error Reporting' -and
                    $_.Message -match 'tgdesk'
                } | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message)
            agent_log_tail = if (Test-Path $agentLog) {
                @(Get-Content $agentLog -Tail 80 | ForEach-Object { [string]$_ })
            } else { @() }
        }

        $restart = @()
        for ($cycle = 1; $cycle -le $RestartCycles; $cycle++) {
            Restart-Service TGDesk -ErrorAction Stop
            (Get-Service TGDesk).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            $recoveryDeadline = [DateTime]::UtcNow.AddSeconds(90)
            do {
                Start-Sleep -Seconds 2
                $cycleStatus = if (Test-Path $statusPath) {
                    try {
                        Get-Content $statusPath -Raw | ConvertFrom-Json
                    } catch { $null }
                } else { $null }
                $cycleAdapters = @(Get-NetAdapter -IncludeHidden `
                    -ErrorAction SilentlyContinue | Where-Object {
                        (
                            $_.Name -match 'TGDesk|Wintun|WireGuard' -or
                            $_.InterfaceDescription -match 'TGDesk|Wintun|WireGuard'
                        ) -and $_.Status -eq 'Up'
                    })
                if (
                    $cycleStatus.state -eq 'ativo' -and
                    $cycleStatus.tunnel_up -and
                    $cycleAdapters.Count -eq 1
                ) { break }
            } while ([DateTime]::UtcNow -lt $recoveryDeadline)
            $restart += [ordered]@{
                cycle = $cycle
                recovered = (
                    $cycleStatus.state -eq 'ativo' -and
                    $cycleStatus.tunnel_up -and
                    $cycleAdapters.Count -eq 1
                )
                recovery_state = [string]$cycleStatus.state
                recovery_tunnel_up = [bool]$cycleStatus.tunnel_up
                service = [string](Get-Service TGDesk).Status
                processes = @(Get-CimInstance Win32_Process -Filter "Name='tgdesk.exe'" |
                    Select-Object ProcessId,ParentProcessId,SessionId,ExecutablePath,CommandLine)
                adapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Name -match 'TGDesk|Wintun|WireGuard' -or
                        $_.InterfaceDescription -match 'TGDesk|Wintun|WireGuard'
                    } | Select-Object Name,InterfaceDescription,Status,ifIndex)
                vpn_addresses = @(Get-NetIPAddress -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue |
                    Where-Object IPAddress -Like '10.70.*' |
                    Select-Object IPAddress,PrefixLength,InterfaceAlias,InterfaceIndex)
            }
        }
        $after = [ordered]@{
            status = if (Test-Path $statusPath) {
                Get-Content $statusPath -Raw | ConvertFrom-Json
            } else { $null }
            identity = @(Get-ChildItem $identityRoot -File -ErrorAction SilentlyContinue |
                ForEach-Object {
                    [ordered]@{
                        name = $_.Name
                        length = $_.Length
                        sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                    }
                })
            critical_events = @(Get-WinEvent -FilterHashtable @{
                    LogName = 'Application'
                    StartTime = (Get-Date).AddHours(-2)
                    Level = 1,2
                } -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProviderName -match 'Application Error|Windows Error Reporting' -and
                    $_.Message -match 'tgdesk'
                } | Select-Object TimeCreated,ProviderName,Id,LevelDisplayName,Message)
        }
        [ordered]@{ initial = $initial; restart_cycles = $restart; after = $after }
    }
    $guests += [ordered]@{ vm_name = $name; observed = $guest }
}

$assertions = @()
foreach ($vm in $guests) {
    $prefix = $vm.vm_name
    $o = $vm.observed
    $serviceOk = (
        $o.initial.service_state -eq 'Running' -and
        $o.initial.service_start_mode -eq 'Auto' -and
        $o.initial.service_exe -eq 'C:\Program Files\TGDesk\tgdesk.exe' -and
        $o.initial.service_path -match '--service'
    )
    $assertions += New-Assertion 'runtime.service-ui-contract' `
        $(if ($serviceOk) { 'passed' } else { 'failed' }) `
        "${prefix}: serviço=$($o.initial.service_state), início=$($o.initial.service_start_mode), caminho=$($o.initial.service_path)"

    $identityStable = (
        $o.initial.identity.Count -gt 0 -and
        (ConvertTo-Json $o.initial.identity -Depth 4 -Compress) -eq
        (ConvertTo-Json $o.after.identity -Depth 4 -Compress)
    )
    $assertions += New-Assertion 'key.machine-bound' `
        $(if ($identityStable) { 'passed' } else { 'failed' }) `
        "${prefix}: $($o.initial.identity.Count) arquivo(s) de identidade permaneceram idênticos após $ServiceRestartCycles reinícios"

    $roleNoLogin = (
        $o.initial.identity.name -contains 'technician.dat' -or
        $o.initial.status.state -in @('guest','ativo','active','suspended')
    )
    $assertions += New-Assertion 'key.role.no-login' `
        $(if ($roleNoLogin) { 'passed' } else { 'failed' }) `
        "${prefix}: papel deriva de identidade/estado local sem credencial interativa"

    $restartOk = $true
    foreach ($cycle in $o.restart_cycles) {
        $serviceProcesses = @($cycle.processes | Where-Object {
            $_.SessionId -eq 0 -and $_.CommandLine -match '--service'
        })
        $hostProcesses = @($cycle.processes | Where-Object {
            $_.CommandLine -match '--tgdesk-host'
        })
        $technicianProcesses = @($cycle.processes | Where-Object {
            $_.CommandLine -match '--tgdesk-technician-service'
        })
        if ($cycle.service -ne 'Running' -or $serviceProcesses.Count -ne 1) {
            $restartOk = $false
        }
        $expectsTechnician = $o.initial.identity.name -contains 'technician.dat'
        $expectedTechnicianCount = if ($expectsTechnician) { 1 } else { 0 }
        if (
            $hostProcesses.Count -ne 1 -or
            $technicianProcesses.Count -ne $expectedTechnicianCount -or
            -not $cycle.recovered -or
            @($cycle.adapters | Where-Object Status -eq 'Up').Count -ne 1 -or
            @($cycle.vpn_addresses).Count -ne 1
        ) {
            $restartOk = $false
        }
        $adapterNames = @($cycle.adapters | ForEach-Object Name)
        if (($adapterNames | Select-Object -Unique).Count -ne $adapterNames.Count) {
            $restartOk = $false
        }
    }
    $assertions += New-Assertion 'stability.service-restarts' `
        $(if ($restartOk) { 'passed' } else { 'failed' }) `
        "${prefix}: $ServiceRestartCycles ciclos medidos; serviço único por ciclo e sem nomes de adaptador duplicados"

    $crashFree = @($o.after.critical_events).Count -eq 0
    $assertions += New-Assertion 'stability.crash-free' `
        $(if ($crashFree) { 'passed' } else { 'failed' }) `
        "${prefix}: $(@($o.after.critical_events).Count) crash(es) crítico(s) TGDesk nas últimas 2 horas"

    $uiProcesses = @($o.initial.processes | Where-Object {
        $_.SessionId -gt 0 -and
        $_.CommandLine -notmatch '--(service|agent|host|tunnel|server|tray)' -and
        $_.CommandLine -notmatch '--tgdesk-'
    })
    $uiState = if ($uiProcesses.Count -eq 1) { 'passed' } elseif ($uiProcesses.Count -eq 0) {
        'blocked'
    } else { 'failed' }
    $assertions += New-Assertion 'runtime.single-ui-process' $uiState `
        "${prefix}: $($uiProcesses.Count) processo(s) UI observável(is) em sessão interativa"

    $vpnOk = (
        @($o.initial.adapters | Where-Object Status -eq 'Up').Count -eq 1 -and
        @($o.initial.vpn_addresses).Count -eq 1 -and
        [bool]$o.initial.status.tunnel_up
    )
    $assertions += New-Assertion 'vpn.adapter.up' `
        $(if ($vpnOk) { 'passed' } else { 'blocked' }) `
        "${prefix}: adaptadores ativos=$(@($o.initial.adapters | Where-Object Status -eq 'Up').Count), IPs 10.70=$(@($o.initial.vpn_addresses).Count), tunnel_up=$($o.initial.status.tunnel_up)"
}

# An assertion is globally passed only when every target VM passed it. Repeated
# per-VM observations remain in details for diagnosis.
$aggregate = @()
foreach ($id in @($assertions.id | Select-Object -Unique)) {
    $items = @($assertions | Where-Object id -eq $id)
    $state = if ($items.state -contains 'failed') { 'failed' } elseif (
        $items.state -contains 'blocked'
    ) { 'blocked' } else { 'passed' }
    $aggregate += [ordered]@{
        id = $id
        state = $state
        detail = @($items.detail)
    }
}
$failed = @($aggregate | Where-Object state -eq 'failed')
$result = [ordered]@{
    schema_version = 1
    phase = 'windows-e2e-cli-0.3.48'
    status = if ($failed.Count) { 'failed' } else { 'passed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    started_at = $startedAt.ToString('o')
    mode = 'CLI-only; no UI interaction'
    targets = $VMName
    service_restart_cycles = $ServiceRestartCycles
    assertions = $aggregate
    guests = $guests
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force |
    Out-Null
$result | ConvertTo-Json -Depth 12 |
    Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 8
if ($failed.Count) { exit 1 }
