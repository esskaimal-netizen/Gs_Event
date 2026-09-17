# ============================================================================
#  GRANDSTORES DIGITAL PHOTO EVENT SOFTWARE
#  Distribution Packaging & Standalone Installer Builder
# ============================================================================

$ErrorActionPreference = "Stop"

$sourceDir = "C:\GS_Event"
$distRootDir = "C:\GS_Event_Dist"
$stagedAppDir = Join-Path $distRootDir "GrandStores_Event"
$outputZip = "C:\GS_Event\GrandStores_Event_Setup.zip"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  BUILDING STANDALONE INSTALLATION SETUP FOR GRANDSTORES    " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Clean previous build staging
if (Test-Path $distRootDir) {
    Remove-Item $distRootDir -Recurse -Force | Out-Null
}
New-Item -ItemType Directory -Path $stagedAppDir -Force | Out-Null

Write-Host "`n[1/3] Staging clean application files..." -ForegroundColor Yellow

$coreFiles = @(
    "index.html",
    "app.js",
    "style.css",
    "gs_logo.png",
    "Start-App.bat",
    "Start-App.ps1",
    "CameraFtpServer.cs",
    "INSTALL_ON_THIS_PC.bat",
    "Setup.bat",
    "HotspotTool.bat",
    "HotspotTool.ps1",
    "FixHotspot.bat",
    "README_TESTING.txt",
    "README.txt"
)

foreach ($f in $coreFiles) {
    $src = Join-Path $sourceDir $f
    if (Test-Path $src) {
        Copy-Item $src -Destination $stagedAppDir -Force
        Write-Host "  + Staged: $f" -ForegroundColor DarkGray
    } else {
        Write-Warning "Missing file: $f"
    }
}

# Copy ASK300 SDK recursively
$askSrc = Join-Path $sourceDir "ASK300"
$askDest = Join-Path $stagedAppDir "ASK300"
Write-Host "  + Staging ASK-300 SDK..." -ForegroundColor DarkGray
Copy-Item $askSrc -Destination $askDest -Recurse -Force

# Copy Sample_Photos
$samplesSrc = Join-Path $sourceDir "Sample_Photos"
$samplesDest = Join-Path $stagedAppDir "Sample_Photos"
Write-Host "  + Staging Sample Photos..." -ForegroundColor DarkGray
Copy-Item $samplesSrc -Destination $samplesDest -Recurse -Force

# Create clean Camera_Incoming directory
$camDest = Join-Path $stagedAppDir "Camera_Incoming"
New-Item -ItemType Directory -Path $camDest -Force | Out-Null
Set-Content -Path (Join-Path $camDest "camera_ready.txt") -Value "Incoming Wi-Fi camera photos will be automatically saved here."

# Create clean Printed_Photos directory
$printedDest = Join-Path $stagedAppDir "Printed_Photos"
New-Item -ItemType Directory -Path $printedDest -Force | Out-Null
Set-Content -Path (Join-Path $printedDest "output_ready.txt") -Value "Processed and printed event photos will be saved here."

Write-Host "[OK] Clean staging complete in: $stagedAppDir" -ForegroundColor Green

# 2. Build GrandStores_Event_Setup.zip
Write-Host "`n[2/3] Creating portable ZIP archive: GrandStores_Event_Setup.zip..." -ForegroundColor Yellow
if (Test-Path $outputZip) { Remove-Item $outputZip -Force }

$zipTemp = Join-Path $distRootDir "GrandStores_Event_Setup.zip"
Set-Location $distRootDir
& tar.exe -a -cf $zipTemp "GrandStores_Event"
Copy-Item $zipTemp -Destination $outputZip -Force
$zipSizeMb = [Math]::Round((Get-Item $outputZip).Length / 1MB, 2)
Write-Host "[OK] ZIP package created: $outputZip ($zipSizeMb MB)" -ForegroundColor Green

# 3. Clean up staging
Set-Location $sourceDir
Remove-Item $distRootDir -Recurse -Force | Out-Null

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "  BUILD FINISHED SUCCESSFULLY!                              " -ForegroundColor Cyan
Write-Host "  ZIP Package: $outputZip ($zipSizeMb MB)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
