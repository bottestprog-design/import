@echo off
setlocal EnableExtensions
title Local AI - Recover Model Download
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo === LOCAL AI - MODEL DOWNLOAD RECOVERY (V3 - SAFE SERVER STORE) ===
echo This does NOT reinstall Ollama or delete model/cache files.
echo The native error output is captured safely so PowerShell cannot hide it.
echo.
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
if not exist "%~dp0RECOVER-MODEL.ps1" (
  echo ERROR: RECOVER-MODEL.ps1 is missing. Extract the whole ZIP first.
  set "RC=2"
  goto :finish
)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RECOVER-MODEL.ps1"
set "RC=%ERRORLEVEL%"
:finish
echo.
if "%RC%"=="0" (
  echo SUCCESS: Model and local inference test completed.
) else (
  echo FAILED with exit code %RC%.
  echo Open the newest D:\LocalAI\Logs\model-recovery-v3-*.log and send it here.
)
echo.
echo Press any key to close this window.
pause >nul
exit /b %RC%
