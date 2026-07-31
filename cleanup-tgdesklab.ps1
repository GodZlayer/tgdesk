# ==========================================
# CLEANUP: Remove TGDESKLAB from Windows
# ==========================================

Write-Host "🧹 Iniciando limpeza de TGDESKLAB..." -ForegroundColor Yellow

# 1. Para serviço
Write-Host "  [1/5] Parando serviço TGDesk..."
Stop-Service -Name "TGDesk" -Force -ErrorAction SilentlyContinue
Write-Host "  ✓ Serviço parado"

# 2. Mata processos
Write-Host "  [2/5] Killando processos tgdesk..."
Get-Process -Name "tgdesk" -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "  ✓ Processos removidos"

# 3. Limpa registry
Write-Host "  [3/5] Limpando registry..."
Remove-Item "HKLM:\Software\TGDesk" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "HKCU:\Software\TGDesk" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "  ✓ Registry limpo"

# 4. Remove diretórios de cache/resquícios
Write-Host "  [4/5] Removendo diretórios de resquício..."
$paths = @(
    "C:\Users\$env:USERNAME\AppData\Local\TGDesk",
    "C:\Users\$env:USERNAME\AppData\Roaming\TGDesk",
    "C:\ProgramData\TGDesk"
)
foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removido: $path"
    }
}

# 5. Verifica limpeza
Write-Host "  [5/5] Verificando limpeza..."
$remaining = Get-Process -Name "tgdesk" -ErrorAction SilentlyContinue
if ($remaining) {
    Write-Host "  ⚠️ Ainda há processos: $remaining" -ForegroundColor Red
    exit 1
} else {
    Write-Host "  ✓ Limpeza concluída com sucesso!" -ForegroundColor Green
    exit 0
}
