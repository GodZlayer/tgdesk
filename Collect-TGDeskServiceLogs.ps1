$roots = @(
    'C:\Windows\System32\config\systemprofile\AppData\Roaming\TGDesk',
    'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\TGDesk',
    'C:\Windows\ServiceProfiles\NetworkService\AppData\Roaming\TGDesk'
)
$files = Get-ChildItem -LiteralPath $roots -Recurse -File -Filter '*.log' `
    -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
$output = 'C:\ProgramData\TGDesk\logs\remote-core.log'
if (-not $files) {
    'Nenhum log encontrado nos perfis de servico.' |
        Set-Content -LiteralPath $output
    exit
}
$files | Select-Object FullName, Length, LastWriteTime |
    Out-String | Set-Content -LiteralPath $output
Add-Content -LiteralPath $output "`r`n=== CONTEUDO ==="
$files | Select-Object -First 5 | ForEach-Object {
    Add-Content -LiteralPath $output "`r`n=== $($_.FullName) ==="
    Get-Content -LiteralPath $_.FullName -Tail 400 |
        Add-Content -LiteralPath $output
}
