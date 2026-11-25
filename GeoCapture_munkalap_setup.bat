@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0test\tools\fieldwork_setup_test.ps1"
if errorlevel 1 goto failed
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0geocapture_fieldwork_setup.ps1" -Apply
if errorlevel 1 goto failed
call flutter pub get
if errorlevel 1 goto failed
call flutter test
if errorlevel 1 goto failed
call flutter analyze --no-fatal-infos
if errorlevel 1 goto failed
echo KESZ. Az Android Studio SDK Managerben az API 36 SDK legyen telepitve.
echo Ezutan a korabbi GeoCapture_Android.bat fajllal inditsd a telefonon.
pause
exit /b 0
:failed
echo HIBA: A fenti lepes sikertelen, a tovabbi lepesek nem futottak le.
pause
exit /b 1