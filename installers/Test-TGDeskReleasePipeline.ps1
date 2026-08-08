$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pipeline = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Release-TGDesk.ps1') -Raw

function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$agentBuild = $pipeline.IndexOf('go build -buildmode=c-shared -o $agentDll ./cmd/agent')
$flutterBuild = $pipeline.IndexOf('flutter build windows --release')
Assert-Contract ($agentBuild -ge 0) `
    'O pipeline nao compila a DLL embutida do agente.'
Assert-Contract ($flutterBuild -gt $agentBuild) `
    'A DLL do agente precisa ser compilada antes do Flutter empacota-la.'
Assert-Contract ($pipeline -match 'Join-Path \$agentRoot ''tgdesk_agent\.dll''') `
    'O pipeline precisa atualizar a DLL que o CMake inclui.'

$cmake = Get-Content -LiteralPath (Join-Path $root 'client-rustdesk-src\flutter\windows\CMakeLists.txt') -Raw
Assert-Contract ($cmake -match 'client-agent/tgdesk_agent\.dll') `
    'O build Flutter nao inclui a DLL do agente no pacote Windows.'

Write-Host 'TGDesk release pipeline: agente embutido compilado antes do pacote.'
