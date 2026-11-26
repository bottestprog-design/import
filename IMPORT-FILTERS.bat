@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0IMPORT-FILTERS.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo FILTER IMPORT FAILED. Check API key, admin role, and Open WebUI readiness.
pause
exit /b %RC%
