@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0geocapture_android.ps1"
set "geoAndroidExit=%errorlevel%"
if not "%geoAndroidExit%"=="0" pause
exit /b %geoAndroidExit%