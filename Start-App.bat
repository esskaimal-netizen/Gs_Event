@echo off
:: ============================================================
::  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
::  Main launcher — works on any Windows PC.
::  No manual setup required. Just double-click and go.
:: ============================================================

title GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
setlocal EnableDelayedExpansion

:: Move to the folder where this script lives
cd /d "%~dp0"

:: ---- Check if first-time setup is needed ----
:: We check for both the URL ACL and our marker file.
set "MARKER=%~dp0.gs_configured"
set "NEEDS_SETUP=0"

if not exist "%MARKER%" (
    set "NEEDS_SETUP=1"
) else (
    :: Verify URL ACL is registered on this specific PC
    netsh http show urlacl url=http://+:8080/ >nul 2>&1
    if !errorlevel! NEQ 0 set "NEEDS_SETUP=1"
    :: Verify Windows Firewall rule exists on this specific PC
    netsh advfirewall firewall show rule name="GrandStores-EventPrint" >nul 2>&1
    if !errorlevel! NEQ 0 set "NEEDS_SETUP=1"
)

:: ---- If setup is needed, handle it ----
if "!NEEDS_SETUP!"=="1" (
    :: Check if we are already running as Administrator
    net session >nul 2>&1
    if !errorlevel! NEQ 0 (
        :: Not admin — re-launch elevated, passing a flag so we know to run setup
        echo.
        echo  ============================================================
        echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
        echo    First-time setup needed on this PC.
        echo    Requesting Administrator access for one-time configuration...
        echo  ============================================================
        echo.
        :: Re-launch self as admin with the /setup flag
        powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '/setup' -Verb RunAs"
        exit /b
    ) else (
        :: We ARE admin (either re-launched with /setup, or user ran as admin)
        call :DoSetup
    )
)

:: ---- Start the Application ----
goto :StartServer

:: ============================================================
:DoSetup
:: ============================================================
cls
echo.
echo  ============================================================
echo    GRANDSTORES — First-Time Configuration
echo    This runs ONCE to prepare this PC. Please wait...
echo  ============================================================
echo.

:: Register URL ACL so PowerShell server can bind to all interfaces
echo  [1/3] Registering network port 8080...
netsh http delete urlacl url=http://+:8080/ >nul 2>&1
netsh http add urlacl url=http://+:8080/ user=Everyone >nul 2>&1
if !errorlevel! EQU 0 (
    echo        OK
) else (
    echo        WARNING: Could not register port. Server will run in local-only mode.
)

:: Windows Firewall rule so mobile devices can reach the server
echo  [2/3] Adding Windows Firewall rule (port 8080 inbound)...
netsh advfirewall firewall delete rule name="GrandStores-EventPrint" >nul 2>&1
netsh advfirewall firewall add rule ^
    name="GrandStores-EventPrint" ^
    dir=in ^
    action=allow ^
    protocol=TCP ^
    localport=8080 ^
    profile=any ^
    description="GrandStores Event Print - allows mobile devices to connect" >nul 2>&1
if !errorlevel! EQU 0 (
    echo        OK
) else (
    echo        WARNING: Could not add firewall rule. Mobile access may not work.
)

:: Set PowerShell execution policy so scripts run without manual override
echo  [3/3] Setting PowerShell execution policy...
powershell -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force" >nul 2>&1
echo        OK

:: Write marker file so we skip setup next time
echo configured > "%~dp0.gs_configured"

echo.
echo  ============================================================
echo    Setup complete! Starting the software now...
echo  ============================================================
echo.
timeout /t 2 /nobreak >nul

goto :StartServer

:: ============================================================
:StartServer
:: ============================================================

:: Handle the /setup re-launch case: after DoSetup above, fall through here
:: Check marker again — if still missing (edge case), warn but continue
if not exist "%MARKER%" (
    echo  NOTE: Setup may not have completed fully. Starting anyway...
    echo.
)

cls
echo.
echo  ============================================================
echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
echo    Starting server on port 8080...
echo  ============================================================
echo.
echo  Keep this window open while using the software.
echo  To stop: press Ctrl+C or close this window.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-App.ps1"

if %errorlevel% NEQ 0 (
    echo.
    echo  ============================================================
    echo    An error occurred. Possible fixes:
    echo      1. Run this file as Administrator
    echo      2. Delete the file ".gs_configured" in this folder
    echo         and double-click Start-App.bat again
    echo      3. Run Setup.bat manually as Administrator
    echo  ============================================================
    echo.
    pause
)
endlocal
