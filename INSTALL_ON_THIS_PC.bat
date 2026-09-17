@echo off
:: ============================================================================
::  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
::  Automated Installer & System Configurator for Any Windows PC
::  Run this once when setting up on a new PC or testing machine.
:: ============================================================================

title GrandStores — System Installer & Setup
setlocal EnableDelayedExpansion

cd /d "%~dp0"

echo.
echo  ============================================================================
echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
echo    Automated Installer & Setup Tool
echo  ============================================================================
echo.

:: 1. Check Administrator Rights and Auto-Elevate if needed
net session >nul 2>&1
if %errorlevel% NEQ 0 (
    echo  [!] Administrator privileges are required to configure:
    echo      - Windows Firewall port 8080 rule
    echo      - Network URL ACL reservation for mobile QR upload
    echo      - PowerShell script execution policy
    echo.
    echo  Prompting for Administrator access...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

cls
echo.
echo  ============================================================================
echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
echo    Installing and Configuring on this PC...
echo  ============================================================================
echo.

set "APP_DIR=%~dp0"
:: Remove trailing backslash if present
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"

:: 2. Create required directories
echo  [1/6] Creating application and event folders...
if not exist "%APP_DIR%\Printed_Photos" mkdir "%APP_DIR%\Printed_Photos"
if not exist "%APP_DIR%\Sample_Photos" mkdir "%APP_DIR%\Sample_Photos"
if not exist "C:\Fujifilm_Hotfolder" (
    mkdir "C:\Fujifilm_Hotfolder" 2>nul
    if exist "C:\Fujifilm_Hotfolder" (
        echo        OK - Created Hot Foil Hotfolder at C:\Fujifilm_Hotfolder
    ) else (
        echo        WARNING - Could not create C:\Fujifilm_Hotfolder. Fallback will be used.
    )
) else (
    echo        OK - Hot Foil Hotfolder already exists at C:\Fujifilm_Hotfolder
)
echo.

:: 3. Register URL ACL for Port 8080
echo  [2/6] Registering Network Port 8080 for all users...
netsh http delete urlacl url=http://+:8080/ >nul 2>&1
netsh http add urlacl url=http://+:8080/ user=Everyone >nul 2>&1
if %errorlevel% EQU 0 (
    echo        OK - Port 8080 registered for all network interfaces
) else (
    echo        WARNING - Could not register URL ACL. Software will fallback to localhost.
)
echo.

:: 4. Add Windows Firewall Inbound Rule
echo  [3/6] Configuring Windows Firewall for Port 8080 (TCP Inbound)...
netsh advfirewall firewall delete rule name="GrandStores-EventPrint" >nul 2>&1
netsh advfirewall firewall add rule ^
    name="GrandStores-EventPrint" ^
    dir=in ^
    action=allow ^
    protocol=TCP ^
    localport=8080 ^
    profile=any ^
    description="GrandStores Event Print - Mobile QR Photo Upload and Kiosk" >nul 2>&1
if %errorlevel% EQU 0 (
    echo        OK - Windows Firewall rule added successfully
) else (
    echo        WARNING - Could not add firewall rule. Mobile upload might require manual exception.
)
echo.

:: 5. Set PowerShell Execution Policy
echo  [4/6] Setting PowerShell execution policy...
powershell -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force" >nul 2>&1
if %errorlevel% EQU 0 (
    echo        OK - PowerShell execution policy set to RemoteSigned
) else (
    echo        INFO - Execution policy already configured
)
echo.

:: 6. Create Desktop and Start Menu Shortcuts
echo  [5/6] Creating Desktop and Start Menu shortcuts...
set "TARGET_APP=%APP_DIR%\Start-App.bat"
set "TARGET_HOTSPOT=%APP_DIR%\HotspotTool.bat"
set "ICON_FILE=%APP_DIR%\gs_logo.png"

powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; " ^
  "$desk = [System.Environment]::GetFolderPath('Desktop'); " ^
  "$s1 = $ws.CreateShortcut(\"$desk\GrandStores Photo Software.lnk\"); " ^
  "$s1.TargetPath = '%TARGET_APP%'; " ^
  "$s1.WorkingDirectory = '%APP_DIR%'; " ^
  "$s1.Description = 'GrandStores Digital Photo Event Software'; " ^
  "if (Test-Path '%ICON_FILE%') { $s1.IconLocation = '%ICON_FILE%'; }; " ^
  "$s1.Save(); " ^
  "$s2 = $ws.CreateShortcut(\"$desk\GrandStores WiFi Hotspot Tool.lnk\"); " ^
  "$s2.TargetPath = '%TARGET_HOTSPOT%'; " ^
  "$s2.WorkingDirectory = '%APP_DIR%'; " ^
  "$s2.Description = 'GrandStores Event WiFi Hotspot Management'; " ^
  "$s2.Save(); " ^
  "$startMenu = [System.IO.Path]::Combine([System.Environment]::GetFolderPath('CommonPrograms'), 'GrandStores Event Photo'); " ^
  "if (-not (Test-Path $startMenu)) { New-Item -ItemType Directory -Path $startMenu -Force | Out-Null; }; " ^
  "$s3 = $ws.CreateShortcut(\"$startMenu\GrandStores Photo Software.lnk\"); " ^
  "$s3.TargetPath = '%TARGET_APP%'; " ^
  "$s3.WorkingDirectory = '%APP_DIR%'; " ^
  "$s3.Save(); " ^
  "Write-Host '       OK - Shortcuts created on Desktop and Start Menu'"
echo.

:: 7. Write Configuration Marker
echo  [6/6] Finalizing configuration...
echo configured > "%APP_DIR%\.gs_configured"
echo        OK - Setup marker written (.gs_configured)
echo.

echo  ============================================================================
echo    INSTALLATION ^& SETUP SUCCESSFUL!
echo  ============================================================================
echo.
echo    The software is now ready to run on this computer:
echo      - Desktop Shortcut:  'GrandStores Photo Software'
echo      - Hotspot Tool:      'GrandStores WiFi Hotspot Tool'
echo      - Hot Foil Folder:   C:\Fujifilm_Hotfolder
echo      - Output Folder:     %APP_DIR%\Printed_Photos
echo      - Sample Photos:     %APP_DIR%\Sample_Photos
echo.
echo  ============================================================================
echo.

set /p "LAUNCH=Would you like to launch the software right now? (Y/N) [Y]: "
if /i "%LAUNCH%"=="" set "LAUNCH=Y"
if /i "%LAUNCH%"=="Y" (
    echo Starting GrandStores Photo Software...
    start "" "%TARGET_APP%"
)

exit /b 0
