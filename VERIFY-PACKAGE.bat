@echo off
setlocal
cd /d "%~dp0"
chcp 65001 >nul
echo LOCALAI STUDIO v2.4.0 - FULL PACKAGE VERIFICATION
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo PACKAGE CHECK FAILED. Do not run setup.
if "%RC%"=="0" echo PACKAGE VERIFIED. Run ONE-CLICK-SETUP.bat.
pause
exit /b %RC%
