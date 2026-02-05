
$targets = @{
    "C:\Program Files\NVIDIA Corporation" = "D:\software\nvidia-assets\NVIDIA Corporation";
    "C:\Program Files\NVIDIA GPU Computing Toolkit" = "D:\software\nvidia-assets\NVIDIA GPU Computing Toolkit"
}

foreach ($link in $targets.Keys) {
    $target = $targets[$link]
    if (Test-Path $target) {
        if (-not (Test-Path $link)) {
            Write-Host "Creating Junction: $link -> $target"
            New-Item -ItemType Junction -Path $link -Value $target
        } else {
            Write-Host "Link already exists: $link"
        }
    } else {
        Write-Warning "Target path not found on D drive: $target"
    }
}
