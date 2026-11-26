@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0STOP-CHAT.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo STOP FAILED. No unrelated process was stopped.
pause
exit /b %RC%
