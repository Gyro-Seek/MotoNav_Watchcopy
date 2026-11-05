@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup.ps1"
set "taskExit=%ERRORLEVEL%"
echo.
pause
exit /b %taskExit%
