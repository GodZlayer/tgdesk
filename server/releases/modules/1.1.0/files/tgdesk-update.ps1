$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'tgdesk-updater.exe'
Write-Host "Verificando atualizacoes do TGDesk..." -ForegroundColor Cyan
& $exe -check
if ($LASTEXITCODE -eq 10) {
    Write-Host "Atualizacao disponivel. Aplicando..." -ForegroundColor Yellow
    & $exe -update
    Write-Host "Concluido (codigo $LASTEXITCODE)." -ForegroundColor Green
} elseif ($LASTEXITCODE -eq 0) {
    Write-Host "TGDesk ja esta atualizado." -ForegroundColor Green
} else {
    Write-Host "Falha ao verificar atualizacoes (codigo $LASTEXITCODE)." -ForegroundColor Red
}
