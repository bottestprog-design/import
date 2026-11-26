@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-CHAT.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo START FAILED. Check D:\LocalAI\Platform\Logs and the message above.
pause
exit /b %RC%
