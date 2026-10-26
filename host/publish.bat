@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
set GFIX_RC=%errorlevel%
pause
exit /b %GFIX_RC%
