@echo off
setlocal
chcp 65001 >nul
set "PLATFORM=D:\LocalAI\Platform"
set "PY=%PLATFORM%\.venv\Scripts\python.exe"
if not exist "%PY%" (
  echo Run RUN-REPAIR.bat first to prepare the platform.
  pause
  exit /b 2
)
if not exist "%PLATFORM%\Logs" mkdir "%PLATFORM%\Logs"
copy /y "%~dp0DASHBOARD-SERVER.py" "%PLATFORM%\DASHBOARD-SERVER.py" >nul
cd /d "%PLATFORM%"
"%PY%" "%PLATFORM%\DASHBOARD-SERVER.py"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Dashboard exit code %RC%. Check "%PLATFORM%\Logs\dashboard.log".
pause
exit /b %RC%
