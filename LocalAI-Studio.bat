@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
set "TASK=%~1"
if not defined TASK set "TASK=start"

if /I "%TASK%"=="start" goto :start
if /I "%TASK%"=="repair" goto :repair
if /I "%TASK%"=="install" goto :repair
if /I "%TASK%"=="stop" goto :stop
if /I "%TASK%"=="check" goto :check
if /I "%TASK%"=="test" goto :test
if /I "%TASK%"=="filters" goto :filters
if /I "%TASK%"=="restore-style" goto :restore
if /I "%TASK%"=="help" goto :help
goto :unknown

:start
call :verify
if errorlevel 1 goto :failed
call :run REPAIR-AND-RESUME.ps1
if errorlevel 1 goto :failed
call :run START-CHAT.ps1
if errorlevel 1 goto :failed
exit /b 0

:repair
call :verify
if errorlevel 1 goto :failed
call :run REPAIR-AND-RESUME.ps1
if errorlevel 1 goto :failed
echo.
echo Repair and setup completed.
pause
exit /b 0

:stop
call :run STOP-CHAT.ps1
goto :done

:check
call :run CHECK-LOCALAI.ps1
goto :done

:test
call :run VERIFY-MODEL.ps1
goto :done

:filters
call :run IMPORT-FILTERS.ps1
goto :done

:restore
call :run RESTORE-OPENWEBUI-STYLE.ps1
goto :done

:verify
call :run VERIFY-PACKAGE.ps1
exit /b %ERRORLEVEL%

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0%~1"
exit /b %ERRORLEVEL%

:done
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo The requested LocalAI operation failed. Read the message above.
) else (
  echo Operation finished.
)
pause
exit /b %RC%

:unknown
echo Unknown command: %TASK%
:help
echo.
echo LocalAI Studio v2.5
echo.
echo Double-click this file to start chat. The first run installs or repairs only the chat platform.
echo.
echo Optional commands:
echo   LocalAI-Studio.bat repair        Repair or install the platform
echo   LocalAI-Studio.bat stop          Stop Open WebUI only; Ollama/Qwen stay running
echo   LocalAI-Studio.bat check         Run system diagnostics
echo   LocalAI-Studio.bat test          Test a real Qwen response
echo   LocalAI-Studio.bat filters       Import the three optional Open WebUI filters
echo   LocalAI-Studio.bat restore-style Restore the original Open WebUI CSS
echo.
pause
exit /b 0

:failed
echo.
echo LocalAI did not start. Check the latest logs in D:\LocalAI\Logs and D:\LocalAI\Platform\Logs.
pause
exit /b 1
