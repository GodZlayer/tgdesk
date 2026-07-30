[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$issPath = Join-Path $repo 'installers\tgdesk-installer.iss'
$updaterPath = Join-Path $repo 'client-agent\updater.go'
$runnerPath = Join-Path $repo 'client-rustdesk-src\flutter\windows\runner\main.cpp'
$artifactPath = Join-Path $PSScriptRoot 'artifacts\installer-update.json'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("tgdesk-contract-" + [guid]::NewGuid().ToString('N'))
$assertions = [Collections.Generic.List[object]]::new()

function Add-Assertion {
    param([string]$Id, [bool]$Passed, [hashtable]$Details)
    $assertions.Add([ordered]@{
        id = $Id
        state = if ($Passed) { 'passed' } else { 'failed' }
        details = $Details
    })
}

function Has-All {
    param([string]$Text, [string[]]$Tokens)
    foreach ($token in $Tokens) {
        if (-not $Text.Contains($token)) { return $false }
    }
    return $true
}

New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $iss = Get-Content -LiteralPath $issPath -Raw
    $updater = Get-Content -LiteralPath $updaterPath -Raw
    $runner = Get-Content -LiteralPath $runnerPath -Raw
    $version = [regex]::Match($iss, '#define MyAppVersion "([^"]+)"').Groups[1].Value

    $flowTokens = @(
        'CreateInputOptionPage(wpWelcome',
        'CreateInputOptionPage(PreserveIdentityPage.ID',
        'CreateInputFilePage(HasControlKeyPage.ID',
        'CreateOutputProgressPage(',
        'if CurStep = ssInstall',
        'if CurStep = ssPostInstall'
    )
    $positions = @($flowTokens | ForEach-Object { $iss.IndexOf($_) })
    $ordered = -not ($positions -contains -1)
    for ($i = 1; $i -lt $positions.Count; $i++) {
        if ($positions[$i] -le $positions[$i - 1]) { $ordered = $false }
    }
    Add-Assertion 'installer.flow.5-pages' $ordered @{ positions = $positions }

    $cleanupFiles = Has-All $iss @(
        'TGDeskAgent', 'TGDeskHost', 'tgdesk-agent.exe', 'tgdesk-host.exe',
        'tgdesk-tunnel.exe', 'RustDesk', 'WireGuard', 'SWD\WINTUN\*',
        'Get-ScheduledTask', 'Win32_UserProfile', '{commonappdata}\TGDesk'
    )
    Add-Assertion 'installer.cleanup.legacy-files' $cleanupFiles @{
        scope = 'services, processes, drivers, tasks, profiles, ProgramData, Program Files'
    }

    $cleanupRegistry = Has-All $iss @(
        "RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\RustDesk')",
        "RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\WireGuard')",
        "RegDeleteKeyIncludingSubkeys(HKLM64, 'SOFTWARE\RustDesk')",
        "RegDeleteKeyIncludingSubkeys(HKLM64, 'SOFTWARE\WireGuard')",
        "RegDeleteKeyIncludingSubkeys(HKCU, 'SOFTWARE\TGDesk')",
        'CurrentVersion\Uninstall'
    )
    $unsafeRootDelete = $iss -match "RegDeleteKeyIncludingSubkeys\([^,]+,\s*'(SOFTWARE|SYSTEM|')\)"
    Add-Assertion 'installer.cleanup.legacy-registry' ($cleanupRegistry -and -not $unsafeRootDelete) @{
        unsafe_root_delete = $unsafeRootDelete
    }

    $preserve = Has-All $iss @(
        'Deseja manter a identidade TGDesk existente?',
        '{commonappdata}\TGDesk\identity\device.json',
        '{commonappdata}\TGDesk\identity\technician.dat',
        "DelTree(ExpandConstant('{commonappdata}\TGDesk\state')",
        "DelTree(ExpandConstant('{commonappdata}\TGDesk\logs')"
    )
    Add-Assertion 'installer.identity.optional-preserve' $preserve @{
        identity_directory_not_deleted_on_preserve_branch = $preserve
    }

    $noEarlyStart = ($iss.IndexOf('sc.exe create TGDesk') -gt $iss.IndexOf('if CurStep = ssPostInstall')) -and
        ($iss -notmatch '\[Run\]')
    Add-Assertion 'installer.no-autostart-before-finish' $noEarlyStart @{
        run_section_absent = ($iss -notmatch '\[Run\]')
    }

    $reboot = Has-All $iss @(
        'AlwaysRestart=yes', 'if WizardSilent then', 'ExecAsOriginalUser',
        'StartWithWindowsConfigured'
    )
    Add-Assertion 'installer.reboot-contract' $reboot @{
        interactive_always_restarts = $iss.Contains('AlwaysRestart=yes')
        app_launch_silent_only = $iss.Contains('if WizardSilent then')
    }

    $singleProduct = Has-All $iss @(
        'Source: "stage-unified\*"', 'sc.exe create TGDesk',
        '{app}\tgdesk.exe', 'TGDesk Service'
    ) -and Has-All $runner @(
        'rustdesk_service', 'LoadLibraryA("tgdesk_agent.dll")',
        'StartTgdeskServiceHost'
    )
    Add-Assertion 'runtime.service-ui-contract' $singleProduct @{
        executable = 'tgdesk.exe'
        roles = @('interactive', '--service')
    }

    # Compila um binário de teste Windows no container e o executa no host.
    $testExe = Join-Path $scratch 'updater-tests.exe'
    & docker run --rm -v "${repo}:/repo" -w /repo/client-agent `
        -e GOOS=windows -e GOARCH=amd64 -e CGO_ENABLED=0 golang:1.22-alpine `
        go test -c -o "/repo/testlab/artifacts/updater-contract-tests.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar testes Windows do atualizador.' }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'artifacts\updater-contract-tests.exe') `
        -Destination $testExe -Force
    $testProcess = Start-Process -FilePath $testExe -ArgumentList '-test.v' `
        -Wait -PassThru -NoNewWindow
    $unitPassed = $testProcess.ExitCode -eq 0
    Add-Assertion 'update.modular.changed-files' $unitPassed @{
        executable_test = 'TestSelectChangedModules'
        service_module_requires_installer = $true
    }
    Add-Assertion 'update.rollback' $unitPassed @{
        executable_test = 'TestModuleTransactionAndRollback'
        restores_replaced = $true
        removes_new_files = $true
    }

    $force = Has-All $runner @('--tgdesk-update', 'TGDeskAgentUpdate') -and
        Has-All $updater @('recoveryAPIBase', 'runManualUpdate()', 'getUpdate(')
    Add-Assertion 'update.force-command' $force @{
        command = 'tgdesk.exe --tgdesk-update'
        public_recovery_fallback = $updater.Contains('recoveryAPIBase')
    }

    $metadataPath = Join-Path $repo "installers\output\tgdesk-installer-$version.metadata.json"
    $installerPath = Join-Path $repo "installers\output\tgdesk-installer-$version.exe"
    $artifactOK = (Test-Path -LiteralPath $metadataPath) -and
        (Test-Path -LiteralPath $installerPath)
    $artifactDetails = @{ version = $version }
    if ($artifactOK) {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
        $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $artifactOK = ([string]$metadata.version -eq $version) -and
            ([string]$metadata.installer.sha256 -eq $actualHash) -and
            ((Get-Content -LiteralPath (Join-Path $repo 'installers\stage-unified\version.txt') -Raw).Trim() -eq $version)
        $artifactDetails = @{
            version = $version
            sha256 = $actualHash
            size = (Get-Item -LiteralPath $installerPath).Length
            stage_files = @($metadata.stage_files).Count
        }
    }
    Add-Assertion 'installer.artifact.signature-version' $artifactOK $artifactDetails

    $failed = @($assertions | Where-Object state -eq 'failed')
    $report = [ordered]@{
        schema_version = 1
        scenario = 'installer-update-contract'
        state = if ($failed.Count) { 'failed' } else { 'passed' }
        measured_at = [DateTimeOffset]::UtcNow.ToString('o')
        version = $version
        assertions = $assertions
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $artifactPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifactPath -Encoding utf8
    $report | ConvertTo-Json -Depth 5
    if ($failed.Count) { exit 1 }
} finally {
    if ((Test-Path -LiteralPath $scratch) -and
        $scratch.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
