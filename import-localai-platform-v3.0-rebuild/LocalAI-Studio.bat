@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0" >nul 2>&1
if errorlevel 1 goto :NO_ROOT

set "PSHOST=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PSHOST%" set "PSHOST=powershell.exe"

set "TASK=%~1"
if not defined TASK set "TASK=start"

if /I "%TASK%"=="start" goto :START_TASK
if /I "%TASK%"=="repair" goto :REPAIR_TASK
if /I "%TASK%"=="install" goto :REPAIR_TASK
if /I "%TASK%"=="stop" goto :STOP_TASK
if /I "%TASK%"=="check" goto :CHECK_TASK
if /I "%TASK%"=="test" goto :TEST_TASK
if /I "%TASK%"=="filters" goto :FILTERS_TASK
if /I "%TASK%"=="restore-style" goto :RESTORE_TASK
if /I "%TASK%"=="verify" goto :VERIFY_TASK
if /I "%TASK%"=="help" goto :HELP
goto :UNKNOWN

:START_TASK
if not exist "%~dp0VERIFY-PACKAGE.ps1" (
    echo MISSING FILE: "%~dp0VERIFY-PACKAGE.ps1"
    pause
    exit /b 2
)
if not exist "%~dp0REPAIR-AND-RESUME.ps1" (
    echo MISSING FILE: "%~dp0REPAIR-AND-RESUME.ps1"
    pause
    exit /b 2
)
if not exist "%~dp0START-CHAT.ps1" (
    echo MISSING FILE: "%~dp0START-CHAT.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
if errorlevel 1 goto :FAILED
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REPAIR-AND-RESUME.ps1"
if errorlevel 1 goto :FAILED
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0START-CHAT.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto :FAILED
echo.
echo [OK] LocalAI Studio is running at http://127.0.0.1:8080
exit /b 0

:REPAIR_TASK
if not exist "%~dp0VERIFY-PACKAGE.ps1" (
    echo MISSING FILE: "%~dp0VERIFY-PACKAGE.ps1"
    pause
    exit /b 2
)
if not exist "%~dp0REPAIR-AND-RESUME.ps1" (
    echo MISSING FILE: "%~dp0REPAIR-AND-RESUME.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
if errorlevel 1 goto :FAILED
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0REPAIR-AND-RESUME.ps1"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" goto :FAILED
echo.
echo [OK] Repair/setup completed.
goto :MAINTENANCE_DONE

:STOP_TASK
if not exist "%~dp0STOP-CHAT.ps1" (
    echo MISSING FILE: "%~dp0STOP-CHAT.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0STOP-CHAT.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:CHECK_TASK
if not exist "%~dp0CHECK-LOCALAI.ps1" (
    echo MISSING FILE: "%~dp0CHECK-LOCALAI.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CHECK-LOCALAI.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:TEST_TASK
if not exist "%~dp0VERIFY-MODEL.ps1" (
    echo MISSING FILE: "%~dp0VERIFY-MODEL.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-MODEL.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:FILTERS_TASK
if not exist "%~dp0IMPORT-FILTERS.ps1" (
    echo MISSING FILE: "%~dp0IMPORT-FILTERS.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0IMPORT-FILTERS.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:RESTORE_TASK
if not exist "%~dp0RESTORE-OPENWEBUI-STYLE.ps1" (
    echo MISSING FILE: "%~dp0RESTORE-OPENWEBUI-STYLE.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0RESTORE-OPENWEBUI-STYLE.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:VERIFY_TASK
if not exist "%~dp0VERIFY-PACKAGE.ps1" (
    echo MISSING FILE: "%~dp0VERIFY-PACKAGE.ps1"
    pause
    exit /b 2
)
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0VERIFY-PACKAGE.ps1"
set "RC=%ERRORLEVEL%"
goto :MAINTENANCE_DONE

:MAINTENANCE_DONE
echo.
if "%RC%"=="0" (
    echo Operation finished successfully.
) else (
    echo Operation failed with exit code %RC%.
)
pause
exit /b %RC%

:FAILED
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" set "RC=1"
echo.
echo LocalAI operation failed with exit code %RC%.
echo Check the latest logs in D:\LocalAI\Logs and D:\LocalAI\Platform\Logs.
pause
exit /b %RC%

:UNKNOWN
echo Unknown command: %TASK%
goto :HELP

:HELP
echo.
echo LocalAI Studio v3.2
echo.
echo Double-click this file to verify, repair if needed, and start the chat.
echo.
echo Optional commands:
echo   LocalAI-Studio.bat repair        Repair or install the platform
echo   LocalAI-Studio.bat stop          Stop Open WebUI only; Ollama/Qwen stay running
echo   LocalAI-Studio.bat check         Run system diagnostics
echo   LocalAI-Studio.bat test          Test a real Qwen response
echo   LocalAI-Studio.bat filters       Import the three optional Open WebUI filters
echo   LocalAI-Studio.bat restore-style Restore the original Open WebUI CSS
echo   LocalAI-Studio.bat verify        Verify every file and launcher dependency
echo.
pause
exit /b 0

:NO_ROOT
echo Could not access the LocalAI project folder: "%~dp0"
pause
exit /b 2
