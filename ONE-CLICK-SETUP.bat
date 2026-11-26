@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title LocalAI Studio Complete - v2.3.0
echo ============================================================
echo LOCALAI STUDIO COMPLETE v2.3.0
echo Reuses the existing Ollama and Qwen installation.
echo Does not reinstall Ollama, pull Qwen, or delete model files.
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0APPLY-V2.3.0.ps1"
if errorlevel 1 goto :failed
call "%~dp0RUN-REPAIR.bat"
exit /b %ERRORLEVEL%
:failed
echo.
echo PATCH FAILED. Setup was not started. Keep this folder intact.
pause
exit /b 1
