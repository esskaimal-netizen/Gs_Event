# GRANDSTORES DIGITAL PHOTO SOFTWARE - Dual-Mode Launcher
# Starts a local web server enabling HTML5 File System Access API security context.

$port = 8080
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")  # + listens on all interfaces (needed for mobile QR access)

# In-memory Event Kiosk Queue
# Each item: @{ id; imageData (base64); timestamp }
$script:evtQueue = [System.Collections.Generic.List[hashtable]]::new()

$script:mobileUploadDir = Join-Path $PSScriptRoot "Mobile_Uploads"
if (-not (Test-Path $script:mobileUploadDir)) {
    try { [System.IO.Directory]::CreateDirectory($script:mobileUploadDir) | Out-Null } catch {}
}

# Helper: get primary local IPv4
function Get-LocalIP {
    try {
        # 1. First check if there is an active default gateway route (Wi-Fi or LAN)
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                 Sort-Object RouteMetric | Select-Object -First 1
        if ($route) {
            $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                  Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' } |
                  Select-Object -ExpandProperty IPAddress -First 1
            if ($ip) { return $ip }
        }

        # 2. Check if Windows Mobile Hotspot is active (192.168.137.1)
        $hs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -eq '192.168.137.1' } |
              Select-Object -ExpandProperty IPAddress -First 1
        if ($hs) { return $hs }

        # 3. Fallback to any valid IPv4 address
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^(127\.|169\.254\.)' } |
               Select-Object -ExpandProperty IPAddressToString
        if ($ips) {
            $valid = $ips | Where-Object { $_ -notmatch '^(127\.|169\.254\.)' } | Select-Object -First 1
            if ($valid) { return $valid }
        }
    } catch {}
    return "127.0.0.1"
}

# Helper: get active Wi-Fi SSID
function Get-ConnectedWifiSsid {
    try {
        $netsh = netsh wlan show interfaces
        $line = $netsh | Where-Object { $_ -match '^\s*SSID\s*:\s*(.+)$' } | Select-Object -First 1
        if ($line -match '^\s*SSID\s*:\s*(.+)$') {
            return $Matches[1].Trim()
        }
    } catch {}
    return ""
}

# Helper: get all IPv4 addresses on all interfaces (LAN, Wi-Fi, Hotspot)
function Get-AllLocalIPs {
    $list = @()
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notmatch '^(127\.|169\.254\.)' } |
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

        # Disable keep-alive to release socket immediately for other concurrent mobile clients
        $response.KeepAlive = $false
        try { $response.Headers.Add("Access-Control-Allow-Origin", "*") } catch {}
        try { $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS") } catch {}
        try { $response.Headers.Add("Access-Control-Allow-Headers", "*") } catch {}

        # Handle CORS preflight
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Close()
            continue
        }

        $url = $request.Url.LocalPath

        # GET /api/info - return local IP, all IPs, Wi-Fi SSID, and default printer for QR generation
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/info") {
            $allIps = Get-AllLocalIPs
            $hotspotIp = ($allIps | Where-Object { $_ -eq "192.168.137.1" } | Select-Object -First 1)
            $localIP = Get-LocalIP
            $wifiSsid = Get-ConnectedWifiSsid

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
                wifiSsid       = $wifiSsid
                defaultPrinter = $defaultPrinter
                ask300Sdk      = [bool]$script:ask300Available
            } | ConvertTo-Json
            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
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

        # POST /api/event-upload - receive photo(s) from customer mobile (single or batch)
        if ($request.HttpMethod -eq "POST" -and $url -eq "/api/event-upload") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = ConvertFrom-Json $body

            $uploadedList = @()
            $imagesToProcess = @()

            if ($data.images -and $data.images.Count -gt 0) {
                $imagesToProcess = @($data.images)
            } elseif ($data.imageData) {
                $imagesToProcess = @($data)
            }

            $dateStamp = Get-Date -Format "yyyyMMdd_HHmmss"

            foreach ($imgObj in $imagesToProcess) {
                try {
                    $rawBase64 = $imgObj.imageData
                    if (-not $rawBase64) { continue }
                    $cleanBase64 = $rawBase64
                    if ($rawBase64 -match '^data:image/[^;]+;base64,(.+)$') {
                        $cleanBase64 = $Matches[1]
                    }
                    $imgBytes = [System.Convert]::FromBase64String($cleanBase64)
                    $newId = [System.Guid]::NewGuid().ToString()
                    $shortId = $newId.Substring(0, 8)

                    $customName = if ($imgObj.filename) { [System.IO.Path]::GetFileNameWithoutExtension($imgObj.filename) -replace '[^a-zA-Z0-9_\-]', '_' } else { "" }
                    $fileBase = if ($customName) { "mobile_${dateStamp}_${customName}_${shortId}.jpg" } else { "mobile_${dateStamp}_${shortId}.jpg" }
                    $savePath = [System.IO.Path]::Combine($script:mobileUploadDir, $fileBase)

                    [System.IO.File]::WriteAllBytes($savePath, $imgBytes)

                    $qty = if ($imgObj.qty -and [int]$imgObj.qty -gt 0) { [int]$imgObj.qty } else { 1 }

                    $item = @{
                        id        = $newId
                        fileName  = $fileBase
                        filePath  = $savePath
                        url       = "/api/mobile-photo?path=" + [System.Uri]::EscapeDataString($savePath)
                        imageData = $rawBase64
                        fileSize  = $imgBytes.Length
                        timestamp = [System.DateTime]::UtcNow.ToString("o")
                        qty       = $qty
                        source    = "mobile"
                    }
                    $script:evtQueue.Add($item)
                    $uploadedList += @{ id = $newId; fileName = $fileBase; url = $item.url; qty = $qty }

                    Write-Host "[MOBILE UPLOAD] Saved: $fileBase ($([Math]::Round($imgBytes.Length / 1024)) KB) | Queue: $($script:evtQueue.Count)" -ForegroundColor Green
                } catch {
                    Write-Host "[MOBILE UPLOAD ERROR] Failed processing image: $_" -ForegroundColor Red
                }
            }

            $response.StatusCode = 200
            $response.ContentType = "application/json; charset=utf-8"
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes((@{ status="ok"; count=$uploadedList.Count; items=$uploadedList } | ConvertTo-Json -Depth 3))
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/mobile-photos - List recent mobile photos for Studio Pro and Event modes
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/mobile-photos") {
            $response.ContentType = "application/json; charset=utf-8"
            $response.Headers.Add("Cache-Control", "no-cache")

            # Collect active items from queue
            $items = @()
            foreach ($q in $script:evtQueue) {
                $items += @{
                    id        = $q.id
                    fileName  = $q.fileName
                    filePath  = $q.filePath
                    url       = $q.url
                    fileSize  = if ($q.fileSize) { [int]$q.fileSize } else { 0 }
                    timestamp = $q.timestamp
                    qty       = if ($q.qty) { [int]$q.qty } else { 1 }
                    inQueue   = $true
                }
            }

            # Also scan directory for any photos not in memory queue (up to 50 newest)
            if (Test-Path $script:mobileUploadDir) {
                $dirFiles = Get-ChildItem -Path $script:mobileUploadDir -Filter "*.jpg" -ErrorAction SilentlyContinue |
                            Sort-Object LastWriteTime -Descending | Select-Object -First 50
                $knownPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($it in $items) { if ($it.filePath) { $knownPaths.Add($it.filePath) | Out-Null } }

                foreach ($df in $dirFiles) {
                    if (-not $knownPaths.Contains($df.FullName)) {
                        $items += @{
                            id        = "file_" + $df.Name
                            fileName  = $df.Name
                            filePath  = $df.FullName
                            url       = "/api/mobile-photo?path=" + [System.Uri]::EscapeDataString($df.FullName)
                            fileSize  = $df.Length
                            timestamp = $df.LastWriteTime.ToString("o")
                            qty       = 1
                            inQueue   = $false
                        }
                    }
                }
            }

            $json = @{
                total = $items.Count
                files = $items
            } | ConvertTo-Json -Depth 4
            $resBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($resBytes, 0, $resBytes.Length)
            $response.OutputStream.Close()
            continue
        }

        # GET /api/mobile-photo - Safely serve saved mobile photo image
        if ($request.HttpMethod -eq "GET" -and $url -eq "/api/mobile-photo") {
            $filePath = $request.QueryString["path"]
            if ($filePath -and (Test-Path $filePath)) {
                $response.ContentType = "image/jpeg"
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
  :root{--bg:#0b0f19;--card:rgba(20,30,54,0.92);--primary:#06b6d4;--accent:#eab308;--text:#f8fafc;--muted:#94a3b8;--success:#10b981;--error:#ef4444;--border:rgba(255,255,255,.1);}
  body{background:var(--bg);color:var(--text);font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;min-height:100dvh;display:flex;flex-direction:column;align-items:center;padding:1rem;background-image:radial-gradient(at 10% 10%,rgba(6,182,212,.18) 0,transparent 50%),radial-gradient(at 90% 90%,rgba(234,179,8,.12) 0,transparent 50%);}
  .app-container{width:100%;max-width:480px;display:flex;flex-direction:column;gap:1rem;flex:1;}
  .card{background:var(--card);border:1px solid var(--border);border-radius:20px;padding:1.5rem 1.25rem;display:flex;flex-direction:column;align-items:center;gap:1.1rem;backdrop-filter:blur(16px);box-shadow:0 8px 32px rgba(0,0,0,.3);}
  .brand-header{display:flex;align-items:center;gap:.6rem;margin-bottom:.25rem;}
  .logo-badge{width:38px;height:38px;border-radius:10px;background:linear-gradient(135deg,#06b6d4,#0891b2);display:flex;align-items:center;justify-content:center;font-size:1.3rem;}
  .brand{font-size:1.1rem;font-weight:800;letter-spacing:.08em;color:var(--primary);}
  .sub{font-size:.75rem;color:var(--muted);text-align:center;}
  h2{font-size:1.25rem;font-weight:700;text-align:center;}
  p{font-size:.85rem;color:var(--muted);text-align:center;line-height:1.45;}
  .btn{width:100%;padding:.85rem 1.2rem;border:none;border-radius:12px;font-size:.95rem;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:.5rem;transition:all .2s;text-decoration:none;-webkit-tap-highlight-color:transparent;}
  .btn-primary{background:linear-gradient(135deg,#06b6d4,#0284c7);color:#fff;box-shadow:0 4px 14px rgba(6,182,212,.35);}
  .btn-primary:active{transform:scale(.98);}
  .btn-accent{background:linear-gradient(135deg,#eab308,#ca8a04);color:#000;box-shadow:0 4px 14px rgba(234,179,8,.3);}
  .btn-accent:active{transform:scale(.98);}
  .btn-ghost{background:rgba(255,255,255,.06);color:var(--text);border:1px solid var(--border);}
  .btn-ghost:active{background:rgba(255,255,255,.12);}
  .btn-sm{padding:.4rem .7rem;font-size:.78rem;border-radius:8px;}
  .btn-icon{width:34px;height:34px;padding:0;border-radius:8px;font-size:.9rem;}
  .info-box{background:rgba(6,182,212,.08);border:1px solid rgba(6,182,212,.2);border-radius:12px;padding:.75rem 1rem;font-size:.8rem;color:#cbd5e1;line-height:1.4;display:flex;align-items:center;gap:.6rem;width:100%;}
  .screen{display:none;width:100%;flex-direction:column;gap:1rem;}
  .screen.active{display:flex;}

  /* Gallery Grid */
  .gallery-header{display:flex;justify-content:space-between;align-items:center;width:100%;padding:.25rem 0;}
  .gallery-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:.75rem;width:100%;}
  .photo-card{background:rgba(255,255,255,.04);border:2px solid transparent;border-radius:14px;overflow:hidden;position:relative;display:flex;flex-direction:column;transition:border-color .2s;}
  .photo-card.selected{border-color:var(--primary);}
  .photo-thumb-wrap{position:relative;width:100%;aspect-ratio:1;background:#000;overflow:hidden;cursor:pointer;}
  .photo-thumb{width:100%;height:100%;object-fit:cover;display:block;transition:transform .2s;}
  .photo-check{position:absolute;top:6px;right:6px;width:26px;height:26px;border-radius:50%;background:rgba(0,0,0,.6);border:2px solid #fff;display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:2;color:#fff;font-size:.8rem;}
  .photo-card.selected .photo-check{background:var(--primary);border-color:var(--primary);}
  .photo-actions{display:flex;justify-content:space-between;align-items:center;padding:.5rem .6rem;background:rgba(0,0,0,.35);}
  .qty-ctrl{display:inline-flex;align-items:center;background:rgba(255,255,255,.08);border-radius:6px;overflow:hidden;}
  .qty-btn{background:transparent;border:none;color:#fff;width:22px;height:24px;font-size:.85rem;cursor:pointer;display:flex;align-items:center;justify-content:center;}
  .qty-val{font-size:.78rem;font-weight:700;min-width:18px;text-align:center;font-family:monospace;}
  .photo-btn-bar{display:flex;gap:.3rem;}

  /* Bottom sticky bar */
  .sticky-bar{position:sticky;bottom:0;left:0;right:0;background:rgba(11,15,25,.95);border-top:1px solid var(--border);padding:.8rem 0;z-index:10;backdrop-filter:blur(12px);margin-top:auto;}
  .badge{background:var(--primary);color:#000;font-weight:800;font-size:.72rem;padding:2px 7px;border-radius:10px;margin-left:4px;}

  /* Modal */
  .modal-wrap{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,.85);z-index:100;backdrop-filter:blur(8px);align-items:center;justify-content:center;padding:1rem;}
  .modal-wrap.active{display:flex;}
  .modal-card{background:var(--card);border:1px solid var(--border);border-radius:18px;max-width:440px;width:100%;padding:1.25rem;display:flex;flex-direction:column;gap:.9rem;max-height:92dvh;overflow-y:auto;}
  .modal-preview-box{width:100%;max-height:42dvh;background:#000;border-radius:12px;overflow:hidden;display:flex;align-items:center;justify-content:center;}
  #modalImg{max-width:100%;max-height:42dvh;object-fit:contain;}
  .slider-row{display:flex;align-items:center;gap:.6rem;width:100%;}
  .slider-lbl{font-size:.78rem;color:var(--muted);width:75px;flex-shrink:0;}
  input[type=range]{flex:1;height:5px;border-radius:3px;appearance:none;background:rgba(255,255,255,.15);outline:none;}
  input[type=range]::-webkit-slider-thumb{appearance:none;width:20px;height:20px;border-radius:50%;background:var(--accent);cursor:pointer;border:2px solid rgba(0,0,0,.3);}
  .slider-val{font-size:.75rem;color:var(--text);width:30px;text-align:right;font-family:monospace;}

  /* Progress Bar */
  .progress-wrap{width:100%;height:10px;background:rgba(255,255,255,.1);border-radius:5px;overflow:hidden;}
  .progress-bar{width:0%;height:100%;background:linear-gradient(90deg,var(--primary),var(--accent));border-radius:5px;transition:width .2s;}
  .spinner{display:inline-block;width:24px;height:24px;border:3px solid rgba(255,255,255,.2);border-top-color:#fff;border-radius:50%;animation:spin .8s linear infinite;}
  @keyframes spin{to{transform:rotate(360deg);}}
  footer{margin-top:auto;padding-top:1.5rem;font-size:.7rem;color:var(--muted);text-align:center;}
</style>
</head>
<body>
<div class="app-container">

  <!-- SCREEN 1: WELCOME -->
  <div id="s-welcome" class="screen active">
    <div class="card">
      <div class="brand-header">
        <div class="logo-badge">📷</div>
        <div>
          <div class="brand">GRANDSTORES</div>
          <div class="sub">Professional Photo Printing</div>
        </div>
      </div>
      <h2>Send Photos to Print</h2>
      <p>Select multiple photos from your gallery or take a new photo to send directly to the Photo Studio station.</p>

      <div class="info-box">
        <span>🔒</span>
        <span>Your photos are sent securely over local Wi-Fi and automatically deleted after printing.</span>
      </div>

      <!-- Hidden file pickers -->
      <!-- galleryInput has multiple and NO capture attribute so it opens phone gallery -->
      <input type="file" id="galleryInput" accept="image/jpeg,image/png,image/webp,image/heic,image/*" multiple style="display:none">
      <!-- cameraInput has capture attribute to trigger camera -->
      <input type="file" id="cameraInput" accept="image/*" capture="environment" style="display:none">

      <button class="btn btn-primary" style="font-size:1.05rem;padding:1rem;" onclick="document.getElementById('galleryInput').click()">
        🖼️ Choose from Gallery
      </button>

      <button class="btn btn-ghost" style="font-size:1rem;padding:.9rem;" onclick="document.getElementById('cameraInput').click()">
        📸 Take a Photo
      </button>
    </div>
  </div>

  <!-- SCREEN 2: GALLERY REVIEW & SELECT -->
  <div id="s-gallery" class="screen">
    <div class="gallery-header">
      <div>
        <h2 style="text-align:left;font-size:1.15rem;">Review Photos</h2>
        <div style="font-size:.75rem;color:var(--muted);" id="gallerySub">Tap photo to edit · Check to select</div>
      </div>
      <div style="display:flex;gap:.4rem;">
        <button class="btn btn-ghost btn-sm" onclick="document.getElementById('galleryInput').click()">+ Gallery</button>
        <button class="btn btn-ghost btn-sm" onclick="document.getElementById('cameraInput').click()">+ Camera</button>
      </div>
    </div>

    <div class="gallery-grid" id="photoGrid"></div>

    <div class="sticky-bar">
      <button class="btn btn-accent" id="btnSendAll" onclick="startUpload()">
        🚀 Send to Studio (<span id="sendCount">0</span>)
      </button>
    </div>
  </div>

  <!-- SCREEN 3: UPLOADING -->
  <div id="s-uploading" class="screen">
    <div class="card" style="padding:2.5rem 1.5rem;text-align:center;">
      <div class="spinner"></div>
      <h2 id="uploadTitle">Sending Photos...</h2>
      <p id="uploadMsg">Preparing high-resolution images for the Studio...</p>
      <div class="progress-wrap">
        <div class="progress-bar" id="uploadBar"></div>
      </div>
      <div style="font-size:.78rem;color:var(--muted);" id="uploadPercent">0%</div>
    </div>
  </div>

  <!-- SCREEN 4: SUCCESS -->
  <div id="s-done" class="screen">
    <div class="card" style="padding:2.5rem 1.5rem;text-align:center;">
      <div style="font-size:3.5rem;">🎉</div>
      <h2>Photos Sent to Studio!</h2>
      <p>Your photos have been successfully received at the Photo Studio station.<br><br>The operator can now crop, enhance, and print your photos.</p>
      <button class="btn btn-primary" onclick="resetGallery()">
        📷 Send More Photos
      </button>
    </div>
  </div>

  <!-- MODAL: PHOTO PREVIEW & ADJUST -->
  <div class="modal-wrap" id="modalWrap">
    <div class="modal-card">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <strong style="font-size:.95rem;">Adjust Photo</strong>
        <button class="btn-icon btn-ghost" onclick="closeModal()">✕</button>
      </div>
      <div class="modal-preview-box">
        <img id="modalImg" src="" alt="Preview">
      </div>
      <div style="display:flex;gap:.5rem;justify-content:center;">
        <button class="btn btn-ghost btn-sm" onclick="rotateCurrentPhoto(90)">↺ Rotate 90°</button>
        <button class="btn btn-ghost btn-sm" onclick="resetCurrentAdjustments()">Reset</button>
      </div>
      <div style="display:flex;flex-direction:column;gap:.5rem;">
        <div class="slider-row">
          <span class="slider-lbl">Brightness</span>
          <input type="range" id="mBri" min="-50" max="50" value="0" oninput="updateModalPreview()">
          <span class="slider-val" id="mValBri">0</span>
        </div>
        <div class="slider-row">
          <span class="slider-lbl">Contrast</span>
          <input type="range" id="mCon" min="-50" max="50" value="0" oninput="updateModalPreview()">
          <span class="slider-val" id="mValCon">0</span>
        </div>
      </div>
      <div style="display:flex;align-items:center;justify-content:space-between;padding-top:.4rem;border-top:1px solid var(--border);">
        <span style="font-size:.85rem;color:var(--muted);">Print Copies:</span>
        <div class="qty-ctrl">
          <button class="qty-btn" onclick="changeCurrentQty(-1)">-</button>
          <span class="qty-val" id="mQtyVal" style="padding:0 8px;">1</span>
          <button class="qty-btn" onclick="changeCurrentQty(1)">+</button>
        </div>
      </div>
      <button class="btn btn-primary" onclick="saveModalEdits()">Done</button>
    </div>
  </div>

  <footer>GrandStores Digital · Privacy-first photo kiosk</footer>
</div>

<script>
  const UPLOAD_URL = '$uploadUrl';
  let photos = []; // Array of { id, file, url, rotation, brightness, contrast, qty, selected }
  let currentPhotoId = null;

  function showScreen(id) {
    document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
    const sc = document.getElementById(id);
    if (sc) sc.classList.add('active');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  // Handle Gallery Selection (multiple files)
  document.getElementById('galleryInput').addEventListener('change', function(e) {
    handleFiles(e.target.files);
    e.target.value = '';
  });

  // Handle Camera Capture (single file)
  document.getElementById('cameraInput').addEventListener('change', function(e) {
    handleFiles(e.target.files);
    e.target.value = '';
  });

  function handleFiles(fileList) {
    if (!fileList || fileList.length === 0) return;
    for (let i = 0; i < fileList.length; i++) {
      const file = fileList[i];
      if (!file.type.startsWith('image/')) continue;
      const id = 'p_' + Date.now() + '_' + Math.random().toString(36).substr(2, 6);
      photos.push({
        id: id,
        file: file,
        name: file.name || ('photo_' + (photos.length + 1) + '.jpg'),
        url: URL.createObjectURL(file),
        rotation: 0,
        brightness: 0,
        contrast: 0,
        qty: 1,
        selected: true
      });
    }
    renderGallery();
    showScreen('s-gallery');
  }

  function renderGallery() {
    const grid = document.getElementById('photoGrid');
    grid.innerHTML = '';

    if (photos.length === 0) {
      showScreen('s-welcome');
      return;
    }

    photos.forEach((p, idx) => {
      const card = document.createElement('div');
      card.className = 'photo-card ' + (p.selected ? 'selected' : '');
      card.id = 'card_' + p.id;

      const filterStr = 'brightness(' + (1 + p.brightness / 100) + ') contrast(' + (1 + p.contrast / 100) + ')';
      const transformStr = 'rotate(' + p.rotation + 'deg)';

      card.innerHTML = `
        <div class="photo-thumb-wrap" onclick="openModal('${p.id}')">
          <img class="photo-thumb" src="${p.url}" style="filter:${filterStr};transform:${transformStr};" alt="${p.name}">
          <div class="photo-check" onclick="event.stopPropagation(); toggleSelect('${p.id}')">
            ${p.selected ? '✓' : ''}
          </div>
        </div>
        <div class="photo-actions">
          <div class="qty-ctrl">
            <button class="qty-btn" onclick="updateQty('${p.id}', -1)">-</button>
            <span class="qty-val" id="qty_${p.id}">${p.qty}</span>
            <button class="qty-btn" onclick="updateQty('${p.id}', 1)">+</button>
          </div>
          <div class="photo-btn-bar">
            <button class="btn btn-ghost btn-icon btn-sm" title="Rotate" onclick="rotatePhoto('${p.id}', 90)">↺</button>
            <button class="btn btn-ghost btn-icon btn-sm" title="Delete" style="color:var(--error);" onclick="removePhoto('${p.id}')">✕</button>
          </div>
        </div>
      `;
      grid.appendChild(card);
    });

    updateSendButton();
  }

  function toggleSelect(id) {
    const p = photos.find(x => x.id === id);
    if (!p) return;
    p.selected = !p.selected;
    const card = document.getElementById('card_' + id);
    if (card) {
      card.classList.toggle('selected', p.selected);
      const chk = card.querySelector('.photo-check');
      if (chk) chk.textContent = p.selected ? '✓' : '';
    }
    updateSendButton();
  }

  function updateQty(id, delta) {
    const p = photos.find(x => x.id === id);
    if (!p) return;
    p.qty = Math.max(1, Math.min(20, (p.qty || 1) + delta));
    const el = document.getElementById('qty_' + id);
    if (el) el.textContent = p.qty;
    updateSendButton();
  }

  function rotatePhoto(id, deg) {
    const p = photos.find(x => x.id === id);
    if (!p) return;
    p.rotation = (p.rotation + deg) % 360;
    const card = document.getElementById('card_' + id);
    if (card) {
      const img = card.querySelector('.photo-thumb');
      if (img) img.style.transform = 'rotate(' + p.rotation + 'deg)';
    }
  }

  function removePhoto(id) {
    photos = photos.filter(x => x.id !== id);
    renderGallery();
  }

  function updateSendButton() {
    const sel = photos.filter(p => p.selected);
    const totalPrints = sel.reduce((sum, p) => sum + (p.qty || 1), 0);
    const btnText = document.getElementById('sendCount');
    if (btnText) btnText.textContent = sel.length + (sel.length === 1 ? ' photo' : ' photos');
    const sendBtn = document.getElementById('btnSendAll');
    if (sendBtn) {
      sendBtn.disabled = (sel.length === 0);
      sendBtn.style.opacity = (sel.length === 0 ? '0.4' : '1');
    }
  }

  // Modal Preview & Adjust
  function openModal(id) {
    const p = photos.find(x => x.id === id);
    if (!p) return;
    currentPhotoId = id;
    const modalImg = document.getElementById('modalImg');
    modalImg.src = p.url;
    document.getElementById('mBri').value = p.brightness;
    document.getElementById('mCon').value = p.contrast;
    document.getElementById('mValBri').textContent = (p.brightness >= 0 ? '+' : '') + p.brightness;
    document.getElementById('mValCon').textContent = (p.contrast >= 0 ? '+' : '') + p.contrast;
    document.getElementById('mQtyVal').textContent = p.qty;
    updateModalPreview();
    document.getElementById('modalWrap').classList.add('active');
  }

  function closeModal() {
    document.getElementById('modalWrap').classList.remove('active');
    currentPhotoId = null;
  }

  function updateModalPreview() {
    const p = photos.find(x => x.id === currentPhotoId);
    if (!p) return;
    const bri = parseInt(document.getElementById('mBri').value);
    const con = parseInt(document.getElementById('mCon').value);
    document.getElementById('mValBri').textContent = (bri >= 0 ? '+' : '') + bri;
    document.getElementById('mValCon').textContent = (con >= 0 ? '+' : '') + con;

    const modalImg = document.getElementById('modalImg');
    modalImg.style.filter = 'brightness(' + (1 + bri/100) + ') contrast(' + (1 + con/100) + ')';
    modalImg.style.transform = 'rotate(' + p.rotation + 'deg)';
  }

  function rotateCurrentPhoto(deg) {
    const p = photos.find(x => x.id === currentPhotoId);
    if (!p) return;
    p.rotation = (p.rotation + deg) % 360;
    updateModalPreview();
  }

  function resetCurrentAdjustments() {
    document.getElementById('mBri').value = 0;
    document.getElementById('mCon').value = 0;
    const p = photos.find(x => x.id === currentPhotoId);
    if (p) p.rotation = 0;
    updateModalPreview();
  }

  function changeCurrentQty(delta) {
    const p = photos.find(x => x.id === currentPhotoId);
    if (!p) return;
    p.qty = Math.max(1, Math.min(20, (p.qty || 1) + delta));
    document.getElementById('mQtyVal').textContent = p.qty;
  }

  function saveModalEdits() {
    const p = photos.find(x => x.id === currentPhotoId);
    if (p) {
      p.brightness = parseInt(document.getElementById('mBri').value);
      p.contrast = parseInt(document.getElementById('mCon').value);
    }
    closeModal();
    renderGallery();
  }

  // Upload Engine
  async function startUpload() {
    const sel = photos.filter(p => p.selected);
    if (sel.length === 0) return;

    showScreen('s-uploading');
    const uploadBar = document.getElementById('uploadBar');
    const uploadPercent = document.getElementById('uploadPercent');
    const uploadMsg = document.getElementById('uploadMsg');

    const total = sel.length;
    let successCount = 0;

    for (let i = 0; i < total; i++) {
      const p = sel[i];
      const percent = Math.round(((i) / total) * 100);
      uploadBar.style.width = percent + '%';
      uploadPercent.textContent = percent + '%';
      uploadMsg.textContent = 'Sending photo ' + (i + 1) + ' of ' + total + '...';

      try {
        const base64 = await processPhotoForUpload(p);
        const resp = await fetch(UPLOAD_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            imageData: base64,
            filename: p.name,
            qty: p.qty || 1
          })
        });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        successCount++;
      } catch (err) {
        console.error('Upload failed for photo ' + (i + 1), err);
      }
    }

    uploadBar.style.width = '100%';
    uploadPercent.textContent = '100%';

    if (successCount > 0) {
      showScreen('s-done');
    } else {
      showScreen('s-gallery');
      alert('Could not send photos. Please make sure your phone is connected to the same Wi-Fi network as the Studio PC.');
    }
  }

  async function processPhotoForUpload(p) {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = p.url; });

    const maxPx = 2400; // Sharp 300 DPI for standard photo prints
    let w = img.naturalWidth;
    let h = img.naturalHeight;
    const scale = Math.min(1, maxPx / Math.max(w, h));
    w = Math.round(w * scale);
    h = Math.round(h * scale);

    const canvas = document.createElement('canvas');
    const rot = (p.rotation || 0) % 360;

    if (rot === 90 || rot === 270) {
      canvas.width = h;
      canvas.height = w;
    } else {
      canvas.width = w;
      canvas.height = h;
    }

    const ctx = canvas.getContext('2d');
    ctx.translate(canvas.width / 2, canvas.height / 2);
    ctx.rotate((rot * Math.PI) / 180);
    ctx.drawImage(img, -w / 2, -h / 2, w, h);

    // Apply brightness/contrast if adjusted
    if (p.brightness !== 0 || p.contrast !== 0) {
      const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const data = imgData.data;
      const bFactor = p.brightness * 2.55;
      const cFactor = (259 * (p.contrast * 2.55 + 255)) / (255 * (259 - p.contrast * 2.55));
      for (let j = 0; j < data.length; j += 4) {
        data[j]   = Math.min(255, Math.max(0, cFactor * (data[j] - 128) + 128 + bFactor));
        data[j+1] = Math.min(255, Math.max(0, cFactor * (data[j+1] - 128) + 128 + bFactor));
        data[j+2] = Math.min(255, Math.max(0, cFactor * (data[j+2] - 128) + 128 + bFactor));
      }
      ctx.putImageData(imgData, 0, 0);
    }

    return canvas.toDataURL('image/jpeg', 0.90);
  }

  function resetGallery() {
    photos = [];
    currentPhotoId = null;
    document.getElementById('galleryInput').value = '';
    document.getElementById('cameraInput').value = '';
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

