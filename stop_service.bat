@echo off
REM Parar serviço via WMI com elevação

echo === PARANDO SERVICO TGDESK ===

REM Tentar via sc.exe
sc stop TGDesk 2>nul
sc stop TGDeskService 2>nul
sc stop TGDeskAgent 2>nul

REM Matar via WMI
wmic process where name="tgdesk.exe" delete /nointeractive 2>nul

REM Matar via taskkill (forçado)
taskkill /IM tgdesk.exe /F /T 2>nul

timeout /t 5

echo === INICIANDO UNICA INSTANCIA ===
start "" "C:\Program Files\TGDesk\tgdesk.exe"

echo.
echo TGDesk devera abrir em instancia unica
timeout /t 15
