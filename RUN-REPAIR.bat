@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo LOCAL AI - PLATFORM CONTINUATION REPAIR v2.3
echo Fixes PowerShell 5.1 package-detection failure.
echo Watches an existing installer and never starts a duplicate.
echo Does not reinstall Ollama or download Qwen.
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
if errorlevel 1 goto :failed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REPAIR-AND-RESUME.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo PLATFORM REPAIR / RESUME FINISHED.
  echo See D:\LocalAI\Platform\PLATFORM-STATUS.txt
) else (
  echo REPAIR EXIT CODE: %RC%.
  echo See D:\LocalAI\Logs and do not delete the venv or model folders.
)
goto :end
:failed
echo PACKAGE INTEGRITY FAILED. Do not run the repair.
set "RC=1"
:end
echo.
pause
exit /b %RC%
