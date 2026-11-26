@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CHECK-LOCALAI.ps1"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
