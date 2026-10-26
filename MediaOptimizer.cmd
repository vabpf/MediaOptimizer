@echo off
setlocal
title Media Optimizer

rem Interactive entry point: double-click this file, or drop a folder onto it.
rem For scripted / scheduled runs use optimize.cmd instead (no prompts).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1" %*
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" echo   Finished with errors - exit code %CODE%.
echo   Press any key to close this window.
pause >nul

exit /b %CODE%
