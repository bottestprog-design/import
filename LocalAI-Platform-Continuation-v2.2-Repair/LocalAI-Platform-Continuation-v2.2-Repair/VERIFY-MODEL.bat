@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-MODEL.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo MODEL TEST FAILED. See D:\LocalAI\Logs and Ollama server.log.
pause
exit /b %RC%
