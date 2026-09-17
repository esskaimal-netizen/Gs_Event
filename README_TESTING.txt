================================================================================
   GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE — TESTING GUIDE ON OTHER COMPUTERS
================================================================================

This package contains the complete, self-contained GrandStores Event Photo Software
designed to run on any Windows 10 or Windows 11 PC (64-bit).

NO DEVELOPER TOOLS ARE REQUIRED.
(No Node.js, no Python, no Git, no Visual Studio needed).

--------------------------------------------------------------------------------
1. QUICK INSTALLATION (1-CLICK SETUP)
--------------------------------------------------------------------------------
1. Copy the "GS_Event" folder (or extract "GrandStores_Event_Setup.zip") to the
   computer (e.g. into C:\GS_Event or C:\GrandStores_Event).
2. Right-click "INSTALL_ON_THIS_PC.bat" and select "Run as administrator"
   (or simply double-click it; Windows will prompt for administrator rights).
3. The script will automatically:
   - Create required working folders (Printed_Photos, Sample_Photos, C:\Fujifilm_Hotfolder)
   - Add the port 8080 URL ACL rule
   - Add the Windows Firewall exception for port 8080
   - Create Desktop & Start Menu shortcuts:
       * "GrandStores Photo Software"
       * "GrandStores WiFi Hotspot Tool"
4. Done! The software will automatically start in your default web browser.

--------------------------------------------------------------------------------
2. HOW TO LAUNCH THE SOFTWARE
--------------------------------------------------------------------------------
- Double-click the "GrandStores Photo Software" shortcut on your Desktop
  (or run "Start-App.bat" from the application folder).
- Keep the black console window open while using the software.
- The web browser opens to: http://localhost:8080/

--------------------------------------------------------------------------------
3. WHAT TO TEST (STEP-BY-STEP CHECKLIST)
--------------------------------------------------------------------------------

A. TEST SOURCE PHOTO BROWSING & 6-FRAME NORITSU LAYOUT:
   1. Click "Change Folder / Open Photos" on the left panel.
   2. Select the included "Sample_Photos" folder inside the app directory.
   3. Notice how all photos appear in the left file management list.
   4. Click individual photos, hold Ctrl to multi-select, or click "Select All".
   5. Observe the right side: exactly 6 inspection frames are displayed
      (3 top row, 3 bottom row) matching the Noritsu EZ-Controller standard.
   6. Use "[< Prev 6 Frames]" and "[Next 6 Frames >]" to navigate between pages.

B. TEST COLOR ADJUSTMENT (CMYD KEYS):
   1. Under any of the 6 frames, click the Cyan Up (C▲) / Red Down (R▼) buttons.
   2. Click the Magenta Up (M▲) / Green Down (G▼) buttons.
   3. Click the Yellow Up (Y▲) / Blue Down (Y▲) buttons.
   4. Notice the live visual color grade shift on the frame.
   5. Click the "0" button on that frame to instantly reset adjustments back to neutral.

C. TEST QUANTITY & FIT MODE:
   1. Adjust the Quantity stepper (e.g. 2, 3) under specific frames.
   2. Toggle "Cut" vs "Overall" fit modes.

D. TEST "START PROCESSING" (OUTPUT & HOT FOIL DISPATCH):
   1. Click the primary "Start Processing" button.
   2. Check the "Printed_Photos" folder: high-resolution processed JPEGs are saved there.
   3. Check "C:\Fujifilm_Hotfolder": copies are automatically dispatched for the Hot Foil unit.
   4. Check the console: print dispatch logs appear in green/cyan.

E. TEST PRINTER / SDK:
   - If a Fujifilm ASK-300 dye-sub printer is connected via USB:
     The software automatically recognizes the SDK ("Fujifilm ASK-300") and sends direct SDK prints.
   - If no ASK-300 is attached:
     The software seamlessly uses the Windows printer driver or default spooler.

F. TEST MOBILE QR CODE WALK-UP / KIOSK:
   1. Connect the computer to a Wi-Fi network (or use "GrandStores WiFi Hotspot Tool.lnk").
   2. On the screen, notice the QR code showing http://<Your_PC_IP>:8080/customer.
   3. Scan the QR code using any smartphone camera connected to the same Wi-Fi.
   4. Take or select a photo on the phone, apply adjustments, and press Send.
   5. The photo arrives instantly on the operator station ready to print!

--------------------------------------------------------------------------------
4. TROUBLESHOOTING
--------------------------------------------------------------------------------
- Port 8080 blocked / access denied:
  Run "INSTALL_ON_THIS_PC.bat" as Administrator to refresh port permissions and firewall rules.
- Mobile phones cannot connect to QR URL:
  Ensure the PC and phone are on the exact same Wi-Fi network and that the PC network
  profile is not set to "Public" without firewall exceptions.
- Hot Foil folder location:
  By default it routes to C:\Fujifilm_Hotfolder. You can click "Change Hot Foil Folder"
  in the software sidebar at any time to point to any custom folder or network drive.
================================================================================
