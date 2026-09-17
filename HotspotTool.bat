@echo off
:: ============================================================
::   GRANDSTORES EVENT WiFi HOTSPOT MANAGER — Launcher
::   Double-click this to open the hotspot tool (admin required)
:: ============================================================

title GrandStores Hotspot Tool

:: Check if running as Administrator
net session >nul 2>&1
if %errorlevel% == 0 goto :RunTool

:: Not admin — re-launch elevated
echo Requesting Administrator privileges...
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:RunTool
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0HotspotTool.ps1"
exit /b
