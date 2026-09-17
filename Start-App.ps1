# GRANDSTORES DIGITAL PHOTO SOFTWARE - Dual-Mode Launcher
# Starts a local web server enabling HTML5 File System Access API security context.

$port = 8080
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")  # + listens on all interfaces (needed for mobile QR access)

# In-memory Event Kiosk Queue
# Each item: @{ id; imageData (base64); timestamp }
$script:evtQueue = [System.Collections.Generic.List[hashtable]]::new()

# Helper: get primary local IPv4
function Get-LocalIP {
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^127\.' } |
               Select-Object -ExpandProperty IPAddressToString
        if ($ips) {
            # Prefer Hotspot IP for mobile customer access if active
            $hs = $ips | Where-Object { $_ -eq "192.168.137.1" } | Select-Object -First 1
            if ($hs) { return $hs }
            return $ips | Select-Object -First 1
        }
    } catch {}
    return "localhost"
}

# Helper: get all IPv4 addresses on all interfaces (LAN, Wi-Fi, Hotspot)
function Get-AllLocalIPs {
    $list = @()
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^127\.' } |
               Select-Object -ExpandProperty IPAddressToString
        if ($ips) { $list = @($ips) }
    } catch {}
    return $list
}

function Invoke-FujifilmPrint {
    param (
        [string]$ImagePath,
        [int]$Qty,
        [double]$ChannelW = 0,   # Paper width  in mm (e.g. 152 for 6-inch side)
        [double]$ChannelH = 0,   # Paper height in mm (e.g. 102 for 4-inch side)
        [string]$ChannelKey = "",# e.g. "6x4", "6x6", "6x8", "5x7"
        [string]$TargetPrinter = "" # Optional specific printer name e.g. "FUJIFILM DX100"
    )
    
    Write-Host "----------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "[PRINT SYSTEM] Printing: $(Split-Path $ImagePath -Leaf) (Qty: $Qty)" -ForegroundColor Green
    if ($ChannelKey) { Write-Host "[PRINT SYSTEM] Channel Key: $ChannelKey" -ForegroundColor Cyan }
    if ($ChannelW -gt 0) { Write-Host "[PRINT SYSTEM] Paper: ${ChannelW}x${ChannelH} mm" -ForegroundColor Cyan }
    
    # Windows printer with correct paper size selection and orientation
    Write-Host "[PRINT SYSTEM] Sending directly to Windows printer..." -ForegroundColor Yellow
    try {
        Add-Type -AssemblyName System.Drawing

        $printDoc = New-Object System.Drawing.Printing.PrintDocument
        $printDoc.DocumentName = [System.IO.Path]::GetFileName($ImagePath)
        if ($TargetPrinter) {
            $printDoc.PrinterSettings.PrinterName = $TargetPrinter
        }
        $printerName = $printDoc.PrinterSettings.PrinterName
        Write-Host "[PRINT SYSTEM] Printer: '$printerName'" -ForegroundColor Cyan

        # ---- Select correct paper size from printer's supported list ----
        $selectedPaper = $null
        $key = if ($ChannelKey) { $ChannelKey.ToLower().Trim() } else { "" }

        # 2a. Primary: Match by channel key name
        $namePattern = $null
        if ($key -match '6x4')          { $namePattern = '6x4|152x102|152 x 102' }
        elseif ($key -match '6x6')      { $namePattern = '6x6|152x152|152 x 152' }
        elseif ($key -match '6x8')      { $namePattern = '6x8|152x203|152 x 203' }
        elseif ($key -match '6x9')      { $namePattern = '6x9|152x229|152 x 229' }
        elseif ($key -match '6x12')     { $namePattern = '6x12|152x305|152 x 305' }
        elseif ($key -match '5x7')      { $namePattern = '5x7|127x178|127 x 178' }
        elseif ($key -match '5x3|3\.5') { $namePattern = '5x3\.5|3\.5x5|127x89|89x127|127 x 89' }
        elseif ($key -match '8x10')     { $namePattern = '8x10|203x254|203 x 254' }
        elseif ($key -match '8x12')     { $namePattern = '8x12|203x305|203 x 305' }

        if ($namePattern) {
            foreach ($ps in $printDoc.PrinterSettings.PaperSizes) {
                if ($ps.PaperName -match $namePattern -and $ps.PaperName -notmatch 'inchx2|Type') {
                    $selectedPaper = $ps
                    Write-Host "[PRINT SYSTEM] Matched paper by key '${key}': $($ps.PaperName)" -ForegroundColor Green
                    break
                }
            }
        }

        # 2b. Secondary: Dimension match with 15mm tolerance
        if (-not $selectedPaper -and $ChannelW -gt 0 -and $ChannelH -gt 0) {
            $longSide  = [Math]::Max($ChannelW, $ChannelH)
            $shortSide = [Math]::Min($ChannelW, $ChannelH)
            foreach ($ps in $printDoc.PrinterSettings.PaperSizes) {
                if ($ps.PaperName -match 'inchx2|Type') { continue }
                $psLong  = [Math]::Max($ps.Width * 0.254, $ps.Height * 0.254)
                $psShort = [Math]::Min($ps.Width * 0.254, $ps.Height * 0.254)
                if ([Math]::Abs($psLong - $longSide) -le 15 -and [Math]::Abs($psShort - $shortSide) -le 15) {
                    $selectedPaper = $ps
                    Write-Host "[PRINT SYSTEM] Matched paper by dimensions (${ChannelW}x${ChannelH}mm): $($ps.PaperName)" -ForegroundColor Green
                    break
                }
            }
        }

        # 2c. Custom PaperSize for 6x6 if driver lacks native 6x6 (e.g. DX100, DE100, ASK-300)
        if (-not $selectedPaper -and ($key -match '6x6' -or ($ChannelW -ge 145 -and $ChannelW -le 155 -and $ChannelH -ge 145 -and $ChannelH -le 155))) {
            $custom6x6 = New-Object System.Drawing.Printing.PaperSize("6x6 inch", 598, 598)
            $custom6x6.RawKind = 256 # DMPAPER_USER
            $selectedPaper = $custom6x6
            Write-Host "[PRINT SYSTEM] Created custom 6x6 PaperSize (598x598, DMPAPER_USER)" -ForegroundColor Green
        }

        # 2d. Fallback for 6x4 channel ONLY: choose 6x4, NEVER 5x3.5
        if (-not $selectedPaper -and ($key -match '6x4' -or ($ChannelW -ge 145 -and $ChannelH -le 115))) {
            foreach ($ps in $printDoc.PrinterSettings.PaperSizes) {
                if ($ps.PaperName -match '6x4|152x102|152 x 102' -and $ps.PaperName -notmatch 'inchx2|Type') {
                    $selectedPaper = $ps
                    Write-Host "[PRINT SYSTEM] Fallback for 6x4 channel: $($ps.PaperName)" -ForegroundColor Yellow
                    break
                }
            }
        }

        # 2e. Final generic fallback (first non-inchx2 paper)
        if (-not $selectedPaper) {
            foreach ($ps in $printDoc.PrinterSettings.PaperSizes) {
                if ($ps.PaperName -notmatch 'inchx2|Type') {
                    $selectedPaper = $ps
                    Write-Host "[PRINT SYSTEM] Auto paper fallback: $($ps.PaperName)" -ForegroundColor Yellow
                    break
                }
            }
        }

        if ($selectedPaper) {
            $printDoc.DefaultPageSettings.PaperSize = $selectedPaper
        }

        # ---- Orientation for Roll Printers ----
        # In roll photo printers, the physical roll width (e.g. 6 inches for 6x4/6x6/6x8/6x9)
        # must be the Width across the paper in print coordinates (PageBounds.Width).
        # - ASK-300 defines 6x4 as Width=409, Height=622 (roll in Height) -> requires Landscape = true.
        # - DX100 / DE100 defines 6x4 as Width=598, Height=402 (roll in Width) -> requires Landscape = false.
        # We detect which dimension of selected PaperSize is closer to physical roll width:
        $targetRollUnits = if ($key -match '^6x') { 600 }
                           elseif ($key -match '^5x') { 500 }
                           elseif ($key -match '^8x') { 800 }
                           elseif ($ChannelW -gt 0 -and $ChannelH -gt 0) { [Math]::Round([Math]::Min($ChannelW, $ChannelH) * 100 / 25.4) }
                           else { 600 }

        $wDiff = [Math]::Abs($selectedPaper.Width - $targetRollUnits)
        $hDiff = [Math]::Abs($selectedPaper.Height - $targetRollUnits)

        if ($hDiff -lt $wDiff) {
            # Roll width is currently in Height -> flip to Width via Landscape = true
            $printDoc.DefaultPageSettings.Landscape = $true
            Write-Host "[PRINT SYSTEM] Print orientation: Landscape=true (roll dimension was Height, flipped to Width)" -ForegroundColor Cyan
        } else {
            # Roll width is already in Width -> keep Landscape = false
            $printDoc.DefaultPageSettings.Landscape = $false
            Write-Host "[PRINT SYSTEM] Print orientation: Landscape=false (roll dimension is already Width)" -ForegroundColor Cyan
        }

        # ---- PrintPage: Draw image to fill full roll width and cut length without borders ----
        $printDoc.add_PrintPage({
            param($sender, $e)
            $imgBytes = [System.IO.File]::ReadAllBytes($ImagePath)
            $ms       = New-Object System.IO.MemoryStream(,$imgBytes)
            $img      = [System.Drawing.Image]::FromStream($ms)
            $pageW = [double]$e.PageBounds.Width
            $pageH = [double]$e.PageBounds.Height

            # AUTO-ADJUST IMAGE ORIENTATION ACCORDING TO PRINT PAGE:
            # If the image orientation does not match the page orientation (e.g. portrait photo on landscape 6x4 page),
            # rotate 90° clockwise in memory so the long side of the image aligns with the long side of the page.
            # If both are portrait, both are landscape, or page is square (6x6), do not rotate.
            $isImgPortrait  = $img.Width -lt $img.Height
            $isPagePortrait = $pageW -lt $pageH
            $isPageSquare   = [Math]::Abs($pageW - $pageH) -le 10

            if (-not $isPageSquare -and ($isImgPortrait -ne $isPagePortrait)) {
                $img.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone)
                Write-Host "[PRINT SYSTEM] Auto-rotated image 90° to align with page orientation" -ForegroundColor Cyan
            }

            # Calculate crop-to-fill scale (aspect ratio fill with bleed, centered)
            $imgRatio  = [double]$img.Width / [double]$img.Height
            $pageRatio = [double]$pageW / [double]$pageH
            if ($imgRatio -gt $pageRatio) {
                # Image is wider than page -> match height, center crop width
                $drawH = $pageH
                $drawW = [Math]::Round($pageH * $imgRatio)
            } else {
                # Image is taller than page -> match width, center crop height
                $drawW = $pageW
                $drawH = [Math]::Round($pageW / $imgRatio)
            }
            $x = [Math]::Round(($pageW - $drawW) / 2)
            $y = [Math]::Round(($pageH - $drawH) / 2)

            $e.Graphics.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $e.Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $e.Graphics.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $e.Graphics.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

            $e.Graphics.DrawImage($img, [int]$x, [int]$y, [int]$drawW, [int]$drawH)

            $img.Dispose()
            $ms.Dispose()
            $e.HasMorePages = $false
        })

        $printDoc.PrinterSettings.Copies = [Math]::Max(1, [Math]::Min($Qty, 99))
        $printDoc.Print()
        $printDoc.Dispose()

        $sizeName = if ($selectedPaper) { $selectedPaper.PaperName } else { "default" }
        $msg = "Printed $Qty copies to '$printerName' ($sizeName)"
        Write-Host "[PRINT SYSTEM] $msg" -ForegroundColor Green
        return "Windows Printer: $msg"

    } catch {
        Write-Host "[PRINT SYSTEM] Print failed: $_" -ForegroundColor Red
        try {
            for ($i = 1; $i -le $Qty; $i++) {
                Start-Process -FilePath $ImagePath -Verb Print -ErrorAction Stop | Out-Null
            }
            return "Shell Print: $Qty copies sent"
        } catch { return "Print failed: $($_.Exception.Message)" }
    }
}

$isBoundAll = $false
try {
    $listener.Start()
    $isBoundAll = $true
} catch {
    # If wildcard binding failed (e.g. non-elevated user or missing URL ACL), fallback to localhost
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$port/")
        $listener.Prefixes.Add("http://127.0.0.1:$port/")
        $listener.Start()
        Write-Host "  [NOTICE] Server running in Local-Only mode (http://localhost:$port/)." -ForegroundColor Yellow
        Write-Host "  To enable Mobile QR upload across WiFi, run as Administrator once." -ForegroundColor Yellow
    } catch {
        Write-Error "Failed to start server. Port $port may already be in use by another application."
        Read-Host "Press Enter to exit..."
        exit
    }
}

Clear-Host
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "    GRANDSTORES DIGITAL PHOTO SOFTWARE - v1.4.0           " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  OPERATOR STATION:  " -NoNewline; Write-Host "http://localhost:$port/" -ForegroundColor Cyan
$localIP = Get-LocalIP
Write-Host "  CUSTOMER QR URL:   " -NoNewline; Write-Host "http://${localIP}:${port}/customer" -ForegroundColor Green
Write-Host ""
Write-Host "  Modes: Studio Pro (full lab control)  |  Event Kiosk (QR walk-up)" -ForegroundColor Gray
Write-Host "  Keep this window open while using the software." -ForegroundColor DarkGray
Write-Host "  To stop: press [Ctrl + C] or close this window." -ForegroundColor Red
Write-Host ""
Write-Host "  NOTE: For Event Kiosk mode, ensure Windows Firewall allows" -ForegroundColor DarkYellow
Write-Host "  port $port so customer phones on the same WiFi can connect." -ForegroundColor DarkYellow
Write-Host ""

# =============================================================================
#  PRINTER & HARDWARE INITIALIZATION
# =============================================================================
$script:ask300Manager = $null
$script:ask300Available = $false

Add-Type -AssemblyName System.Drawing
$defaultPrinterName = try { [System.Drawing.Printing.PrinterSettings]::new().PrinterName } catch { "" }

Write-Host "  [PRINT SYSTEM] Windows Default Printer: '$defaultPrinterName'" -ForegroundColor Cyan

$ask300Folder = Join-Path $PSScriptRoot "ASK300"
$ask300Bridge = Join-Path $ask300Folder "ASK300Bridge.cs"

# Check if running 64-bit PowerShell (modern Windows standard)
if ([Environment]::Is64BitProcess) {
    # In 64-bit Windows, 32-bit unmanaged DLLs (like legacy ASK300 SDK) cannot be loaded directly into 64-bit processes (HRESULT: 0x8007000B).
    # The official 64-bit Fujifilm Windows Spooler Driver ('FUJIFILM ASK-300') provides native high-quality direct printing.
    if ($defaultPrinterName -match "ASK-300|DX100|DE100") {
        Write-Host "  [PRINT SYSTEM] Fujifilm Photo Printer '$defaultPrinterName' is ready via Windows Spooler Engine." -ForegroundColor Green
    } else {
        Write-Host "  [PRINT SYSTEM] 64-bit Spooler Engine active. Direct printing configured for '$defaultPrinterName'." -ForegroundColor Green
    }
} else {
    # 32-bit process fallback - only attempt low-level SDK if running 32-bit
    if ((Test-Path $ask300Folder) -and (Test-Path (Join-Path $ask300Folder "ASKAPI.dll"))) {
        Write-Host "  [ASK-300] 32-bit process detected. Testing SDK bridge..." -ForegroundColor Cyan
        try {
            if (-not ([System.Management.Automation.PSTypeName]'GrandStores.ASK300.Ask300Manager').Type) {
                $bridgeCode = Get-Content $ask300Bridge -Raw
                Add-Type -TypeDefinition $bridgeCode `
                         -ReferencedAssemblies "System.Drawing","System.Runtime.InteropServices" `
                         -Language CSharp -ErrorAction Stop
            }
            $script:ask300Manager = New-Object GrandStores.ASK300.Ask300Manager($ask300Folder)
            $initResult = $script:ask300Manager.Initialize()
            Write-Host "  [ASK-300] $initResult" -ForegroundColor $(if ($initResult -match '^OK') { 'Green' } else { 'Yellow' })
            $script:ask300Available = $initResult -match '^OK'
        } catch {
            Write-Host "  [ASK-300] SDK bridge unavailable - using Windows Spooler." -ForegroundColor DarkGray
            $script:ask300Available = $false
        }
    }
}

# =============================================================================
#  WI-FI CAMERA INGEST & FTP RECEIVER INITIALIZATION
# =============================================================================
$script:cameraServer = $null
$cameraDefaultIncoming = Join-Path $PSScriptRoot "Camera_Incoming"
if (-not (Test-Path $cameraDefaultIncoming)) {
    try { [System.IO.Directory]::CreateDirectory($cameraDefaultIncoming) | Out-Null } catch {}
}

$cameraServerCodePath = Join-Path $PSScriptRoot "CameraFtpServer.cs"
if (Test-Path $cameraServerCodePath) {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'GrandStores.Camera.CameraFtpServer').Type) {
            $cameraCs = Get-Content $cameraServerCodePath -Raw
            Add-Type -TypeDefinition $cameraCs -Language CSharp -ErrorAction Stop
        }
        $script:cameraServer = New-Object GrandStores.Camera.CameraFtpServer($cameraDefaultIncoming, 2121)
        $camStarted = $script:cameraServer.Start()
        if ($camStarted) {
            Write-Host "  [CAMERA] Wi-Fi Camera FTP Ingest active on port 2121." -ForegroundColor Green
            Write-Host "  [CAMERA] Default incoming folder: $cameraDefaultIncoming" -ForegroundColor DarkGray
        } else {
            Write-Host "  [CAMERA] Wi-Fi Camera FTP failed to start on port 2121." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [CAMERA] Wi-Fi Camera Ingest initialization failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Open default browser
Start-Process "http://localhost:$port/"

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $url = $request.Url.LocalPath

        # GET /api/info - return local IP, all IPs, and default printer for QR generation
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/info") {
            $allIps = Get-AllLocalIPs
            $hotspotIp = ($allIps | Where-Object { $_ -eq "192.168.137.1" } | Select-Object -First 1)
            $localIP = Get-LocalIP

            # Detect default Windows printer name
            $defaultPrinter = ""
            try {
                $p = Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue | Where-Object { $_.Default -eq $true } | Select-Object -First 1
                if ($p) { $defaultPrinter = $p.Name }
            } catch {}

            $responseJson = @{
                ip             = $localIP
                port           = $port
                allIps         = $allIps
                hotspotIp      = if ($hotspotIp) { $hotspotIp } else { "" }
                hasHotspot     = [bool]$hotspotIp
                defaultPrinter = $defaultPrinter
                ask300Sdk      = [bool]$script:ask300Available
            } | ConvertTo-Json
            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/camera/status - Camera receiver status, port, IP addresses, target folder
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/camera/status") {
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Cache-Control", "no-cache")
            $response.Headers.Add("Access-Control-Allow-Origin", "*")

            $ips = Get-AllLocalIPs
            $hotspotIp = ($ips | Where-Object { $_ -eq "192.168.137.1" } | Select-Object -First 1)
            $primaryIp = ($ips | Where-Object { $_ -ne "192.168.137.1" } | Select-Object -First 1)
            if (-not $primaryIp) { $primaryIp = if ($hotspotIp) { $hotspotIp } else { "127.0.0.1" } }

            $statusObj = @{
                isRunning        = if ($script:cameraServer) { [bool]$script:cameraServer.IsRunning } else { $false }
                port             = if ($script:cameraServer) { [int]$script:cameraServer.Port } else { 2121 }
                targetFolder     = if ($script:cameraServer) { [string]$script:cameraServer.TargetFolder } else { $cameraDefaultIncoming }
                totalReceived    = if ($script:cameraServer) { [int]$script:cameraServer.TotalReceived } else { 0 }
                lastFileName     = if ($script:cameraServer) { [string]$script:cameraServer.LastFileName } else { "" }
                lastFileTime     = if ($script:cameraServer -and $script:cameraServer.LastFileTime -ne [DateTime]::MinValue) { $script:cameraServer.LastFileTime.ToString("o") } else { "" }
                connectedClients = if ($script:cameraServer) { [int]$script:cameraServer.ConnectedClients } else { 0 }
                ipAddresses      = $ips
                primaryIp        = $primaryIp
                hotspotIp        = if ($hotspotIp) { $hotspotIp } else { "" }
                hasHotspot       = [bool]$hotspotIp
                user             = "camera"
                password         = "camera"
            }
            $json = $statusObj | ConvertTo-Json -Depth 4
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/camera/toggle - Start / Stop camera receiver
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/camera/toggle") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $reqData = if ($body) { ConvertFrom-Json $body } else { $null }

            if ($script:cameraServer) {
                if ($reqData -and ($reqData.enabled -ne $null)) {
                    if ($reqData.enabled) { $script:cameraServer.Start() | Out-Null }
                    else { $script:cameraServer.Stop() }
                } else {
                    if ($script:cameraServer.IsRunning) { $script:cameraServer.Stop() }
                    else { $script:cameraServer.Start() | Out-Null }
                }
            }

            $response.ContentType = "application/json; charset=utf-8"
            $json = @{
                isRunning = if ($script:cameraServer) { [bool]$script:cameraServer.IsRunning } else { $false }
                port      = if ($script:cameraServer) { [int]$script:cameraServer.Port } else { 2121 }
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/camera/set-folder - Set target incoming folder for camera photos
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/camera/set-folder") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $reqData = if ($body) { ConvertFrom-Json $body } else { $null }
            $newFolder = if ($reqData -and $reqData.folder) { [string]$reqData.folder } else { "" }

            if ($newFolder -and (Test-Path $newFolder)) {
                if ($script:cameraServer) {
                    $script:cameraServer.SetTargetFolder($newFolder)
                    Write-Host "[CAMERA] Target folder changed to: $newFolder" -ForegroundColor Cyan
                }
            }
            $response.ContentType = "application/json; charset=utf-8"
            $json = @{
                success      = $true
                targetFolder = if ($script:cameraServer) { [string]$script:cameraServer.TargetFolder } else { "" }
            } | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/camera/incoming - Retrieve recent photos received from camera
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/camera/incoming") {
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Cache-Control", "no-cache")
            $response.Headers.Add("Access-Control-Allow-Origin", "*")

            $recentList = @()
            if ($script:cameraServer) {
                $limit = 50
                $files = $script:cameraServer.GetRecentFiles($limit)
                foreach ($f in $files) {
                    $recentList += @{
                        fileName  = $f.FileName
                        filePath  = $f.FilePath
                        fileSize  = $f.FileSize
                        timestamp = $f.Timestamp.ToString("o")
                        url       = "/api/camera-photo?path=" + [System.Uri]::EscapeDataString($f.FilePath)
                    }
                }
            }
            $json = @{
                total = if ($script:cameraServer) { [int]$script:cameraServer.TotalReceived } else { 0 }
                files = $recentList
            } | ConvertTo-Json -Depth 4
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/camera-photo - Serve image content safely to frontend
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/camera-photo") {
            $filePath = $request.QueryString["path"]
            if ($filePath -and (Test-Path $filePath)) {
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $mime = switch ($ext) {
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".webp" { "image/webp" }
                    ".bmp"  { "image/bmp" }
                    default { "application/octet-stream" }
                }
                $response.ContentType = $mime
                $response.Headers.Add("Cache-Control", "public, max-age=3600")
                $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
                $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
                $response.OutputStream.Close()
                continue
            } else {
                $response.StatusCode = 404
                $response.Close()
                continue
            }
        }

        # POST /api/event-upload - receive photo from customer mobile
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/event-upload") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = ConvertFrom-Json $body

            $newId = [System.Guid]::NewGuid().ToString()
            $item  = @{
                id        = $newId
                imageData = $data.imageData   # base64 data URL from customer
                timestamp = [System.DateTime]::UtcNow.ToString("o")
            }
            $script:evtQueue.Add($item)

            Write-Host "[EVENT] Photo received from customer. Queue size: $($script:evtQueue.Count)" -ForegroundColor Cyan

            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes((@{ status="ok"; id=$newId } | ConvertTo-Json))
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/event-queue - return pending items to operator station
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/event-queue") {
            $queueArray = @($script:evtQueue | ForEach-Object { $_ })
            $responseJson = ConvertTo-Json $queueArray -Depth 5
            if (-not $responseJson) { $responseJson = "[]" }
            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/event-ack - remove item from queue (printed or rejected)
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/event-ack") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = ConvertFrom-Json $body
            $ackId = $data.id
            $toRemove = $script:evtQueue | Where-Object { $_.id -eq $ackId }
            foreach ($r in @($toRemove)) { $script:evtQueue.Remove($r) | Out-Null }
            Write-Host "[EVENT] Item acknowledged/removed: $ackId. Queue: $($script:evtQueue.Count)" -ForegroundColor DarkCyan

            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"ok"}')
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /customer - serve customer mobile web page
        if ($request.HttpMethod -eq "GET" -and $url -eq "/customer") {
            $localIP = Get-LocalIP
            $uploadUrl = "http://${localIP}:${port}/api/event-upload"
            $customerHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<title>GrandStores Photo Print</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0;}
  :root{--bg:#0b0f19;--card:rgba(20,30,54,0.9);--primary:#06b6d4;--accent:#eab308;--text:#f8fafc;--muted:#64748b;--success:#10b981;--error:#ef4444;}
  body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100dvh;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:1.5rem;background-image:radial-gradient(at 20% 10%,rgba(6,182,212,.18) 0,transparent 50%),radial-gradient(at 80% 90%,rgba(234,179,8,.12) 0,transparent 50%);}
  .card{background:var(--card);border:1px solid rgba(255,255,255,.08);border-radius:20px;padding:2rem 1.75rem;width:100%;max-width:400px;display:flex;flex-direction:column;align-items:center;gap:1.25rem;backdrop-filter:blur(16px);}
  .logo{font-size:2.5rem;margin-bottom:.25rem;}
  .brand{font-size:1rem;font-weight:700;letter-spacing:.1em;color:var(--primary);}
  .sub{font-size:.78rem;color:var(--muted);}
  h2{font-size:1.25rem;font-weight:700;text-align:center;}
  p{font-size:.85rem;color:var(--muted);text-align:center;line-height:1.5;}
  .btn{width:100%;padding:.9rem;border:none;border-radius:12px;font-size:1rem;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:.5rem;transition:all .2s;}
  .btn-primary{background:var(--primary);color:#fff;}
  .btn-primary:active{background:#0891b2;}
  .btn-accent{background:var(--accent);color:#000;}
  .btn-accent:active{background:#ca8a04;}
  .btn-ghost{background:rgba(255,255,255,.06);color:var(--text);border:1px solid rgba(255,255,255,.12);}
  .preview-wrap{width:100%;border-radius:12px;overflow:hidden;background:#000;max-height:50dvh;display:flex;align-items:center;justify-content:center;}
  #previewImg{width:100%;height:auto;max-height:50dvh;object-fit:contain;display:block;}
  .sliders{width:100%;display:flex;flex-direction:column;gap:.65rem;}
  .slider-row{display:flex;align-items:center;gap:.6rem;}
  .slider-lbl{font-size:.75rem;color:var(--muted);width:72px;flex-shrink:0;}
  input[type=range]{flex:1;height:4px;border-radius:2px;appearance:none;background:rgba(255,255,255,.15);outline:none;}
  input[type=range]::-webkit-slider-thumb{appearance:none;width:18px;height:18px;border-radius:50%;background:var(--accent);cursor:pointer;border:2px solid rgba(0,0,0,.3);}
  .slider-val{font-size:.72rem;color:var(--text);width:30px;text-align:right;font-family:monospace;}
  .status{padding:.65rem 1rem;border-radius:10px;font-size:.85rem;text-align:center;width:100%;}
  .status-ok{background:rgba(16,185,129,.15);color:var(--success);border:1px solid rgba(16,185,129,.25);}
  .status-err{background:rgba(239,68,68,.12);color:var(--error);border:1px solid rgba(239,68,68,.2);}
  .spinner{display:inline-block;width:18px;height:18px;border:3px solid rgba(255,255,255,.2);border-top-color:#fff;border-radius:50%;animation:spin .8s linear infinite;}
  @keyframes spin{to{transform:rotate(360deg);}}
  .screen{display:none;} .screen.active{display:contents;}
  footer{margin-top:1.5rem;font-size:.68rem;color:var(--muted);text-align:center;}
</style>
</head>
<body>
<!-- WELCOME SCREEN -->
<div id="s-welcome" class="screen active">
<div class="card">
  <div class="logo">📷</div>
  <div class="brand">GRANDSTORES</div>
  <div class="sub">Digital Photo Printing</div>
  <h2>Send Your Photo to Print</h2>
  <p>Select or take a photo and send it directly to the print kiosk. Your image is deleted immediately after printing.</p>
  <input type="file" id="fileInput" accept="image/*" capture="environment" style="display:none">
  <button class="btn btn-primary" onclick="document.getElementById('fileInput').click()">
    📁 Choose Photo
  </button>
  <button class="btn btn-ghost" onclick="document.getElementById('fileInput').setAttribute('capture','environment'); document.getElementById('fileInput').click()">
    📸 Take Photo
  </button>
</div>
</div>

<!-- EDIT SCREEN -->
<div id="s-edit" class="screen">
<div class="card">
  <div style="font-size:.8rem;color:var(--muted);align-self:flex-start;">Step 2 of 2 · Adjust &amp; Send</div>
  <div class="preview-wrap">
    <img id="previewImg" src="" alt="Your photo">
  </div>
  <div class="sliders">
    <div class="slider-row">
      <span class="slider-lbl">Brightness</span>
      <input type="range" id="slBri" min="-50" max="50" value="0" oninput="updatePreview()">
      <span class="slider-val" id="valBri">0</span>
    </div>
    <div class="slider-row">
      <span class="slider-lbl">Contrast</span>
      <input type="range" id="slCon" min="-50" max="50" value="0" oninput="updatePreview()">
      <span class="slider-val" id="valCon">0</span>
    </div>
    <div class="slider-row">
      <span class="slider-lbl">Saturation</span>
      <input type="range" id="slSat" min="-50" max="50" value="0" oninput="updatePreview()">
      <span class="slider-val" id="valSat">0</span>
    </div>
  </div>
  <p style="font-size:.72rem;">Adjustments shown as preview only. Final quality is applied at print.</p>
  <button class="btn btn-accent" id="btnSend" onclick="sendPhoto()">
    🖨️ Send to Print
  </button>
  <button class="btn btn-ghost" onclick="showScreen('s-welcome')" style="font-size:.85rem;padding:.6rem;">← Choose Different Photo</button>
</div>
</div>

<!-- SENDING SCREEN -->
<div id="s-sending" class="screen">
<div class="card">
  <div style="font-size:3rem;margin-bottom:.5rem;">⏳</div>
  <h2>Sending...</h2>
  <p>Please wait while your photo is sent to the print kiosk.</p>
  <div class="spinner"></div>
</div>
</div>

<!-- THANKYOU SCREEN -->
<div id="s-done" class="screen">
<div class="card">
  <div style="font-size:3.5rem;margin-bottom:.5rem;">🎉</div>
  <h2>Photo Sent!</h2>
  <p>Your photo has been sent to the print queue. The operator will print it shortly.<br><br>Your image is <strong style="color:var(--success)">automatically deleted</strong> from the system after printing.</p>
  <div class="status status-ok">✓ Successfully sent to print queue</div>
  <button class="btn btn-primary" onclick="resetApp()">📷 Send Another Photo</button>
</div>
</div>

<footer>GrandStores Digital · Privacy-first photo kiosk</footer>

<script>
  const UPLOAD_URL = '$uploadUrl';
  let originalFile = null;

  function showScreen(id) {
    document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
    document.getElementById(id).classList.add('active');
  }

  document.getElementById('fileInput').addEventListener('change', function(e) {
    const file = e.target.files[0];
    if (!file) return;
    originalFile = file;
    const url = URL.createObjectURL(file);
    document.getElementById('previewImg').src = url;
    // Reset sliders
    ['slBri','slCon','slSat'].forEach(id => document.getElementById(id).value = 0);
    ['valBri','valCon','valSat'].forEach(id => document.getElementById(id).textContent = '0');
    updatePreview();
    showScreen('s-edit');
  });

  function updatePreview() {
    const bri = parseInt(document.getElementById('slBri').value);
    const con = parseInt(document.getElementById('slCon').value);
    const sat = parseInt(document.getElementById('slSat').value);
    document.getElementById('valBri').textContent = (bri >= 0 ? '+' : '') + bri;
    document.getElementById('valCon').textContent = (con >= 0 ? '+' : '') + con;
    document.getElementById('valSat').textContent = (sat >= 0 ? '+' : '') + sat;
    // CSS filter preview
    const img = document.getElementById('previewImg');
    img.style.filter = 'brightness(' + (1 + bri/100) + ') contrast(' + (1 + con/100) + ') saturate(' + (1 + sat/100) + ')';
  }

  async function sendPhoto() {
    if (!originalFile) return;
    showScreen('s-sending');

    // Compress + encode to base64
    try {
      const canvas = document.createElement('canvas');
      const img = new Image();
      const url  = URL.createObjectURL(originalFile);
      await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });

      // Limit to 2000px on longest side for upload
      const maxPx = 2000;
      const scale = Math.min(1, maxPx / Math.max(img.naturalWidth, img.naturalHeight));
      canvas.width  = Math.round(img.naturalWidth  * scale);
      canvas.height = Math.round(img.naturalHeight * scale);
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);

      const base64 = canvas.toDataURL('image/jpeg', 0.88);

      const resp = await fetch(UPLOAD_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ imageData: base64 })
      });

      if (resp.ok) {
        showScreen('s-done');
      } else {
        throw new Error('Server error: ' + resp.status);
      }
    } catch (err) {
      showScreen('s-edit');
      alert('Failed to send: ' + err.message + '\n\nPlease ensure you are on the same WiFi network as the kiosk.');
    }
  }

  function resetApp() {
    originalFile = null;
    document.getElementById('fileInput').value = '';
    document.getElementById('previewImg').src = '';
    showScreen('s-welcome');
  }
</script>
</body>
</html>
"@
            $response.StatusCode = 200
            $response.ContentType = "text/html; charset=utf-8"
            $response.Headers.Add("Cache-Control", "no-cache")
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($customerHtml)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/ask300/status - Printer status from ASK-300 SDK
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/ask300/status") {
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Cache-Control","no-cache")
            if ($script:ask300Available -and $script:ask300Manager) {
                $statusJson = $script:ask300Manager.GetPrinterStatus()
                $statusObj  = ConvertFrom-Json $statusJson
                $fullStatus = @{
                    sdkAvailable = $true
                    sdkStatus    = $statusObj
                    printerName  = "Fujifilm ASK-300"
                } | ConvertTo-Json -Depth 5
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes($fullStatus)
            } else {
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes(
                    '{"sdkAvailable":false,"printerName":"Windows Default Printer","sdkStatus":null}')
            }
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/ask300/print - Direct ASK-300 SDK print (Pro Mode)
        # Body: { image: "base64...", sizeId: 2, copies: 1, printMode: 1, usbNo: 0 }
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/ask300/print") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body   = $reader.ReadToEnd()
            $reader.Close()
            $data = ConvertFrom-Json $body

            $base64Image = $data.image
            if ($base64Image -match '^data:image/[^;]+;base64,(.+)$') { $base64Image = $Matches[1] }
            $imageBytes = [System.Convert]::FromBase64String($base64Image)

            $sizeId    = if ($data.sizeId)    { [int]$data.sizeId }    else { 2 }  # default 4x6
            $copies    = if ($data.copies)    { [int]$data.copies }    else { 1 }
            $printMode = if ($data.printMode -ne $null) { [int]$data.printMode } else { 1 }  # quality
            $usbNo     = if ($data.usbNo -ne $null)     { [int]$data.usbNo }     else { 0 }

            $response.ContentType = "application/json; charset=utf-8"

            if ($script:ask300Available -and $script:ask300Manager) {
                Write-Host "[ASK-300] Direct SDK print: sizeId=$sizeId copies=$copies mode=$printMode usb=$usbNo" -ForegroundColor Cyan
                $result = $script:ask300Manager.PrintImage($imageBytes, $sizeId, $copies, $printMode, $usbNo)
                Write-Host "[ASK-300] Result: $result" -ForegroundColor Green
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes($result)
            } else {
                $resBytes = [System.Text.Encoding]::UTF8.GetBytes(
                    '{"success":false,"error":"ASK-300 SDK not available on this machine"}')
            }
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/browse-folder - Native Windows folder picker dialog
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/browse-folder") {
            $selectedPath = ""
            try {
                $shell = New-Object -ComObject Shell.Application
                # 0x0001 = BIF_RETURNONLYFSDIRS, 0x0040 = BIF_NEWDIALOGSTYLE, 0x0010 = BIF_EDITBOX
                $folder = $shell.BrowseForFolder(0, "Select Folder - GrandStores Event", 0x0001 -bor 0x0040 -bor 0x0010, 0)
                if ($folder) {
                    $selectedPath = $folder.Self.Path
                }
            } catch {
                try {
                    Add-Type -AssemblyName System.Windows.Forms
                    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
                    $fbd.Description = "Select Folder"
                    $fbd.ShowNewFolderButton = $true
                    if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $selectedPath = $fbd.SelectedPath
                    }
                    $fbd.Dispose()
                } catch {}
            }

            $response.ContentType = "application/json; charset=utf-8"
            $responseJson = @{ path = $selectedPath } | ConvertTo-Json
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/list-folder - List image files in a directory (Windows Explorer style)
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/list-folder") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $reqData = ConvertFrom-Json $body
            $targetDir = $reqData.folder

            $fileList = @()
            if ($targetDir -and (Test-Path $targetDir)) {
                $exts = @("*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp")
                $items = Get-ChildItem -Path $targetDir -File -Include $exts -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime -Descending
                foreach ($f in $items) {
                    $fileList += @{
                        name = $f.Name
                        path = $f.FullName
                        size = $f.Length
                        modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                        url = "/api/file?path=" + [System.Uri]::EscapeDataString($f.FullName)
                    }
                }
            }
            $response.ContentType = "application/json; charset=utf-8"
            $responseJson = @{ folder = $targetDir; files = $fileList } | ConvertTo-Json -Depth 3
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/browse-directory - In-software folder browsing API
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/browse-directory") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $reqData = if ($body) { ConvertFrom-Json $body } else { $null }
            $target = if ($reqData -and $reqData.path) { [string]$reqData.path } else { "" }

            if (-not $target -or -not (Test-Path $target)) {
                $target = if (Test-Path "C:\") { "C:\" } else { $PSScriptRoot }
            }

            # Normalize path
            $target = [System.IO.Path]::GetFullPath($target)

            $drives = @()
            try {
                $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName }
            } catch {}

            $parent = try {
                $parentObj = [System.IO.Directory]::GetParent($target)
                if ($parentObj) { $parentObj.FullName } else { "" }
            } catch { "" }

            $subdirs = @()
            try {
                $dirs = [System.IO.Directory]::GetDirectories($target)
                foreach ($d in $dirs) {
                    $dirName = [System.IO.Path]::GetFileName($d)
                    if (-not $dirName.StartsWith(".") -and -not $dirName.StartsWith('$') -and $dirName -ne "System Volume Information" -and $dirName -ne "Recovery") {
                        $subdirs += $dirName
                    }
                }
            } catch {}

            $response.ContentType = "application/json; charset=utf-8"
            $responseJson = @{
                currentPath = $target
                parentPath  = $parent
                drives      = $drives
                subdirs     = $subdirs
            } | ConvertTo-Json -Depth 3
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # POST /api/create-directory - Create folder from within in-software browser
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/create-directory") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $reqData = if ($body) { ConvertFrom-Json $body } else { $null }
            $target = if ($reqData -and $reqData.path) { [string]$reqData.path } else { "" }
            $success = $false
            if ($target) {
                try {
                    if (-not (Test-Path $target)) {
                        [System.IO.Directory]::CreateDirectory($target) | Out-Null
                    }
                    $success = $true
                } catch {}
            }
            $response.ContentType = "application/json; charset=utf-8"
            $responseJson = @{ success = $success; path = $target } | ConvertTo-Json
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/file - Serve local image file securely
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/file") {
            $filePath = $request.QueryString["path"]
            if ($filePath -and (Test-Path $filePath)) {
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $mime = switch ($ext) {
                    ".jpg"  { "image/jpeg" }
                    ".jpeg" { "image/jpeg" }
                    ".png"  { "image/png" }
                    ".webp" { "image/webp" }
                    ".bmp"  { "image/bmp" }
                    default { "application/octet-stream" }
                }
                $response.ContentType = $mime
                $response.Headers.Add("Cache-Control", "max-age=3600")
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                $response.OutputStream.Close()
                continue
            } else {
                $response.StatusCode = 404
                $response.Close()
                continue
            }
        }

        # POST /api/print - Studio Pro and Event Mode prints
        # Routes output to Output Folder, Hot Folder (Hot Foil Facility), and Photo Printer
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/print") {
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()

            $data        = ConvertFrom-Json $body
            $filename    = $data.filename
            $qty         = [int]$data.qty
            $base64Image = $data.image
            $isEventMode = if ($data.eventMode -ne $null) { [bool]$data.eventMode } else { $false }
            $chKey       = if ($data.channelKey) { [string]$data.channelKey } else { "" }
            $sizeId      = if ($data.sizeId)     { [int]$data.sizeId } else {
                if ($chKey -match '6x4')      { 2 }
                elseif ($chKey -match '6x8')  { 128 }
                elseif ($chKey -match '6x9')  { 8 }
                elseif ($chKey -match '5x7')  { 4 }
                elseif ($chKey -match '5x3')  { 1 }
                else { 2 }
            }
            $printMode   = if ($data.printMode -ne $null) { [int]$data.printMode } else { 1 }

            if ($base64Image -match '^data:image/[^;]+;base64,(.+)$') {
                $base64Data = $Matches[1]
            } else {
                $base64Data = $base64Image
            }
            $imageBytes = [System.Convert]::FromBase64String($base64Data)

            # Determine Output Folder destination
            $outputDir = if ($data.outputFolder) {
                if (-not (Test-Path $data.outputFolder)) {
                    try { [System.IO.Directory]::CreateDirectory($data.outputFolder).FullName } catch { $null }
                } else { $data.outputFolder }
            } else { $null }

            if (-not $outputDir -or -not (Test-Path $outputDir)) {
                $defaultDir = [System.IO.Path]::Combine($PSScriptRoot, "Printed_Photos")
                if (-not (Test-Path $defaultDir)) { [System.IO.Directory]::CreateDirectory($defaultDir) | Out-Null }
                $outputDir = $defaultDir
            }
            $cleanBase = ([System.IO.Path]::GetFileNameWithoutExtension($filename) -replace '[^a-zA-Z0-9_\-]', '_')
            $ext       = [System.IO.Path]::GetExtension($filename)
            if (-not $ext) { $ext = ".jpg" }
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

            if ($isEventMode) {
                $tempGuid = [System.Guid]::NewGuid().ToString("N").Substring(0, 12)
                $savePath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "gs_event_$tempGuid.jpg")
            } else {
                $savePath = [System.IO.Path]::Combine($outputDir, "${cleanBase}_${timestamp}${ext}")
            }
            [System.IO.File]::WriteAllBytes($savePath, $imageBytes)
            Write-Host "[OUTPUT] Saved processed image: $savePath" -ForegroundColor Green

            # Check print destination mode: 'direct' vs 'hotfolder' (default)
            # In Event Kiosk mode, ALWAYS default to 'direct' print unless explicitly asked otherwise
            $printDest = if ($data.printDestination) { [string]$data.printDestination } else {
                if ($isEventMode) { "direct" } else { "hotfolder" }
            }

            $hotFoilDispatched = 0
            if ($printDest -eq "hotfolder") {
                # Dispatch copies to Hot Folder for Hot Foil Facility
                $hotFolderDir = if ($data.hotFolder) {
                    if (-not (Test-Path $data.hotFolder)) {
                        try { [System.IO.Directory]::CreateDirectory($data.hotFolder).FullName } catch { $null }
                    } else { $data.hotFolder }
                } else { $null }

                if (-not $hotFolderDir) {
                    $defaultHf = "C:\Fujifilm_Hotfolder"
                    if (Test-Path $defaultHf) {
                        $hotFolderDir = $defaultHf
                    } else {
                        try {
                            [System.IO.Directory]::CreateDirectory($defaultHf) | Out-Null
                            $hotFolderDir = $defaultHf
                        } catch {
                            $localHf = [System.IO.Path]::Combine($PSScriptRoot, "HotFolder")
                            if (-not (Test-Path $localHf)) { [System.IO.Directory]::CreateDirectory($localHf) | Out-Null }
                            $hotFolderDir = $localHf
                        }
                    }
                }

                if ($hotFolderDir) {
                    try {
                        for ($hfIdx = 1; $hfIdx -le $qty; $hfIdx++) {
                            $hfDest = [System.IO.Path]::Combine($hotFolderDir, "${cleanBase}_foil_${timestamp}_${hfIdx}${ext}")
                            [System.IO.File]::WriteAllBytes($hfDest, $imageBytes)
                        }
                        $hotFoilDispatched = $qty
                        Write-Host "[HOT FOIL] Dispatched $qty print(s) to hot folder: $hotFolderDir" -ForegroundColor Cyan
                    } catch {
                        Write-Host "[HOT FOIL ERROR] Failed copying to hot folder: $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "[DIRECT PRINT] Sending directly to connected photo printer (SDK / Windows default)." -ForegroundColor Cyan
            }

            # ---- Try ASK-300 SDK or Windows default printer ----
            # If printDest is 'direct' or in Event Mode, print to ASK-300 (if connected) or Windows Default Printer
            $printResult = $null
            if ($printDest -eq "direct" -or $isEventMode) {
                if ($script:ask300Available -and $script:ask300Manager) {
                    try {
                        Write-Host "[PRINT] Using ASK-300 SDK: sizeId=$sizeId copies=$qty mode=$printMode" -ForegroundColor Green
                        $sdkResult   = $script:ask300Manager.PrintImage($imageBytes, $sizeId, $qty, $printMode, 0)
                        $sdkObj      = ConvertFrom-Json $sdkResult
                        if ($sdkObj.success) {
                            $printResult = "ASK-300 SDK: Print job sent (sizeId=$sizeId, qty=$qty)"
                            Write-Host "[PRINT] $printResult" -ForegroundColor Green
                        } else {
                            Write-Host "[PRINT] ASK-300 SDK failed: $($sdkObj.error) - falling back to Windows printer" -ForegroundColor Yellow
                        }
                    } catch {
                        Write-Host "[PRINT] ASK-300 exception: $_ - falling back" -ForegroundColor Yellow
                    }
                }

                if (-not $printResult) {
                    $chW = if ($data.channelW) { [double]$data.channelW } else { 0 }
                    $chH = if ($data.channelH) { [double]$data.channelH } else { 0 }
                    $printResult = Invoke-FujifilmPrint -ImagePath $savePath -Qty $qty -ChannelW $chW -ChannelH $chH -ChannelKey $chKey
                }

                # Delete temporary event photo file after printing completes
                if ($isEventMode -and (Test-Path $savePath)) {
                    Remove-Item $savePath -Force -ErrorAction SilentlyContinue
                    Write-Host "[EVENT PRINT] Temp file deleted. Print complete." -ForegroundColor Green
                }
            } else {
                $printResult = "Hotfolder dispatched ($hotFoilDispatched copies)"
            }

            # Move / Transfer source image to Output Folder
            $sourcePath = if ($data.sourcePath) { [string]$data.sourcePath } else { $null }
            if ($sourcePath -and (Test-Path $sourcePath)) {
                try {
                    $sourceDest = [System.IO.Path]::Combine($outputDir, "SOURCE_" + [System.IO.Path]::GetFileName($sourcePath))
                    Copy-Item -Path $sourcePath -Destination $sourceDest -Force
                    Write-Host "[ARCHIVE] Transferred source image to output folder: $sourceDest" -ForegroundColor DarkGray
                } catch {
                    Write-Host "[ARCHIVE WARNING] Could not transfer source image: $_" -ForegroundColor DarkYellow
                }
            }

            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $responseJson = @{
                status  = "success"
                message = if ($printDest -eq "direct") { "Direct Printed $filename (Qty: $qty) on $chKey to Windows default printer" } else { "Processed & dispatched $filename to hot folder (Qty: $qty)" }
                details = $printResult
                outputFile = $savePath
                hotFoilCopies = $hotFoilDispatched
                printDestination = $printDest
                usedSDK = ($printResult -match 'ASK-300 SDK')
            } | ConvertTo-Json
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($responseJson)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # Static file serving
        if ($url -eq "/") { $url = "index.html" }
        $url = $url.TrimStart('/')
        if ($url -match '\?') { $url = $url.Split('?')[0] }
        $filePath = [System.IO.Path]::Combine($PSScriptRoot, $url)
        
        if (Test-Path $filePath -PathType Leaf) {
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = "application/octet-stream"
            if ($ext -eq ".html") { $contentType = "text/html; charset=utf-8" }
            elseif ($ext -eq ".css")  { $contentType = "text/css; charset=utf-8" }
            elseif ($ext -eq ".js")   { $contentType = "application/javascript; charset=utf-8" }
            elseif ($ext -eq ".png")  { $contentType = "image/png" }
            elseif ($ext -eq ".jpg" -or $ext -eq ".jpeg") { $contentType = "image/jpeg" }
            
            $response.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
            $response.Headers.Add("Pragma", "no-cache")
            $response.Headers.Add("Expires", "0")
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 - File Not Found: $url")
            $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
        }
        $response.OutputStream.Close()

    } catch {
        # Loop continues if request is aborted or canceled
    }
}

