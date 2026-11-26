@echo off
setlocal
cd /d "%~dp0"
title LocalAI - Apply Setup Fix
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-FIX.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo FIX WAS NOT APPLIED. Extract the fix into the original package folder and overwrite files.
) else (
  echo FIX APPLIED. Now run ONE-TIME-SETUP.bat.
)
echo.
pause
exit /b %RC%
