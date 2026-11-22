@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0geocapture_phone_check.ps1"
set "geoPhoneCheckExit=%errorlevel%"
pause
exit /b %geoPhoneCheckExit%