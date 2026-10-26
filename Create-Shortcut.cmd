@echo off
setlocal
title Media Optimizer - Create Start menu shortcut

rem Installs Media Optimizer for the current user and adds it to the Start menu.
rem Run once. Undo with:  Create-Shortcut.cmd -Remove

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0create-shortcut.ps1" %*
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" echo   Stopped - exit code %CODE%.
echo   Press any key to close this window.
pause >nul

exit /b %CODE%
