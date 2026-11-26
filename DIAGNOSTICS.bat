@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0DIAGNOSTICS.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Some checks need attention; read the report path above.
pause
exit /b %RC%
