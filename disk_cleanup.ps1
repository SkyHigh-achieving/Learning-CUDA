
function Get-DiskSpace {
    $drive = Get-PSDrive C
    $used = [math]::Round($drive.Used / 1GB, 2)
    $free = [math]::Round($drive.Free / 1GB, 2)
    Write-Host "C Drive Status: Used: $used GB, Free: $free GB"
}

Write-Host "--- Disk Space Analysis ---"
Get-DiskSpace

# 1. Temp Files Analysis
$tempSize = (Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "User Temp Folder Size: $([math]::Round($tempSize, 2)) MB"

$winTempSize = (Get-ChildItem "C:\Windows\Temp" -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Windows Temp Folder Size: $([math]::Round($winTempSize, 2)) MB"

# 2. Hibernation Check
Write-Host "--- Hibernation Status ---"
powercfg /a

# 3. System Restore Check
Write-Host "--- System Restore Storage ---"
vssadmin list shadowstorage

# 4. Safe Cleanup (Pre-defined items)
Write-Host "--- Executing Safe Cleanup ---"
# Remove temp files
Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Clean Windows Update Cache (SoftwareDistribution)
# Note: Usually requires stopping wuauserv service, skipping for now to avoid side effects without user confirmation

Write-Host "--- Post-Cleanup Status ---"
Get-DiskSpace
