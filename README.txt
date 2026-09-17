======================================================================
  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
  Quick Start Guide
======================================================================

HOW TO START
------------
1. Double-click  "Start-App.bat"
   - On a NEW PC: it will ask for Administrator permission ONCE to
     configure the port and firewall. Allow it. The app starts
     automatically after that.
   - On subsequent launches: it starts immediately, no admin needed.

2. Your browser opens automatically at:
     http://localhost:8080/

3. To give customers WiFi access to the print kiosk:
   - Start the hotspot first (see EVENT MODE below)
   - Share the QR code shown in the app with customers

THAT'S IT. No installation, no Node.js, no Python needed.


FILES IN THIS FOLDER
--------------------
  Start-App.bat      Main launcher. Double-click to start.
  HotspotTool.bat    WiFi hotspot manager for Event Mode.
  FixHotspot.bat     Troubleshooting tool if mobiles can't connect.
  Setup.bat          Manual re-setup (only needed after Windows updates).
  INSTALL.bat        Creates a Desktop shortcut for convenience.
  README.txt         This file.


EVENT MODE (WiFi Hotspot for Customer Photo Upload)
----------------------------------------------------
1. Double-click  HotspotTool.bat  (requires Administrator — prompted)
2. Start the WiFi hotspot from the tool
3. Start the app with  Start-App.bat
4. In the app, switch to "Event Kiosk" mode
5. Display the QR code — customers scan it with their phone
   and send photos directly to the print queue


MOVING TO A NEW PC
------------------
Simply copy the entire folder to the new PC and double-click
Start-App.bat. The software configures itself automatically.

There is nothing to install. Everything runs directly from
this folder using built-in Windows features (PowerShell + .NET).


TROUBLESHOOTING
---------------
Problem: Browser doesn't open / server won't start
  Fix:  Delete the file ".gs_configured" from this folder, then
        double-click Start-App.bat again (re-runs first-time setup).

Problem: Mobile phones can't connect
  Fix:  Double-click FixHotspot.bat (requires Administrator).
        Make sure phones are on the SAME WiFi network as this PC.

Problem: Printing doesn't work
  Fix:  Check that the Fujifilm ASK-300 printer is connected and
        powered on. The app will fall back to the Windows default
        printer if the ASK-300 SDK is not available.

Problem: "Execution Policy" error in PowerShell
  Fix:  Run Setup.bat as Administrator.


SYSTEM REQUIREMENTS
-------------------
  - Windows 10 or Windows 11
  - PowerShell 5.1 or later (built into Windows)
  - .NET Framework 4.5+ (built into Windows)
  - A web browser (Chrome, Edge, Firefox)
  - No internet connection required


======================================================================
  GrandStores Digital Photo Software
  Support: contact your system administrator
======================================================================
