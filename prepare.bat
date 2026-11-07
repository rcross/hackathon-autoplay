@echo off
rem Double-click this file to download the submissions and build the playlists.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare.ps1" %*
echo.
pause
