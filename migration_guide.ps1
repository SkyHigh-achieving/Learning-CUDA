
# 1. User Folder Migration Script (Documents, Downloads, Desktop)
$targetDrive = "D:\Users\$env:USERNAME"
$folders = @("Documents", "Downloads", "Desktop", "Music", "Pictures", "Videos")

Write-Host "--- User Folder Migration Plan ---"
foreach ($folder in $folders) {
    $currentPath = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::$folder)
    $targetPath = Join-Path $targetDrive $folder
    Write-Host "Folder: $folder"
    Write-Host "  Current: $currentPath"
    Write-Host "  Proposed Target: $targetPath"
}

# 2. Registry Cleanup Recommendation (Instructions)
Write-Host "`n--- Registry & Software Cleanup ---"
Write-Host "1. Open 'appwiz.cpl' to uninstall unused programs."
Write-Host "2. Use CCleaner or similar tools for registry residue (Manual step)."

# 3. System Restore & Hibernation Optimization
Write-Host "`n--- System Optimization ---"
Write-Host "1. Hibernation: 'powercfg -h off' (Already done or recommended)"
Write-Host "2. System Restore: 'vssadmin resize shadowstorage /for=C: /on=C: /maxsize=5%'"

# 4. Large File Localization
Write-Host "`n--- Large File Detection (C:\ Top 10) ---"
Get-ChildItem C:\ -File -Recurse -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 10 | Select-Object Name, @{Name="SizeGB"; Expression={$_.Length / 1GB}}, Directory

# 5. Nsight Installation Solution
Write-Host "`n--- Nsight Installation Solution ---"
Write-Host "1. Verify VS: Run 'vswhere.exe' to ensure C++ workload is installed."
Write-Host "2. Nsight VS Integration: If Nsight menu is missing, try running the installer in 'Repair' mode."
Write-Host "3. Standalone Nsight: Download from https://developer.nvidia.com/nsight-visual-studio-edition-downloads"
