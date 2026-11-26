@echo off
setlocal EnableExtensions
title Local AI - Read Only Diagnostics
chcp 65001 >nul
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
if not exist "%~dp0DIAGNOSE.ps1" (echo ERROR: DIAGNOSE.ps1 missing.& pause & exit /b 2)
"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0DIAGNOSE.ps1"
echo.
echo Press any key to close.
pause >nul
