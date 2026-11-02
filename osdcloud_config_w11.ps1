Write-Host -ForegroundColor Green "Starting OSDCloud ZTI"
Start-Sleep -Seconds 5

# Deploy Windows (no -Restart, so we can inject drivers afterwards)
Start-OSDCloud -OSVersion 'Windows 11' -OSBuild 26H2 -OSEdition Pro -OSLanguage en-us -OSLicense Retail -ZTI

#=================================================
# Inject Intel VMD / RST storage driver into the applied OS
# Prevents INACCESSIBLE_BOOT_DEVICE on Intel machines with storage set to RAID On
#=================================================
Write-Host -ForegroundColor Green "Checking for Intel VMD driver injection"

$LogPath = 'X:\OSDCloud\Logs'
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer
$usb = (Get-Volume | Where-Object { $_.DriveLetter -and (Test-Path "$($_.DriveLetter):\OSDCloud\Drivers\VMD") }).DriveLetter | Select-Object -First 1

if (-not (Test-Path 'C:\Windows\System32\config\SYSTEM')) {
    Write-Warning "Applied Windows not found on C: - skipping driver injection"
}
elseif ($cpu -notmatch 'Intel') {
    Write-Host -ForegroundColor DarkGray "Non-Intel CPU ($cpu) - skipping VMD driver injection"
}
elseif (-not $usb) {
    Write-Warning "OSDCloud\Drivers\VMD folder not found on USB - skipping driver injection"
}
else {
    Write-Host -ForegroundColor Cyan "Injecting VMD driver from $($usb):\OSDCloud\Drivers\VMD"
    dism /Image:C:\ /Add-Driver /Driver:"$($usb):\OSDCloud\Drivers\VMD" /Recurse /LogPath:"$LogPath\VMD-Inject.log"

    if ($LASTEXITCODE -eq 0) {
        Write-Host -ForegroundColor Green "VMD driver injected successfully"
    }
    else {
        Write-Warning "DISM returned exit code $LASTEXITCODE - check $LogPath\VMD-Inject.log"
    }

    # Show what landed, for the screen/photo record
    dism /Image:C:\ /Get-Drivers /Format:Table | Select-String -Pattern 'iastor'
}

#=================================================
# Restart from WinPE
#=================================================
Write-Host -ForegroundColor Green "Restarting in 20 seconds!"
Start-Sleep -Seconds 20
wpeutil reboot
