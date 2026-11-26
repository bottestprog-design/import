@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RESTORE-OPENWEBUI-STYLE.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo STYLE RESTORE FAILED. Existing Open WebUI data was not changed.
pause
exit /b %RC%
