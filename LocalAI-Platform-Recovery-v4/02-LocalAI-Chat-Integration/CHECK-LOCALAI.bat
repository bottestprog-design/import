@echo off
setlocal
chcp 65001 >nul
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CHECK-LOCALAI.ps1"
echo.
pause
