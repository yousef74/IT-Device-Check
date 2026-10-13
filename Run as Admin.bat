@echo off
title IT Device Check - Administrator
color 0B
cls

echo ================================================================
echo                 IT DEVICE CHECK - ADMIN MODE
echo ================================================================
echo.
echo This will open a browser-based dashboard with FULL Kaspersky data.
echo.
echo Click YES on the UAC prompt.
echo.
pause

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0DeviceDashboard.ps1\"' -Verb RunAs"
