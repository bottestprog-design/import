@echo off
setlocal
cd /d "%~dp0"
call "%~dp0RUN-REPAIR.bat"
exit /b %ERRORLEVEL%
