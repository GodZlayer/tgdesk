$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'tgdesk.exe'
Write-Host "Verificando atualizacoes do TGDesk..." -ForegroundColor Cyan
& $exe --tgdesk-update
if ($LASTEXITCODE -eq 10) {
    Write-Host "Atualizacao baixada e iniciada." -ForegroundColor Green
} elseif ($LASTEXITCODE -eq 0) {
    Write-Host "TGDesk ja esta atualizado." -ForegroundColor Green
} else {
    Write-Host "Falha ao verificar atualizacoes (codigo $LASTEXITCODE)." -ForegroundColor Red
}
