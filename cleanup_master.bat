@echo off
setlocal enabledelayedexpansion

echo === LIMPEZA DO ADMIN MASTER ===
echo.
echo Identidade sera preservada em: %%APPDATA%%\TGDesk\config\
echo.

echo === 1. Matando processos ===
taskkill /IM tgdesk.exe /F /T 2>nul
timeout /t 5 /nobreak

echo === 2. Assumindo propriedade ===
echo Executando takeown...
cd /d "C:\Program Files"
takeown /F "TGDesk Client" /R /D Y
icacls "TGDesk Client" /grant:r "%username%:F" /T /C

echo === 3. Deletando pasta paralela ===
echo Removendo: C:\Program Files\TGDesk Client
rmdir /S /Q "TGDesk Client" 2>nul

if exist "TGDesk Client" (
    echo ERRO: Pasta ainda existe
) else (
    echo SUCESSO: Pasta deletada
)

echo === 4. Iniciando TGDesk v0.4.0 ===
start "" "C:\Program Files\TGDesk\tgdesk.exe"

echo === LIMPEZA CONCLUIDA ===
echo.
echo O TGDesk v0.4.0 devera abrir em breve
echo Identidade preservada
timeout /t 10
