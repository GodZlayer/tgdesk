$ErrorActionPreference = "Continue"

Write-Host "=== Iniciando TGDesk com debug ==="
$exePath = "C:\Program Files\TGDesk\tgdesk.exe"

Write-Host "Executável: $exePath"
Write-Host "Tamanho: $(Get-Item $exePath | % Length) bytes"
Write-Host ""

try {
    Write-Host "Iniciando processo..."
    $proc = Start-Process -FilePath $exePath -PassThru -ErrorAction Stop
    Write-Host "✓ PID: $($proc.Id)"
    Write-Host ""

    Write-Host "Aguardando 15 segundos..."
    $proc.WaitForExit(15000)

    if ($proc.HasExited) {
        Write-Host "❌ Processo saiu"
        Write-Host "Exit code: $($proc.ExitCode)"
    } else {
        Write-Host "✅ Ainda rodando"
    }
} catch {
    Write-Host "❌ Erro: $_"
}

Write-Host ""
Write-Host "=== Verificando diretório ==="
Get-Item "C:\Program Files\TGDesk"

Write-Host ""
Write-Host "=== Verificando permissões ==="
icacls "C:\Program Files\TGDesk\tgdesk.exe"
