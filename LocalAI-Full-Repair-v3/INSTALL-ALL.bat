@echo off
setlocal EnableExtensions
title Local AI - Full Installer
chcp 65001 >nul
cd /d "%~dp0"
echo.
echo === Local AI - Full Installer ===
echo This window will stay open and show any error.
echo.
if not exist "%~dp0INSTALL-ALL.ps1" (
  echo ERROR: Required PowerShell script was not found.
  set "RC=2"
  goto :finish
)
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-ALL.ps1"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
  echo SUCCESS: All installation steps finished.
) else (
  echo.
  echo FAILED with exit code %RC%. Read the error above before closing.
  echo Run DIAGNOSE.bat from the extracted FULL package and send its report.
)
:finish
echo.
echo Press any key to close this window.
pause >nul
exit /b %RC%
