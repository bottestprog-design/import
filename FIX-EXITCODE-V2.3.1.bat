@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title LocalAI Studio v2.3.1 - Exit Code Hotfix
echo ============================================================
echo LOCALAI STUDIO COMPLETE v2.3.1
echo Fixes Windows PowerShell 5.1 native process exit-code handling.
echo Does not reinstall Ollama or download/delete Qwen.
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0FIX-EXITCODE-V2.3.1.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo HOTFIX FAILED. Do not start setup; keep the logs and show the error.
if "%RC%"=="0" echo Hotfix applied. Now run ONE-CLICK-SETUP.bat.
pause
exit /b %RC%
