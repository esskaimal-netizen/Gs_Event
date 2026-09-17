@echo off
:: ============================================================
::  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
::  Manual Setup Tool — Run this if Start-App.bat can't fix itself,
::  or to re-apply settings after a Windows update.
::  (Requires Administrator rights — prompted automatically)
:: ============================================================

title GrandStores — Manual Setup Tool

:: Auto-elevate to Administrator
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting Administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cls
echo.
echo  ============================================================
echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
echo    Manual Setup Tool
echo  ============================================================
echo.
echo  NOTE: Start-App.bat handles first-time setup automatically.
echo  Use this tool only if you need to manually re-apply settings
echo  (e.g. after a Windows update or network change).
echo.
echo  This will:
echo    - Register port 8080 for all network interfaces
echo    - Add Windows Firewall rule (port 8080 - TCP inbound)
echo    - Set PowerShell execution policy (RemoteSigned)
echo    - Verify WiFi adapter capability
echo.
echo  Running...
echo.

:: 1. Register URL ACL
echo  [1/4] Registering port 8080 for network access...
netsh http delete urlacl url=http://+:8080/ >nul 2>&1
netsh http add urlacl url=http://+:8080/ user=Everyone
if %errorlevel% EQU 0 (
    echo        OK - Port 8080 registered for all users
) else (
    echo        WARNING - Could not register port. Server may need to run as admin.
)
echo.

:: 2. Windows Firewall
echo  [2/4] Adding Windows Firewall rule...
netsh advfirewall firewall delete rule name="GrandStores-EventPrint" >nul 2>&1
netsh advfirewall firewall add rule ^
    name="GrandStores-EventPrint" ^
    dir=in ^
    action=allow ^
    protocol=TCP ^
    localport=8080 ^
    profile=any ^
    description="GrandStores Event Print - allows customers to upload photos"
if %errorlevel% EQU 0 (
    echo        OK - Firewall rule added (port 8080, all network profiles)
) else (
    echo        WARNING - Could not add firewall rule. Add it manually if needed.
)
echo.

:: 3. PowerShell execution policy
echo  [3/4] Setting PowerShell execution policy...
powershell -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force" >nul 2>&1
if %errorlevel% EQU 0 (
    echo        OK - PowerShell execution policy set to RemoteSigned
) else (
    echo        INFO - Execution policy already set or not needed
)
echo.

:: 4. WiFi adapter check
echo  [4/4] Checking WiFi adapter...
for /f "tokens=*" %%a in ('netsh wlan show drivers 2^>^&1 ^| findstr /i "Hosted network"') do (
    echo        %%a
)
echo.

:: Write/refresh the configuration marker
echo configured > "%~dp0.gs_configured"

echo  ============================================================
echo    SETUP COMPLETE
echo.
echo    You can now:
echo      - Double-click  Start-App.bat      to run the software
echo      - Double-click  HotspotTool.bat    for Event WiFi hotspot
echo      - Double-click  INSTALL.bat        to add Desktop shortcut
echo.
echo    Start-App.bat now handles setup automatically on any new PC.
echo    You do NOT need to run this tool on new machines.
echo  ============================================================
echo.
pause
