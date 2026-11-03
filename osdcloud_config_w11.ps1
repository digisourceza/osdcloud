# Log everything to the USB stick so it survives the reboot
$usb = (Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\OSDCloud") }).DriveLetter | Select-Object -First 1
$serial = (Get-CimInstance Win32_BIOS).SerialNumber
$UsbLogs = "$($usb):\DeployLogs\$serial-$(Get-Date -Format yyyyMMdd-HHmm)"
New-Item $UsbLogs -ItemType Directory -Force | Out-Null
Start-Transcript -Path "$UsbLogs\Deploy-Transcript.log" -Append

Write-Host -ForegroundColor Green "Starting OSDCloud ZTI"
Start-Sleep -Seconds 5

Start-OSDCloud -OSVersion 'Windows 11' -OSBuild 26H2 -OSEdition Pro -OSLanguage en-us -OSLicense Retail -ZTI

try { Start-Transcript -Path "$UsbLogs\Deploy-Transcript.log" -Append | Out-Null } catch {}

#=================================================
# Inject Intel VMD / RST storage driver into the applied OS
#=================================================
Write-Host -ForegroundColor Green "Checking for Intel VMD driver injection"
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer

if (-not (Test-Path 'C:\Windows\System32\config\SYSTEM')) {
    Write-Warning "Applied Windows not found on C: - skipping driver injection"
}
elseif ($cpu -notmatch 'Intel') {
    Write-Host -ForegroundColor DarkGray "Non-Intel CPU ($cpu) - skipping VMD driver injection"
}
elseif (-not (Test-Path "$($usb):\OSDCloud\Drivers\VMD")) {
    Write-Warning "OSDCloud\Drivers\VMD folder not found on USB - skipping driver injection"
}
else {
    dism /Image:C:\ /Add-Driver /Driver:"$($usb):\OSDCloud\Drivers\VMD" /Recurse /LogPath:"$UsbLogs\VMD-Inject.log"
    if ($LASTEXITCODE -eq 0) { Write-Host -ForegroundColor Green "VMD driver injected successfully" }
    else { Write-Warning "DISM returned exit code $LASTEXITCODE" }
}

#=================================================
# Copy OSDCloud and setup logs to the USB
#=================================================
Copy-Item 'X:\OSDCloud\Logs'  -Destination "$UsbLogs\WinPE-OSDCloudLogs" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item 'C:\OSDCloud\Logs'  -Destination "$UsbLogs\C-OSDCloudLogs"     -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item 'C:\Windows\Panther' -Destination "$UsbLogs\Panther"           -Recurse -Force -ErrorAction SilentlyContinue

Stop-Transcript

Write-Host -ForegroundColor Green "Restarting in 20 seconds!"
Start-Sleep -Seconds 20
wpeutil reboot
