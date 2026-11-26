@echo off
setlocal EnableExtensions
chcp 65001 >nul
title LocalAI - Chat Platform Installer
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALL-CHAT-PLATFORM.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Installation failed. Check D:\LocalAI\Logs.
pause
exit /b %RC%
