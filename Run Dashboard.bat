@echo off
title IT Device Check
color 0B
cls

echo ================================================================
echo                    IT DEVICE CHECK
echo ================================================================
echo.
echo This will open a browser-based dashboard with all device info.
echo.
echo Click YES on the UAC prompt for full results.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0DeviceDashboard.ps1"
