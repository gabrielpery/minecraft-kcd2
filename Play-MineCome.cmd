@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Play-MineCome.ps1" %*
set "MineComeExit=%ERRORLEVEL%"
if not "%MineComeExit%"=="0" echo MineCome could not start. Read the error above; no administrator mode is needed.
if "%~1"=="" pause
exit /b %MineComeExit%
