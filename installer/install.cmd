@echo off
setlocal

set "TARGET=%LocalAppData%\TGdesk"
set "ZIPFILE=%~dp0TGDesk.zip"

if exist "%TARGET%" rmdir /S /Q "%TARGET%"
mkdir "%TARGET%" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%ZIPFILE%' -DestinationPath '%TARGET%' -Force"
if errorlevel 1 exit /b 1

start "" "%TARGET%\TGdesk.exe"
exit /b 0
