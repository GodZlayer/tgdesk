[CmdletBinding()]
param(
    [string[]]$VMName = @(
        'tgdesk-client-0-3-48',
        'tgdesk-supervisor-0-3-48'
    ),
    [string]$InstallerPath = '',
    [string]$EvidencePath = ''
)
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $scriptRoot
if (-not $InstallerPath) {
    $InstallerPath = Join-Path $repo `
        'installers\output\tgdesk-installer-0.3.48.exe'
}
if (-not $EvidencePath) {
    $EvidencePath = Join-Path $scriptRoot `
        'artifacts\windows-e2e-install-0.3.48.json'
}
$credential = [pscredential]::new(
    'tgdesklab',
    (ConvertTo-SecureString 'TGDesk-Lab-Only-2026!' -AsPlainText -Force)
)
$results = @()
foreach ($name in $VMName) {
    $before = Invoke-Command -VMName $name -Credential $credential -ScriptBlock {
        @(Get-ChildItem 'C:\ProgramData\TGDesk\identity' -File |
            ForEach-Object {
                [ordered]@{
                    name = $_.Name
                    sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
                }
            })
    }
    $destination = 'C:\TGDeskLab\tgdesk-installer-0.3.48-fixed.exe'
    Copy-VMFile -Name $name -SourcePath $InstallerPath `
        -DestinationPath $destination -FileSource Host -Force
    $install = Invoke-Command -VMName $name -Credential $credential -ScriptBlock {
        $process = Start-Process `
            'C:\TGDeskLab\tgdesk-installer-0.3.48-fixed.exe' `
            -ArgumentList @(
                '/VERYSILENT',
                '/SUPPRESSMSGBOXES',
                '/NORESTART',
                '/CLOSEAPPLICATIONS',
                '/LOG=C:\TGDeskLab\reinstall-fixed.log'
            ) -Wait -PassThru
        [ordered]@{ exit_code = $process.ExitCode }
    }
    # The installer replaces the service and starts the new binary itself.
    # Reboot remains a separate installer acceptance test because Hyper-V
    # shutdown of these evaluation guests can wait indefinitely.
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    do {
        Start-Sleep -Seconds 3
        try {
            $after = Invoke-Command -VMName $name -Credential $credential `
                -ErrorAction Stop -ScriptBlock {
                [ordered]@{
                    service = [string](Get-Service TGDesk).Status
                    version = (Get-Content `
                        'C:\Program Files\TGDesk\version.txt' -Raw).Trim()
                    identity = @(Get-ChildItem `
                        'C:\ProgramData\TGDesk\identity' -File |
                        ForEach-Object {
                            [ordered]@{
                                name = $_.Name
                                sha256 = (Get-FileHash $_.FullName `
                                    -Algorithm SHA256).Hash
                            }
                        })
                    core_hash = (Get-FileHash `
                        'C:\Program Files\TGDesk\librustdesk.dll' `
                        -Algorithm SHA256).Hash
                }
            }
        } catch { $after = $null }
    } until ($after -or [DateTime]::UtcNow -ge $deadline)
    $preserved = (
        (ConvertTo-Json $before -Depth 5 -Compress) -eq
        (ConvertTo-Json $after.identity -Depth 5 -Compress)
    )
    $results += [ordered]@{
        vm_name = $name
        install_exit_code = $install.exit_code
        ready = [bool]$after
        service = [string]$after.service
        version = [string]$after.version
        identity_preserved = $preserved
        core_hash = [string]$after.core_hash
    }
}
$passed = @($results | Where-Object {
    -not $_.ready -or
    $_.service -ne 'Running' -or
    $_.version -ne '0.3.48' -or
    -not $_.identity_preserved
}).Count -eq 0
$result = [ordered]@{
    schema_version = 1
    phase = 'windows-e2e-fixed-install'
    status = if ($passed) { 'passed' } else { 'failed' }
    measured_at = [DateTime]::UtcNow.ToString('o')
    installer_sha256 = (Get-FileHash $InstallerPath -Algorithm SHA256).Hash
    targets = $results
}
New-Item -ItemType Directory -Path (Split-Path -Parent $EvidencePath) -Force |
    Out-Null
$result | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $EvidencePath -Encoding utf8
$result | ConvertTo-Json -Depth 8
if (-not $passed) { exit 1 }
