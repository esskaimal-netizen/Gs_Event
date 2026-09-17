#Requires -RunAsAdministrator
# =============================================================================
#  GRANDSTORES EVENT WiFi HOTSPOT MANAGER v4.0
#  Dedicated USB WiFi Dongle Edition
#
#  ARCHITECTURE:
#    - Built-in adapter (Ethernet or WiFi) = company network (UNTOUCHED)
#    - USB WiFi Dongle                     = customer hotspot (our zone)
#    - Customers connect to dongle hotspot, reach print server via local IP
#    - Company network is completely isolated from customer network
#
#  REQUIREMENT: A USB WiFi dongle must be plugged in before enabling hotspot.
#  The software package includes a compatible dongle.
# =============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'

$STATE_FILE    = Join-Path $PSScriptRoot "hotspot_state.json"
$APP_PORT      = 8080
$FW_RULE       = "GrandStores-EventPrint"
$DEFAULT_SSID  = "GrandStores-Print"
$DEFAULT_PASS  = "GrandPhoto1"
$CUSTOMER_PATH = "/customer"
$HOTSPOT_IP    = "192.168.137.1"   # Windows ICS/hosted-network default gateway

# =============================================================================
#  CONSOLE HELPERS
# =============================================================================
function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host "  |   GRANDSTORES  EVENT  WiFi  HOTSPOT  MANAGER  v4.0     |" -ForegroundColor Cyan
    Write-Host "  |   USB Dongle Edition  -  Works on any Windows 10/11 PC  |" -ForegroundColor DarkCyan
    Write-Host "  +=========================================================+" -ForegroundColor Cyan
    Write-Host ""
}
function Write-Sep  { Write-Host "  ---------------------------------------------------------" -ForegroundColor DarkGray }
function Pause-Now  { param([string]$m = "Press any key to continue..."); Write-Host ""; Write-Host "  $m" -ForegroundColor DarkGray; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
function Write-OK   { param([string]$m); Write-Host "  [OK]   $m" -ForegroundColor Green }
function Write-WARN { param([string]$m); Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-INFO { param([string]$m); Write-Host "  [....] $m" -ForegroundColor Cyan }
function Write-FAIL { param([string]$m); Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Write-STEP { param([int]$n, [string]$m); Write-Host "  [Step $n] $m" -ForegroundColor White }

# =============================================================================
#  STATE
# =============================================================================
function Load-State {
    if (Test-Path $STATE_FILE) { try { return Get-Content $STATE_FILE -Raw | ConvertFrom-Json } catch {} }
    return $null
}
function Save-State([hashtable]$d) {
    $d | ConvertTo-Json -Depth 4 | Set-Content $STATE_FILE -Encoding UTF8
}
function Clear-State { if (Test-Path $STATE_FILE) { Remove-Item $STATE_FILE -Force } }

# =============================================================================
#  ADAPTER DETECTION
# =============================================================================

# Returns all WiFi adapters on the system (both built-in and USB dongles)
function Get-AllWiFiAdapters {
    $adapters = [System.Collections.Generic.List[psobject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Method 1: Query netsh wlan show interfaces (ground truth from Windows WLAN service)
    try {
        $netshOutput = netsh wlan show interfaces 2>&1
        $currentName = $null
        foreach ($line in $netshOutput) {
            if ($line -match '^\s*Name\s*:\s*(.+)$') {
                $currentName = $Matches[1].Trim()
                if ($currentName) {
                    $netAdapter = Get-NetAdapter -Name $currentName -ErrorAction SilentlyContinue
                    if ($netAdapter -and $seen.Add($netAdapter.Name)) {
                        $adapters.Add($netAdapter)
                    }
                }
            }
        }
    } catch {}

    # Method 2: Query Get-NetAdapter matching PhysicalMediaType, Description, or Name
    try {
        $allNet = Get-NetAdapter -ErrorAction SilentlyContinue
        foreach ($a in $allNet) {
            if ($a.InterfaceDescription -match 'Virtual Adapter|Hosted Network Virtual') { continue }

            $isWifi = ($a.PhysicalMediaType -match '802\.11|Native 802\.11|Wireless') -or
                      ($a.InterfaceDescription -match 'Wireless|Wi-Fi|WiFi|802\.11|WLAN|80211|AirPort|Centrino') -or
                      ($a.Name -match '^Wi-Fi|^WiFi|Wireless|WLAN')

            if ($isWifi -and $seen.Add($a.Name)) {
                $adapters.Add($a)
            }
        }
    } catch {}

    # Method 3: Detect disabled Wi-Fi adapters and auto-enable them
    try {
        $disabled = Get-NetAdapter | Where-Object { $_.Status -eq 'Disabled' -and ($_.Name -match 'Wi-Fi|WiFi|Wireless|WLAN' -or $_.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|WLAN') }
        foreach ($d in $disabled) {
            if ($seen.Add($d.Name)) {
                $adapters.Add($d)
            }
        }
    } catch {}

    return @($adapters)
}

# Detects USB WiFi adapters (the dongle)
# USB adapters have PNPDeviceID starting with "USB\" or USB in description
function Get-USBWiFiAdapters {
    $wifiAdapters = Get-AllWiFiAdapters
    $usbAdapters  = @()

    foreach ($a in $wifiAdapters) {
        $pnpId = $a.PnPDeviceID
        if ($pnpId -match '^USB\\' -or $a.InterfaceDescription -match 'USB|\bDongle\b') {
            $usbAdapters += $a
        }
    }
    return $usbAdapters
}

# Returns all non-USB WiFi adapters (built-in/PCIe/SDIO)
function Get-BuiltInWiFiAdapters {
    $all  = Get-AllWiFiAdapters
    $usbs = Get-USBWiFiAdapters
    $usbNames = $usbs | ForEach-Object { $_.Name }
    return @($all | Where-Object { $_.Name -notin $usbNames })
}

# Best internet-connected adapter (Ethernet preferred, then WiFi, skip dongle)
function Get-InternetAdapter {
    param([string]$ExcludeAdapterName = "")

    $candidates = Get-NetAdapter | Where-Object {
        $_.Status -eq 'Up' -and $_.Name -ne $ExcludeAdapterName
    } | Sort-Object @{
        # Ethernet first, then built-in WiFi, USB last
        Expression = {
            if ($_.InterfaceDescription -match 'Ethernet|LAN|Realtek PCIe|Intel Ethernet') { 0 }
            elseif ($_.PnPDeviceID -match '^USB\\') { 2 }
            else { 1 }
        }
    }

    foreach ($a in $candidates) {
        $route = Get-NetRoute -InterfaceIndex $a.InterfaceIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue
        if ($route) { return $a }
    }
    return ($candidates | Select-Object -First 1)
}

# Let user pick a dongle adapter (if multiple USB adapters or unclear)
function Select-DongleAdapter {
    param([array]$Adapters)

    if ($Adapters.Count -eq 0) { return $null }
    if ($Adapters.Count -eq 1) { return $Adapters[0] }

    Write-Host ""
    Write-Host "  Multiple USB WiFi adapters detected. Select the hotspot dongle:" -ForegroundColor Yellow
    Write-Host ""
    for ($i = 0; $i -lt $Adapters.Count; $i++) {
        $a = $Adapters[$i]
        $status = if ($a.Status -eq 'Up') { "(Connected)" } else { "(Disconnected)" }
        Write-Host "  [$($i+1)]  $($a.Name)  -  $($a.InterfaceDescription)  $status" -ForegroundColor White
    }
    Write-Host ""
    $choice = Read-Host "  Enter number (1-$($Adapters.Count))"
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $Adapters.Count) { return $Adapters[$idx] }
    return $Adapters[0]
}

# Wait for user to plug in dongle (up to 60 seconds)
function Wait-For-Dongle {
    Write-Host ""
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |  USB WiFi DONGLE NOT DETECTED                              |" -ForegroundColor Yellow
    Write-Host "  |                                                             |" -ForegroundColor Yellow
    Write-Host "  |  Please plug in the GrandStores USB WiFi dongle now.        |" -ForegroundColor White
    Write-Host "  |  Waiting up to 60 seconds...                                |" -ForegroundColor White
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""

    $waited = 0
    while ($waited -lt 60) {
        $usb = Get-USBWiFiAdapters
        if ($usb.Count -gt 0) {
            Write-OK "Dongle detected: $($usb[0].InterfaceDescription)"
            Start-Sleep -Seconds 2  # Let driver fully initialize
            return $usb
        }
        Write-Host "  Waiting... ($waited/60 sec)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 3
        $waited += 3
    }

    Write-FAIL "No USB WiFi dongle detected after 60 seconds."
    Write-Host "  Please ensure the dongle is plugged in and driver is installed." -ForegroundColor Yellow
    return $null
}

# Check if dongle supports hosted network via netsh
function Test-HostedNetworkSupport {
    param([string]$AdapterName)
    # Try to set hostednetwork and see if it refers to this adapter
    $result = netsh wlan show drivers interface="$AdapterName" 2>&1
    if (($result -join " ") -match 'Hosted network supported\s*:\s*Yes') { return $true }

    # Fallback: try start and see if it works
    $r = netsh wlan set hostednetwork mode=allow ssid="TestGS" key="test1234" 2>&1
    return (($r -join " ") -notmatch 'error|failed|not supported')
}

# =============================================================================
#  WINRT MOBILE HOTSPOT HELPERS
# =============================================================================
function Get-TetheringManager {
    try {
        [Windows.System.UserProfile.UserProfilePersonalizationSettings, Windows.System.UserProfile, ContentType = WindowsRuntime] | Out-Null
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
        [Windows.Networking.Connectivity.NetworkInformation, Windows.Networking.Connectivity, ContentType = WindowsRuntime] | Out-Null
        [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager, Windows.Networking.NetworkOperators, ContentType = WindowsRuntime] | Out-Null
        
        # 1. Try Internet Connection Profile first
        $profile = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if ($profile) {
            $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($profile)
            if ($tm) { return $tm }
        }

        # 2. Fallback to ANY connection profile on the PC (crucial for offline/event venue setups!)
        $allProfiles = [Windows.Networking.Connectivity.NetworkInformation]::GetConnectionProfiles()
        if ($allProfiles) {
            foreach ($p in $allProfiles) {
                try {
                    $tm = [Windows.Networking.NetworkOperators.NetworkOperatorTetheringManager]::CreateFromConnectionProfile($p)
                    if ($tm) { return $tm }
                } catch {}
            }
        }
    } catch {}
    return $null
}

function Enable-MobileHotspotDirect {
    param([string]$SSID, [string]$Password)

    try {
        # Ensure domain policy allows ICS / Mobile Hotspot
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Network Connections" -Name "NC_ShowSharedAccessUI" -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Windows\Network Connections" -Name "NC_PersonalFirewallConfig" -Value 1 -ErrorAction SilentlyContinue

        # Ensure services are enabled & running
        Set-Service icssvc -StartupType Manual -ErrorAction SilentlyContinue
        Start-Service icssvc -ErrorAction SilentlyContinue
        Set-Service WlanSvc -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service WlanSvc -ErrorAction SilentlyContinue

        # Auto-enable any disabled Wi-Fi adapters
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { $_.Status -eq 'Disabled' -and ($_.Name -match 'Wi-Fi|WiFi|Wireless|WLAN' -or $_.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|WLAN') } |
            ForEach-Object { Enable-NetAdapter -Name $_.Name -Confirm:$false -ErrorAction SilentlyContinue }

        $tm = Get-TetheringManager
        if ($tm) {
            # Configure SSID and passphrase
            $cfg = $tm.GetCurrentAccessPointConfiguration()
            $cfg.Ssid = $SSID
            $cfg.Passphrase = $Password
            $cfgOp = $tm.ConfigureAccessPointAsync($cfg)
            
            # Wait for config operation
            $waited = 0
            while ($cfgOp.Status -eq 'Started' -and $waited -lt 40) {
                Start-Sleep -Milliseconds 100
                $waited++
            }

            # Check if already On
            if ($tm.TetheringOperationalState -eq "On") {
                return $true
            }

            # Start tethering
            $startOp = $tm.StartTetheringAsync()
            $waited = 0
            while ($startOp.Status -eq 'Started' -and $waited -lt 150) {
                Start-Sleep -Milliseconds 100
                $waited++
            }

            try {
                $res = $startOp.GetResults()
                if ($res.Status -eq "Success" -or $tm.TetheringOperationalState -eq "On") {
                    return $true
                }
            } catch {
                if ($tm.TetheringOperationalState -eq "On") {
                    return $true
                }
            }
        }
    } catch {}
    return $false
}

function Enable-DongleHotspot {
    param([string]$SSID, [string]$Password, [string]$DongleAdapterName)

    Write-STEP 1 "Enabling Mobile Hotspot ($SSID)..."

    # Method 1: Modern Windows 10/11 Mobile Hotspot API (Wi-Fi Direct)
    Write-INFO "Trying Windows Mobile Hotspot API..."
    $directOk = Enable-MobileHotspotDirect -SSID $SSID -Password $Password
    if ($directOk) {
        Write-OK "Mobile Hotspot active and broadcasting SSID '$SSID'!"
        return "MobileHotspot"
    }

    # Method 2: Legacy netsh hostednetwork (fallback for older systems)
    Write-INFO "Trying legacy netsh hostednetwork..."
    netsh wlan set hostednetwork mode=allow ssid="$SSID" key="$Password" 2>&1 | Out-Null
    $r = netsh wlan start hostednetwork 2>&1
    $rText = ($r -join " ")
    if ($rText -match 'started') {
        Write-OK "Hotspot started via netsh!"
        return "netsh"
    }

    # Method 3: Windows Mobile Hotspot Settings GUI fallback
    Write-INFO "Opening Windows Mobile Hotspot Settings..."
    Write-Host ""
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  |  MANUAL STEP (if prompted)                                 |" -ForegroundColor Yellow
    Write-Host "  |                                                             |" -ForegroundColor Yellow
    Write-Host "  |  1. In the Settings window that opens:                      |" -ForegroundColor White
    Write-Host "  |  2. Click EDIT (or Properties)                              |" -ForegroundColor White
    Write-Host "  |  3. Set Network name  :  $($SSID.PadRight(33))|" -ForegroundColor Cyan
    Write-Host "  |  4. Set Password      :  $($Password.PadRight(33))|" -ForegroundColor Cyan
    Write-Host "  |  5. Click SAVE                                              |" -ForegroundColor White
    Write-Host "  |  6. Toggle Mobile Hotspot switch  ON                        |" -ForegroundColor White
    Write-Host "  |  7. Return here, press any key                              |" -ForegroundColor White
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""
    Start-Process "ms-settings:network-mobilehotspot"
    Pause-Now "After turning hotspot ON in Settings, press any key..."
    return "settings"
}

function Disable-DongleHotspot {
    Write-STEP 1 "Stopping hotspot..."
    netsh wlan stop hostednetwork 2>&1 | Out-Null

    # WinRT Stop
    try {
        $tm = Get-TetheringManager
        if ($tm -and $tm.TetheringOperationalState -eq "On") {
            $stopOp = $tm.StopTetheringAsync()
            $asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
            $asTask = $asTaskGeneric.MakeGenericMethod([Windows.Networking.NetworkOperators.NetworkOperatorTetheringOperationResult])
            $stopTask = $asTask.Invoke($null, @($stopOp))
            $stopTask.Wait(10000) | Out-Null
        }
    } catch {}

    Write-OK "Hotspot stopped"
}

# =============================================================================
#  INTERNET CONNECTION SHARING (ICS)
#  Routes internet from company adapter through to the dongle customers
# =============================================================================
function Enable-ICS {
    param([string]$PublicAdapterName, [string]$DongleVirtualAdapterName)
    Write-STEP 3 "Setting up Internet Connection Sharing..."
    Write-INFO "Internet (public) : $PublicAdapterName"
    Write-INFO "Customer (private): $DongleVirtualAdapterName"

    try {
        Set-Service SharedAccess -StartupType Automatic
        Start-Service SharedAccess
        Start-Sleep -Milliseconds 1000

        $ns       = New-Object -ComObject HNetCfg.HNetShare.1
        $allConns = @($ns.EnumEveryConnection())
        $pub = $null; $priv = $null

        foreach ($c in $allConns) {
            try {
                $p = $ns.NetConnectionProps($c)
                if ($p.Name -eq $PublicAdapterName)         { $pub  = $c }
                if ($p.Name -eq $DongleVirtualAdapterName)  { $priv = $c }
                # Also match "Local Area Connection*" style names for virtual adapters
                if (-not $priv -and $p.Name -match 'Local Area Connection|Virtual|Hosted') { $priv = $c }
            } catch {}
        }

        if (-not $pub) {
            Write-WARN "Could not find public adapter '$PublicAdapterName' in ICS. Skipping ICS."
            Write-WARN "Customers will connect to hotspot but won't have internet access."
            Write-WARN "(Print upload still works on the local hotspot network.)"
            return $false
        }

        # Disable any existing ICS first
        foreach ($c in $allConns) {
            try { $ns.INetSharingConfigurationForINetConnection($c).DisableSharing() } catch {}
        }
        Start-Sleep -Milliseconds 500

        # Enable ICS
        $ns.INetSharingConfigurationForINetConnection($pub).EnableSharing(0)   # Public
        if ($priv) {
            $ns.INetSharingConfigurationForINetConnection($priv).EnableSharing(1)  # Private
        }

        Write-OK "ICS enabled: company network -> customer hotspot"
        return $true
    } catch {
        Write-WARN "ICS setup skipped: $($_.Exception.Message.Split([char]10)[0])"
        Write-WARN "Print upload still works without ICS."
        return $false
    }
}

function Disable-ICS {
    Write-STEP 1 "Disabling Internet Connection Sharing..."
    try {
        $ns = New-Object -ComObject HNetCfg.HNetShare.1
        foreach ($c in @($ns.EnumEveryConnection())) {
            try { $ns.INetSharingConfigurationForINetConnection($c).DisableSharing() } catch {}
        }
        Stop-Service SharedAccess -Force
        Set-Service SharedAccess -StartupType Manual
        Write-OK "ICS disabled"
    } catch { Write-WARN "ICS disable skipped" }
}

# =============================================================================
#  NETWORK READINESS (URL ACL + FIREWALL)
# =============================================================================
function Ensure-NetworkReady {
    param([int]$Port)
    # URL ACL - allows server to bind to all interfaces without admin on every run
    $acl = (netsh http show urlacl url=http://+:$Port/ 2>&1) -join " "
    if ($acl -notmatch 'Reserved URL') {
        Write-INFO "Registering URL ACL for port $Port..."
        netsh http delete urlacl url=http://+:$Port/ 2>&1 | Out-Null
        netsh http add urlacl url=http://+:$Port/ user=Everyone 2>&1 | Out-Null
        Write-OK "Port $Port registered for all interfaces"
    }
    # Firewall
    if (-not (Get-NetFirewallRule -DisplayName $FW_RULE -ErrorAction SilentlyContinue)) {
        Write-INFO "Adding Windows Firewall rule (port $Port)..."
        New-NetFirewallRule -DisplayName $FW_RULE -Direction Inbound -Protocol TCP `
            -LocalPort $Port -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
        Write-OK "Firewall rule added"
    }
}

function Remove-NetworkRules {
    Remove-NetFirewallRule -DisplayName $FW_RULE -ErrorAction SilentlyContinue
    netsh http delete urlacl url=http://+:$APP_PORT/ 2>&1 | Out-Null
    Write-OK "Firewall rule and URL ACL removed"
}

# =============================================================================
#  HOTSPOT IP DETECTION
# =============================================================================
function Get-HotspotGatewayIP {
    param([string]$DongleAdapterName = "")

    # Look for the virtual adapter created by Mobile Hotspot / hosted network
    $virtualAdapters = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -match 'Wi-Fi Direct Virtual Adapter|Hosted Network Virtual Adapter' `
        -and $_.Status -eq 'Up'
    }

    foreach ($a in $virtualAdapters) {
        $ip = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip -and $ip.IPAddress -ne '127.0.0.1' -and $ip.IPAddress -notmatch '^169\.254\.') { return $ip.IPAddress }
    }

    # Try the dongle adapter itself
    if ($DongleAdapterName) {
        $da = Get-NetAdapter -Name $DongleAdapterName -ErrorAction SilentlyContinue
        if ($da) {
            $ip = Get-NetIPAddress -InterfaceIndex $da.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ip -and $ip.IPAddress -ne '127.0.0.1' -and $ip.IPAddress -notmatch '^169\.254\.') { return $ip.IPAddress }
        }
    }

    # Windows ICS/hosted network default
    return $HOTSPOT_IP
}

# =============================================================================
#  STATUS DISPLAY
# =============================================================================
function Test-HotspotActive {
    # Check WinRT Mobile Hotspot first
    $tm = Get-TetheringManager
    if ($tm -and $tm.TetheringOperationalState -eq "On") { return $true }

    # Check netsh hosted network
    $hs = (netsh wlan show hostednetwork 2>&1) -join " "
    if ($hs -match 'Status\s*:\s*Started') { return $true }

    # Check Wi-Fi Direct or Hosted Network virtual adapter that has a valid non-APIPA IP
    $virtual = Get-NetAdapter | Where-Object {
        $_.InterfaceDescription -match 'Wi-Fi Direct Virtual Adapter|Hosted Network Virtual Adapter' `
        -and $_.Status -eq 'Up'
    }
    if ($virtual) {
        foreach ($a in $virtual) {
            $ip = Get-NetIPAddress -InterfaceIndex $a.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ip -and $ip.IPAddress -ne '127.0.0.1' -and $ip.IPAddress -notmatch '^169\.254\.') { return $true }
        }
    }

    # Also check if 192.168.137.1 is assigned to any active adapter on this PC
    try {
        $hsIp = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
                Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -eq '192.168.137.1' }
        if ($hsIp) { return $true }
    } catch {}

    return $false
}

function Show-Status {
    $s      = Load-State
    $active = Test-HotspotActive
    $ssid   = if ($s -and $s.SSID)     { $s.SSID }     else { $DEFAULT_SSID }
    $pass   = if ($s -and $s.Password) { $s.Password } else { $DEFAULT_PASS }
    $dongle = if ($s -and $s.DongleAdapter) { $s.DongleAdapter } else { "Auto-select" }
    $ip     = if ($active) { Get-HotspotGatewayIP $dongle } else { "--" }

    Write-Host "  STATUS" -ForegroundColor White
    Write-Sep
    if ($active) {
        Write-Host "  Hotspot :  " -NoNewline; Write-Host "ACTIVE" -ForegroundColor Green
        Write-Host "  Adapter :  $dongle" -ForegroundColor White
        Write-Host "  WiFi    :  $ssid  (Password: $pass)" -ForegroundColor Cyan
        Write-Host "  IP      :  $ip" -ForegroundColor Yellow
        Write-Host "  URL     :  http://${ip}:${APP_PORT}${CUSTOMER_PATH}" -ForegroundColor Yellow
    } else {
        Write-Host "  Hotspot :  " -NoNewline; Write-Host "INACTIVE" -ForegroundColor DarkGray
        Write-Host "  WiFi    :  $ssid  (Password: $pass)" -ForegroundColor DarkGray
    }

    # Display all detected Wi-Fi adapters (Built-in and USB)
    $allAdapters = Get-AllWiFiAdapters
    if ($allAdapters.Count -gt 0) {
        foreach ($a in $allAdapters) {
            $isUsb     = ($a.PnPDeviceID -match '^USB\\' -or $a.InterfaceDescription -match 'USB|\bDongle\b')
            $typeLabel = if ($isUsb) { "[USB Dongle]" } else { "[Built-in Wi-Fi]" }
            $stLabel   = if ($a.Status -eq 'Up') { "Connected" } else { "Ready / Standby" }
            $col       = if ($a.Status -eq 'Up') { 'Green' } else { 'DarkCyan' }
            Write-Host "  Wi-Fi   :  $typeLabel $($a.Name) - $($a.InterfaceDescription) ($stLabel)" -ForegroundColor $col
        }
    } else {
        Write-Host "  Wi-Fi   :  NO WI-FI ADAPTER DETECTED" -ForegroundColor Red
        Write-Host "             (Please ensure Wi-Fi is enabled in Windows, or plug in a USB Wi-Fi dongle)" -ForegroundColor Yellow
    }
    Write-Sep
}

# =============================================================================
#  CONNECTION INFO
# =============================================================================
function Show-ConnectionInfo {
    param([string]$SSID, [string]$Password, [string]$IP)
    $url = "http://${IP}:${APP_PORT}${CUSTOMER_PATH}"
    Write-Host ""
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  CUSTOMER CONNECTION INFO                                  |" -ForegroundColor Green
    Write-Host "  |                                                             |" -ForegroundColor Green
    Write-Host "  |  WiFi Network  :  $($SSID.PadRight(42))|" -ForegroundColor White
    Write-Host "  |  Password      :  $($Password.PadRight(42))|" -ForegroundColor Yellow
    Write-Host "  |  Upload URL    :  $($url.PadRight(42))|" -ForegroundColor Cyan
    Write-Host "  |                                                             |" -ForegroundColor Green
    Write-Host "  |  HOW CUSTOMERS CONNECT:                                     |" -ForegroundColor Green
    Write-Host "  |  1. Phone Settings -> WiFi -> Connect to: $SSID" -ForegroundColor White
    Write-Host "  |  2. Open phone browser                                      |" -ForegroundColor White
    Write-Host "  |  3. Type: $url" -ForegroundColor Cyan
    Write-Host "  |  4. Choose photo -> Send to Print                           |" -ForegroundColor White
    Write-Host "  |                                                             |" -ForegroundColor Green
    Write-Host "  +------------------------------------------------------------+" -ForegroundColor Green
    Write-Host ""

    # Generate QR code in browser (fallback to text if no internet)
    $qr = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=20&data=" + [Uri]::EscapeDataString($url)
    Write-INFO "Opening QR code in browser for customer scanning..."
    Start-Process $qr -ErrorAction SilentlyContinue
}

# =============================================================================
#  MENU ACTION: ENABLE HOTSPOT
# =============================================================================
function Do-Enable {
    Write-Header
    Write-Host "  ENABLE CUSTOMER HOTSPOT" -ForegroundColor Green
    Write-Sep
    Write-Host ""

    $s    = Load-State
    $SSID = if ($s -and $s.SSID)     { $s.SSID }     else { $DEFAULT_SSID }
    $PASS = if ($s -and $s.Password) { $s.Password } else { $DEFAULT_PASS }

    # ---- Detect Wi-Fi adapters (USB dongle or built-in) ----
    $allAdapters = Get-AllWiFiAdapters
    if ($allAdapters.Count -eq 0) {
        Write-FAIL "No Wi-Fi adapter detected on this system."
        Write-WARN "Please ensure a Wi-Fi adapter is plugged in or enabled in Windows Settings."
        Pause-Now; return
    }

    $usbAdapters = Get-USBWiFiAdapters
    $dongleName = ""
    $dongleDesc = ""

    if ($usbAdapters.Count -gt 0) {
        $dongle     = Select-DongleAdapter -Adapters $usbAdapters
        $dongleName = $dongle.Name
        $dongleDesc = "$($dongle.InterfaceDescription) [USB Dongle]"
        Write-OK "Selected adapter: $dongleDesc ($dongleName)"
    } else {
        $primary = $allAdapters | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if (-not $primary) { $primary = $allAdapters | Select-Object -First 1 }
        $dongleName = $primary.Name
        $dongleDesc = "$($primary.InterfaceDescription) [Built-in Wi-Fi]"
        Write-OK "Selected adapter: $dongleDesc ($dongleName)"
    }
    Write-Host ""

    # ---- Internet adapter (company network - DO NOT TOUCH ITS CONFIG) ----
    $intAdapter = Get-InternetAdapter -ExcludeAdapterName $dongleName
    if (-not $intAdapter) { $intAdapter = Get-InternetAdapter }
    $intName    = if ($intAdapter) { $intAdapter.Name } else { "Wi-Fi" }
    Write-INFO "Company network adapter (untouched): $intName ($($intAdapter.InterfaceDescription))"
    Write-Host ""

    # ---- Network readiness ----
    Ensure-NetworkReady -Port $APP_PORT

    # ---- Enable hotspot ----
    $method = Enable-DongleHotspot -SSID $SSID -Password $PASS -DongleAdapterName $dongleName
    Start-Sleep -Seconds 3

    # Verify if hotspot is actually active
    if (-not (Test-HotspotActive)) {
        Write-FAIL "Hotspot could not be verified automatically."
        Write-WARN "If the Mobile Hotspot switch is ON in Windows Settings, you can proceed."
        $manualOk = Read-Host "  Is Mobile Hotspot ON in Windows Settings? (y/n)"
        if ($manualOk.Trim().ToLower() -ne 'y') {
            Pause-Now; return
        }
    }

    # If legacy netsh was used, enable ICS
    if ($method -eq "netsh") {
        $virtualAdapter = Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -match 'Virtual|Hosted' `
            -and $_.Status -eq 'Up'
        } | Select-Object -First 1
        $virtualName = if ($virtualAdapter) { $virtualAdapter.Name } else { "Local Area Connection* 1" }
        Write-Host ""
        Enable-ICS -PublicAdapterName $intName -DongleVirtualAdapterName $virtualName
        Start-Sleep -Seconds 2
    } else {
        $virtualAdapter = Get-NetAdapter | Where-Object {
            $_.InterfaceDescription -match 'Wi-Fi Direct Virtual Adapter' `
            -and $_.Status -eq 'Up'
        } | Select-Object -First 1
        $virtualName = if ($virtualAdapter) { $virtualAdapter.Name } else { "Wi-Fi Direct" }
    }

    # ---- Get hotspot IP ----
    $hsIP = Get-HotspotGatewayIP -DongleAdapterName $dongleName
    Write-OK "Hotspot gateway IP: $hsIP"

    # ---- Save state ----
    Save-State @{
        Active          = $true
        SSID            = $SSID
        Password        = $PASS
        DongleAdapter   = $dongleName
        DongleDesc      = $dongleDesc
        VirtualAdapter  = $virtualName
        InternetAdapter = $intName
        HotspotIP       = $hsIP
        HotspotMethod   = $method
        EnabledAt       = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    # ---- Start print server if not running ----
    Write-Host ""
    $running = (netstat -ano 2>$null) -join "" | Select-String ":$APP_PORT\b"
    if (-not $running) {
        $ps1 = Join-Path $PSScriptRoot "Start-App.ps1"
        if (Test-Path $ps1) {
            Write-STEP 4 "Starting GrandStores print server..."
            Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File `"$ps1`""
            Start-Sleep -Seconds 3
            Write-OK "Print server running on port $APP_PORT"
        }
    } else {
        Write-OK "Print server already running on port $APP_PORT"
    }

    # ---- Show connection info ----
    Show-ConnectionInfo -SSID $SSID -Password $PASS -IP $hsIP
    Write-Host "  >> CUSTOMER HOTSPOT IS ACTIVE <<" -ForegroundColor Green
    Write-Host "  Company network connection remains untouched." -ForegroundColor DarkGray
    Write-Host ""
    Pause-Now
}

# =============================================================================
#  MENU ACTION: DISABLE HOTSPOT
# =============================================================================
function Do-Disable {
    Write-Header
    Write-Host "  DISABLE HOTSPOT - REVERT TO NORMAL" -ForegroundColor Yellow
    Write-Sep
    Write-Host ""

    Disable-DongleHotspot
    Write-Host ""
    Disable-ICS
    Write-Host ""
    Remove-NetworkRules
    Clear-State

    Write-Host ""
    Write-OK "Hotspot disabled."
    Write-OK "Company network adapter is fully restored."
    Write-OK "ICS disabled. Firewall rule removed."
    Write-Host ""
    Pause-Now
}

# =============================================================================
#  MENU ACTION: CHANGE CREDENTIALS
# =============================================================================
function Do-ChangeCredentials {
    Write-Header
    Write-Host "  CHANGE WiFi NAME AND PASSWORD" -ForegroundColor Cyan
    Write-Sep
    Write-Host ""

    $s    = Load-State
    $curS = if ($s -and $s.SSID)     { $s.SSID }     else { $DEFAULT_SSID }
    $curP = if ($s -and $s.Password) { $s.Password } else { $DEFAULT_PASS }

    Write-Host "  Current WiFi Name : $curS" -ForegroundColor DarkGray
    Write-Host "  Current Password  : $curP" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  NOTE: Changes take effect next time you enable the hotspot." -ForegroundColor DarkGray
    Write-Host ""

    $newS = Read-Host "  New WiFi Name (max 32 chars) [Enter to keep]"
    if ([string]::IsNullOrWhiteSpace($newS)) { $newS = $curS }
    if ($newS.Length -gt 32) { $newS = $newS.Substring(0,32) }

    $newP = Read-Host "  New Password (min 8 chars) [Enter to keep]"
    if ([string]::IsNullOrWhiteSpace($newP)) { $newP = $curP }
    elseif ($newP.Length -lt 8) {
        Write-WARN "Too short (min 8). Keeping current password."
        $newP = $curP
    }

    Save-State @{
        Active          = if ($s) { $s.Active }          else { $false }
        SSID            = $newS
        Password        = $newP
        DongleAdapter   = if ($s) { $s.DongleAdapter }   else { "" }
        DongleDesc      = if ($s) { $s.DongleDesc }       else { "" }
        VirtualAdapter  = if ($s) { $s.VirtualAdapter }   else { "" }
        InternetAdapter = if ($s) { $s.InternetAdapter }  else { "" }
        HotspotIP       = if ($s) { $s.HotspotIP }        else { $HOTSPOT_IP }
        HotspotMethod   = if ($s) { $s.HotspotMethod }    else { "" }
        EnabledAt       = if ($s) { $s.EnabledAt }        else { "" }
    }

    Write-Host ""
    Write-OK "Saved: WiFi=$newS | Password=$newP"
    Write-Host ""
    Pause-Now
}

# =============================================================================
#  MENU ACTION: SHOW QR CODE
# =============================================================================
function Do-QRCode {
    Write-Header
    Write-Host "  CUSTOMER QR CODE" -ForegroundColor Cyan
    Write-Sep
    Write-Host ""

    $s  = Load-State
    $ip = if ($s -and $s.HotspotIP) { $s.HotspotIP } else { Get-HotspotGatewayIP }
    $url = "http://${ip}:${APP_PORT}${CUSTOMER_PATH}"

    Write-Host "  Upload URL: $url" -ForegroundColor Cyan
    Write-Host ""
    $qr = "https://api.qrserver.com/v1/create-qr-code/?size=500x500&margin=20&data=" + [Uri]::EscapeDataString($url)
    Start-Process $qr -ErrorAction SilentlyContinue
    Write-OK "QR code opened in browser."
    Write-Host ""
    Write-Host "  Display this QR code so customers can scan it with their phone camera." -ForegroundColor Green
    Write-Host "  It opens the photo upload page automatically." -ForegroundColor Green
    Pause-Now
}

# =============================================================================
#  MENU ACTION: CONNECTED DEVICES
# =============================================================================
function Do-Devices {
    Write-Header
    Write-Host "  CONNECTED DEVICES" -ForegroundColor Cyan
    Write-Sep
    Write-Host ""

    $hs = (netsh wlan show hostednetwork 2>&1) -join " "
    if ($hs -match 'Status\s*:\s*Started') {
        $n = if ($hs -match 'Number of clients\s*:\s*(\d+)') { $Matches[1] } else { "?" }
        Write-Host "  Connected clients: $n" -ForegroundColor Green
    } else {
        Write-WARN "Hosted network not active via netsh."
    }

    Write-Host ""
    Write-Host "  ARP table (devices on hotspot network):" -ForegroundColor Yellow
    $arpLines = arp -a 2>&1 | Where-Object { $_ -match '\d+\.\d+\.\d+\.\d+' -and $_ -notmatch '255\.' }
    if ($arpLines) {
        $arpLines | ForEach-Object { Write-Host "    $_" -ForegroundColor White }
    } else {
        Write-Host "    (No devices visible yet - they may not have communicated recently)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Pause-Now
}

# =============================================================================
#  MENU ACTION: DIAGNOSTICS
# =============================================================================
function Do-Diagnostics {
    Write-Header
    Write-Host "  DIAGNOSTICS" -ForegroundColor Cyan
    Write-Sep
    Write-Host ""

    Write-Host "  [1] Wi-Fi Adapter Detection (Built-in & USB):" -ForegroundColor White
    $allW = Get-AllWiFiAdapters
    if ($allW.Count -gt 0) {
        $allW | ForEach-Object {
            $isU = ($_.PnPDeviceID -match '^USB\\' -or $_.InterfaceDescription -match 'USB|\bDongle\b')
            $tag = if ($isU) { "[USB Dongle]" } else { "[Built-in Wi-Fi]" }
            Write-Host "      FOUND: $tag $($_.Name)  |  $($_.InterfaceDescription)  |  Status: $($_.Status)" -ForegroundColor Green
        }
    } else {
        Write-Host "      NOT FOUND - Please ensure Wi-Fi is enabled or plug in a USB Wi-Fi dongle" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  [2] All Network Adapters:" -ForegroundColor White
    Get-NetAdapter | ForEach-Object {
        $busType = if ($_.PnPDeviceID -match '^USB\\') { "[USB]" } else { "[PCIe/built-in]" }
        $col = if ($_.Status -eq 'Up') { 'Green' } else { 'DarkGray' }
        Write-Host ("      {0,-30} {1,-16} [{2,-12}] {3}" -f $_.Name, $busType, $_.Status, $_.InterfaceDescription) -ForegroundColor $col
    }

    Write-Host ""
    Write-Host "  [3] Hosted Network (netsh):" -ForegroundColor White
    netsh wlan show hostednetwork 2>&1 | Where-Object { $_ -match 'Mode|SSID|Status|clients' } |
        ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "  [4] WiFi Driver Hosted Network Support:" -ForegroundColor White
    $allWifi = Get-AllWiFiAdapters
    foreach ($a in $allWifi) {
        $driverInfo = netsh wlan show drivers interface="$($a.Name)" 2>&1
        $hosted = ($driverInfo | Select-String "Hosted network") -join ""
        if (-not $hosted) { $hosted = "(info not available)" }
        Write-Host "      $($a.Name): $hosted" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  [5] Company (internet) Adapter:" -ForegroundColor White
    $usbs = Get-USBWiFiAdapters
    $dongleName = if ($usbs.Count -gt 0) { $usbs[0].Name } else { "" }
    $ia = Get-InternetAdapter -ExcludeAdapterName $dongleName
    if ($ia) { Write-Host "      $($ia.Name)  |  $($ia.InterfaceDescription)  |  $($ia.Status)" -ForegroundColor Green }
    else     { Write-Host "      Not detected" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  [6] All IPv4 Addresses:" -ForegroundColor White
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne '127.0.0.1' } |
        ForEach-Object { Write-Host ("      {0,-30} {1}" -f $_.InterfaceAlias, $_.IPAddress) -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "  [7] ICS Service (SharedAccess):" -ForegroundColor White
    $svc = Get-Service SharedAccess -ErrorAction SilentlyContinue
    Write-Host "      Status: $(if($svc){$svc.Status}else{'Not found'})" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "  [8] URL ACL (port $APP_PORT):" -ForegroundColor White
    $acl = (netsh http show urlacl url=http://+:$APP_PORT/ 2>&1) -join " "
    $aclOk = $acl -match 'Reserved URL'
    Write-Host "      $(if($aclOk){'REGISTERED - OK'}else{'NOT REGISTERED - run Setup.bat first'})" -ForegroundColor $(if($aclOk){'Green'}else{'Red'})

    Write-Host ""
    Write-Host "  [9] Firewall Rule:" -ForegroundColor White
    $fw = Get-NetFirewallRule -DisplayName $FW_RULE -ErrorAction SilentlyContinue
    Write-Host "      $(if($fw){"PRESENT (Enabled=$($fw.Enabled))"}else{'NOT PRESENT - will be added when hotspot is enabled'})" -ForegroundColor $(if($fw){'Green'}else{'Yellow'})

    Write-Host ""
    Write-Host "  [10] Print Server (port $APP_PORT):" -ForegroundColor White
    $srv = (netstat -ano 2>$null) -join " " | Select-String ":$APP_PORT "
    Write-Host "       $(if($srv){'LISTENING - OK'}else{'NOT RUNNING - start via Start-App.bat'})" -ForegroundColor $(if($srv){'Green'}else{'Yellow'})

    Write-Host ""
    Pause-Now
}

# =============================================================================
#  MAIN MENU LOOP
# =============================================================================
while ($true) {
    Write-Header
    Show-Status
    Write-Host ""
    Write-Host "  MENU" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1]  Enable Hotspot    - Start customer WiFi (plug dongle in first)" -ForegroundColor Green
    Write-Host "  [2]  Disable Hotspot   - Turn off, revert everything" -ForegroundColor Yellow
    Write-Host "  [3]  Change WiFi Name and Password" -ForegroundColor Cyan
    Write-Host "  [4]  Show Customer QR Code" -ForegroundColor Cyan
    Write-Host "  [5]  View Connected Devices" -ForegroundColor Cyan
    Write-Host "  [6]  Diagnostics / Troubleshoot" -ForegroundColor DarkGray
    Write-Host "  [0]  Exit" -ForegroundColor DarkGray
    Write-Host ""
    $ch = Read-Host "  Select option"
    switch ($ch.Trim()) {
        '1' { Do-Enable }
        '2' { Do-Disable }
        '3' { Do-ChangeCredentials }
        '4' { Do-QRCode }
        '5' { Do-Devices }
        '6' { Do-Diagnostics }
        '0' { Write-Host ""; exit 0 }
        default { Write-WARN "Invalid option."; Start-Sleep 1 }
    }
}
