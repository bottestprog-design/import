@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-CHAT.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" (
  echo.
  echo LocalAI did not start. Read the message above and the newest logs in D:\LocalAI\Platform\Logs.
  pause
)
exit /b %RC%
