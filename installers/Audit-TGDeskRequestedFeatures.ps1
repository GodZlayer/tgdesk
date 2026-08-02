param([string]$OutputPath = '')

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP 'tgdesk-requested-features-audit.json'
}

function Match-Evidence([string]$RelativePath, [string[]]$Patterns) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $hits = foreach ($pattern in $Patterns) {
        Select-String -Path $path -Pattern $pattern -CaseSensitive:$false |
            ForEach-Object { '{0}:{1}:{2}' -f $RelativePath, $_.LineNumber, $_.Line.Trim() }
    }
    return @($hits | Select-Object -Unique)
}

$checks = [ordered]@{
    diagnostics_api = Match-Evidence 'server\api-core\internal\handlers\diagnostics.go' @('diagnostic','test_type','progress')
    diagnostics_agent = Match-Evidence 'client-agent\cmd\agent\diagnostics.go' @('cpu','gpu','disk','badblock','internet','network')
    diagnostics_ui = Match-Evidence 'client-rustdesk-src\flutter\lib\tgdesk\diagnostics_dialog.dart' @('diagnostic','CPU','GPU','disco','internet','log')
    branding_api = Match-Evidence 'server\api-core\internal\handlers\branding.go' @('branding','favicon','logo','permission')
    branding_ui = Match-Evidence 'client-rustdesk-src\flutter\lib\tgdesk\branding_page.dart' @('crop','preview','logo','favicon','brand')
    support_api = Match-Evidence 'server\api-core\internal\handlers\support.go' @('ticket','offer','work_order','scope','rating','standalone','virtual','presencial')
    support_ui = Match-Evidence 'client-rustdesk-src\flutter\lib\tgdesk\support_page.dart' @('chamado','ordem','escopo','recusar','nota','virtual','presencial')
    hierarchy_api = @(Match-Evidence 'server\api-core\internal\handlers\subnetworks.go' @('organization','network','subnetwork','device')) + @(Match-Evidence 'server\api-core\internal\handlers\technicians.go' @('suspend','cascade','supervisor','freelancer'))
    remote_advanced = Match-Evidence 'client-rustdesk-src\flutter\lib\tgdesk\remote_session_page.dart' @('clipboard','file','draw','pen','eraser','keyboard','mouse','fullscreen')
    roles_ui = Match-Evidence 'client-rustdesk-src\flutter\lib\tgdesk\ui_contract.dart' @('client','standalone','freelancer','supervisor','super_admin')
}

$result = [ordered]@{
    measured_at = [DateTimeOffset]::UtcNow.ToString('o')
    root = $root
    checks = $checks
    migrations = @(Get-ChildItem (Join-Path $root 'server\migrations') -File |
        Sort-Object Name | ForEach-Object Name)
}
$json = $result | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($OutputPath, $json, (New-Object Text.UTF8Encoding($false)))
$OutputPath
