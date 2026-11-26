@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================================
echo LOCALAI STUDIO COMPLETE - PLATFORM REPAIR v2.4.0
echo Full manifest and PowerShell syntax verification.
echo Native exit-code helper tests run before installation.
echo Existing Ollama and Qwen model files remain untouched.
echo ============================================================
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
if errorlevel 1 goto :failed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0TEST-EXITCODE-RUNNER.ps1"
if errorlevel 1 goto :failed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REPAIR-AND-RESUME.ps1"
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
  echo PLATFORM REPAIR / RESUME FINISHED.
  echo See D:\LocalAI\Platform\PLATFORM-STATUS.txt
) else if "%RC%"=="10" (
  echo Another LocalAI setup process already owns the lock.
  echo No duplicate installer was started. Check the other setup window.
) else (
  echo REPAIR EXIT CODE: %RC%.
  echo See D:\LocalAI\Logs and keep the venv and model folders.
)
goto :end
:failed
echo PACKAGE OR NATIVE RUNNER CHECK FAILED. Setup was not started.
set "RC=1"
:end
echo.
pause
exit /b %RC%
