@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ADD-FAST-MODEL.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo OPTIONAL MODEL ADD-ON FAILED. Existing Qwen 9B was not intentionally changed.
pause
exit /b %RC%
