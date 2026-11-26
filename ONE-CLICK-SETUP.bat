@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title LocalAI Studio Complete v2.3.1
echo ============================================================
echo LOCALAI STUDIO COMPLETE v2.3.1
echo Dedicated PowerShell 5.1 process exit-code repair.
echo Reuses existing Ollama, Qwen and D:\LocalAI\Platform\.venv.
echo Does not reinstall Ollama, pull Qwen, or delete model files.
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0FIX-EXITCODE-V2.3.1.ps1"
if errorlevel 1 goto :failed
call "%~dp0RUN-REPAIR.bat"
exit /b %ERRORLEVEL%
:failed
echo.
echo HOTFIX FAILED. Setup was not started. Keep the folder intact.
pause
exit /b 1
