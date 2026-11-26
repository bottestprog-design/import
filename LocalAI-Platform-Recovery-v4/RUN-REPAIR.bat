@echo off
setlocal EnableExtensions
chcp 65001 >nul
title LocalAI - Platform Recovery v4
cd /d "%~dp0"
echo ==================================================
echo LOCALAI PLATFORM RECOVERY v4
echo Repairs only the missing chat platform.
echo Does NOT pull, reinstall, restart, move, or delete Ollama models.
echo ==================================================
echo.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
if errorlevel 1 goto :failed
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REPAIR-PLATFORM.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo RECOVERY COMPLETED. Open WebUI should be available at http://127.0.0.1:8080
) else (
  echo RECOVERY FAILED with exit code %RC%.
  echo Read D:\LocalAI\Logs\platform-recovery-*.log and platform-install-*.log
)
goto :finish
:failed
echo PACKAGE INTEGRITY CHECK FAILED. Do not run the repair.
set "RC=1"
:finish
echo.
echo Press any key to close.
pause >nul
exit /b %RC%
