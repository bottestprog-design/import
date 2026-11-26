@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title LocalAI Studio Complete v2.4.0
echo ============================================================
echo LOCALAI STUDIO COMPLETE v2.4.0
echo Uses existing Ollama, Qwen and project Python where valid.
echo Does not reinstall Ollama, download Qwen, or delete model files.
echo Verifies all files and PowerShell syntax before starting.
echo ============================================================
call "%~dp0RUN-REPAIR.bat"
exit /b %ERRORLEVEL%
