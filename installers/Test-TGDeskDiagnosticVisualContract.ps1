param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$agentPath = Join-Path $Root 'client-agent\cmd\agent\diagnostics.go'
$catalogPath = Join-Path $Root 'server\api-core\internal\handlers\diagnostics.go'
$uiPath = Join-Path $Root 'client-rustdesk-src\flutter\lib\tgdesk\diagnostics_dialog.dart'

$agent = Get-Content -LiteralPath $agentPath -Raw
$catalog = Get-Content -LiteralPath $catalogPath -Raw
$ui = Get-Content -LiteralPath $uiPath -Raw

$catalogIds = [regex]::Matches($catalog, '\{"id":\s*"([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } |
    Where-Object { $_ -ne 'all_tests' } |
    Sort-Object -Unique
$executorIds = [regex]::Matches($agent, 'case\s+"([^"]+)":') |
    ForEach-Object { $_.Groups[1].Value } |
    Sort-Object -Unique

$missingExecutors = @($catalogIds | Where-Object { $_ -notin $executorIds })
$missingCatalog = @($executorIds | Where-Object { $_ -notin $catalogIds })
if ($missingExecutors.Count -gt 0) {
    throw "Testes sem executor: $($missingExecutors -join ', ')"
}
if ($missingCatalog.Count -gt 0) {
    throw "Executores fora do catálogo: $($missingCatalog -join ', ')"
}

$resultVisualStart = $ui.IndexOf('Widget _resultVisual(')
$suiteVisualStart = $ui.IndexOf('Widget _suiteResultVisual(')
if ($resultVisualStart -lt 0 -or $suiteVisualStart -le $resultVisualStart) {
    throw 'Não foi possível localizar a área visual de resultados.'
}
$resultVisual = $ui.Substring($resultVisualStart, $suiteVisualStart - $resultVisualStart)
if ($resultVisual -match 'JsonEncoder|jsonEncode') {
    throw 'A área de resultados ainda contém renderização de JSON bruto.'
}
if ($resultVisual -notmatch '_visualValue') {
    throw 'A área de resultados não usa o renderizador visual estruturado.'
}

[pscustomobject]@{
    status = 'PASS'
    catalog_tests = $catalogIds.Count
    executors = $executorIds.Count
    visual_renderer = $true
} | ConvertTo-Json -Compress
