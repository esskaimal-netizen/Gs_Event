@echo off
:: ============================================================
::  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
::  Desktop Shortcut Installer
::  Run this once to create a shortcut on the Desktop.
:: ============================================================

title GrandStores — Create Desktop Shortcut

echo.
echo  ============================================================
echo    GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
echo    Creating Desktop Shortcut...
echo  ============================================================
echo.

:: Build the shortcut using PowerShell WScript.Shell
set "TARGET=%~dp0Start-App.bat"
set "ICON=%~dp0gs_logo.png"
set "SHORTCUT=%USERPROFILE%\Desktop\GrandStores Photo Software.lnk"

powershell -NoProfile -Command ^
  "$ws = New-Object -ComObject WScript.Shell; " ^
  "$s = $ws.CreateShortcut('%SHORTCUT%'); " ^
  "$s.TargetPath = '%TARGET%'; " ^
  "$s.WorkingDirectory = '%~dp0'; " ^
  "$s.Description = 'GrandStores Digital Photo Event Software'; " ^
  "$s.Save(); " ^
  "Write-Host '  Shortcut created on Desktop.'"

if exist "%SHORTCUT%" (
    echo.
    echo  ============================================================
    echo    Done! A shortcut "GrandStores Photo Software" has been
    echo    added to your Desktop.
    echo.
    echo    Just double-click that shortcut to start the software.
    echo  ============================================================
) else (
    echo.
    echo  WARNING: Could not create shortcut automatically.
    echo  You can create one manually:
    echo    Right-click "Start-App.bat" → Send to → Desktop (shortcut)
)

echo.
pause
