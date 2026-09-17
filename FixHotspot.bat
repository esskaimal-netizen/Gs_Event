@echo off
:: GrandStores — Hotspot Quick Fix Tool
:: Fixes all known issues that prevent mobile devices from connecting

title GrandStores Hotspot Quick Fix

net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo Requesting Administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo  ============================================================
echo    GRANDSTORES HOTSPOT QUICK FIX
echo  ============================================================
echo.

:: ---- Step 1: Register URL ACL so server can accept external connections ----
echo  [1] Registering port 8080 for all-interface access...
netsh http delete urlacl url=http://+:8080/ >nul 2>&1
netsh http add urlacl url=http://+:8080/ user=Everyone
echo      Done.
echo.

:: ---- Step 2: Remove old firewall rules and add correct ones ----------------
echo  [2] Fixing Windows Firewall rules for port 8080...
netsh advfirewall firewall delete rule name="GrandStores-EventPrint" >nul 2>&1
netsh advfirewall firewall delete rule name="GrandStores-Print-8080" >nul 2>&1
netsh advfirewall firewall add rule name="GrandStores-EventPrint" ^
    dir=in action=allow protocol=TCP localport=8080 ^
    profile=any description="GrandStores Event Print - mobile access"
echo      Done.
echo.

:: ---- Step 3: Check Wi-Fi Adapters and Hotspot status ------------------------
echo  [3] Checking Wi-Fi Adapters and Hotspot status...
netsh wlan show interfaces 2>&1 | findstr /i "Name Description State SSID Radio"
netsh wlan show hostednetwork 2>&1 | findstr /i "status ssid clients"
echo.

:: ---- Step 4: Show all active network IPs ----------------------------------
echo  [4] Your PC network addresses (tell customers to use one of these):
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    echo      IP: %%a
)
echo.

:: ---- Step 5: Open Mobile Hotspot Settings ---------------------------------
echo  [5] Opening Windows Mobile Hotspot Settings...
echo      Make sure the toggle is ON and note the SSID and password.
echo.
start ms-settings:network-mobilehotspot
timeout /t 3 /nobreak >nul

echo.
echo  ============================================================
echo    HOW TO CONNECT MOBILES:
echo.
echo    OPTION A (Normal Wi-Fi Router / Personal Hotspot):
echo    1. Connect both mobile phones to the SAME Wi-Fi network as this PC.
echo    2. Open your mobile browser and go to your PC's IP address (e.g.):
echo       http://192.168.137.74:8080/customer
echo.
echo    OPTION B (Windows PC Mobile Hotspot):
echo    1. Enable Windows Mobile Hotspot in Settings.
echo    2. Connect your mobile phones to that hotspot name.
echo    3. Open mobile browser to:
echo       http://192.168.137.1:8080/customer
echo.
echo    IMPORTANT TIP: If your phone prompts "Wi-Fi has no internet",
echo    choose "Stay connected to Wi-Fi" or temporarily disable Mobile Data.
echo  ============================================================
echo.

:: ---- Step 6: Kill any old server and restart it ---------------------------
echo  [6] Restarting GrandStores print server...
taskkill /f /im powershell.exe /fi "WINDOWTITLE eq GrandStores*" >nul 2>&1
timeout /t 2 /nobreak >nul
start "GrandStores Print Server" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-App.ps1"
echo      Server started.
echo.

echo  Press any key to exit...
pause >nul
