
$source1 = "C:\Program Files\NVIDIA Corporation"
$source2 = "C:\Program Files\NVIDIA GPU Computing Toolkit"
$targetBase = "D:\software\nvidia-assets"

# 1. Check Space
$driveD = Get-PSDrive D
$freeD = $driveD.Free / 1GB
Write-Host "D Drive Free Space: $([math]::Round($freeD, 2)) GB"

# 2. Create Target
if (!(Test-Path $targetBase)) {
    New-Item -ItemType Directory -Force -Path $targetBase
}

# 3. Stop NVIDIA Services (Best effort)
Write-Host "Stopping NVIDIA Services..."
Get-Service -Name "NV*" -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue

# 4. Copying
Write-Host "Copying NVIDIA Corporation..."
robocopy $source1 "$targetBase\NVIDIA Corporation" /E /R:1 /W:1 /MT:32

Write-Host "Copying NVIDIA GPU Computing Toolkit..."
robocopy $source2 "$targetBase\NVIDIA GPU Computing Toolkit" /E /R:1 /W:1 /MT:32

# 5. Create Symlinks (Requires Admin)
Write-Host "`n--- To complete the migration, run these in an ADMIN PowerShell ---"
Write-Host "Step A: Rename originals (Backup)"
Write-Host "Rename-Item '$source1' 'NVIDIA Corporation.bak'"
Write-Host "Rename-Item '$source2' 'NVIDIA GPU Computing Toolkit.bak'"

Write-Host "`nStep B: Create Junctions/Symlinks"
Write-Host "New-Item -ItemType Junction -Path '$source1' -Value '$targetBase\NVIDIA Corporation'"
Write-Host "New-Item -ItemType Junction -Path '$source2' -Value '$targetBase\NVIDIA GPU Computing Toolkit'"

Write-Host "`nStep C: Restart Services"
Write-Host "Get-Service -Name 'NV*' | Start-Service"
