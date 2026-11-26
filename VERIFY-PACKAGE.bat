@echo off
setlocal
cd /d "%~dp0"
echo ============================================================
echo LOCAL AI - PACKAGE INTEGRITY CHECK
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo PACKAGE CHECK FAILED. Download and extract the ZIP again.
if "%RC%"=="0" echo PACKAGE FILES VERIFIED. You may run INSTALL-PLATFORM.bat.
echo.
pause
exit /b %RC%
