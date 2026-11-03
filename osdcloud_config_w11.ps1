#=================================================
# Digisource OSDCloud ZTI deployment script
#=================================================

# Find the USB stick (OSDCloudUSB partition, not WinPE's X: drive)
$usb = $null
try {
    $usb = (Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystemLabel -eq 'OSDCloudUSB' }).DriveLetter | Select-Object -First 1
    if (-not $usb) {
        $usb = (Get-Volume | Where-Object {
            $_.DriveLetter -and $_.DriveLetter -ne 'X' -and (Test-Path "$($_.DriveLetter):\OSDCloud\Drivers")
        }).DriveLetter | Select-Object -First 1
    }
} catch {}

# Logging to the USB
$UsbLogs = $null
if ($usb) {
    try {
        $serial = ((Get-CimInstance Win32_BIOS).SerialNumber -replace '[^A-Za-z0-9-]', '')
        if (-not $serial) { $serial = 'NoSerial' }
        $UsbLogs = "$($usb):\DeployLogs\$serial-$(Get-Date -Format yyyyMMdd-HHmm)"
        New-Item $UsbLogs -ItemType Directory -Force | Out-Null
        Start-Transcript -Path "$UsbLogs\Deploy-Transcript.log" -Append | Out-Null
    } catch {
        Write-Warning "Could not start transcript: $_"
        $UsbLogs = $null
    }
}
Write-Host -ForegroundColor Cyan "USB OSDCloud partition: $(if ($usb) { "$($usb):" } else { 'NOT FOUND' })"

#=================================================
# Deploy Windows
#=================================================
Write-Host -ForegroundColor Green "Starting OSDCloud ZTI"
Start-Sleep -Seconds 5

Start-OSDCloud -OSVersion 'Windows 11' -OSBuild 26H2 -OSEdition Pro -OSLanguage en-us -OSLicense Retail -ZTI

# OSDCloud stops our transcript - restart it
if ($UsbLogs) { try { Start-Transcript -Path "$UsbLogs\Deploy-Transcript.log" -Append | Out-Null } catch {} }

#=================================================
# Inject Intel VMD / RST storage driver (Intel machines only)
#=================================================
Write-Host -ForegroundColor Green "Checking for Intel VMD driver injection"
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer

if (-not (Test-Path 'C:\Windows\System32\config\SYSTEM')) {
    Write-Warning "Applied Windows not found on C: - skipping driver injection"
}
elseif ($cpu -notmatch 'Intel') {
    Write-Host -ForegroundColor DarkGray "Non-Intel CPU ($cpu) - skipping VMD driver injection"
}
elseif (-not $usb -or -not (Test-Path "$($usb):\OSDCloud\Drivers\VMD")) {
    Write-Warning "OSDCloud\Drivers\VMD folder not found on USB - skipping driver injection"
}
else {
    $dismLog = if ($UsbLogs) { "$UsbLogs\VMD-Inject.log" } else { 'X:\VMD-Inject.log' }
    dism /Image:C:\ /Add-Driver /Driver:"$($usb):\OSDCloud\Drivers\VMD" /Recurse /LogPath:"$dismLog"
    if ($LASTEXITCODE -eq 0) { Write-Host -ForegroundColor Green "VMD driver injected successfully" }
    else { Write-Warning "DISM returned exit code $LASTEXITCODE" }
}

#=================================================
# Apply unattend.xml to the installed Windows
#=================================================
Write-Host -ForegroundColor Green "Applying unattend.xml"
if ($usb -and (Test-Path "$($usb):\OSDCloud\Config\Unattend\unattend.xml")) {
    New-Item 'C:\Windows\Panther' -ItemType Directory -Force | Out-Null
    Copy-Item "$($usb):\OSDCloud\Config\Unattend\unattend.xml" -Destination 'C:\Windows\Panther\unattend.xml' -Force
    if (Test-Path 'C:\Windows\Panther\unattend.xml') {
        Write-Host -ForegroundColor Green "unattend.xml copied to C:\Windows\Panther"
    } else {
        Write-Warning "unattend.xml copy failed"
    }
}
else {
    Write-Warning "No unattend.xml found on USB - OOBE will run with default prompts"
}

#=================================================
# Copy logs to the USB
#=================================================
if ($UsbLogs) {
    Copy-Item 'C:\Windows\Temp\osdcloud-logs' -Destination "$UsbLogs\osdcloud-logs" -Recurse -Force -ErrorAction SilentlyContinue
    try { Stop-Transcript | Out-Null } catch {}
}

#=================================================
# Restart from WinPE
#=================================================
Write-Host -ForegroundColor Green "Restarting in 20 seconds!"
Start-Sleep -Seconds 20
wpeutil reboot
