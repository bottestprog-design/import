@echo off
setlocal
cd /d "%~dp0"
call "%~dp0START-LOCALAI.bat"
exit /b %ERRORLEVEL%
