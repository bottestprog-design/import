@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0BACKUP-LOCALAI.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Backup failed; review the error above.
pause
exit /b %RC%
