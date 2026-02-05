
$source = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.1"
$target = "D:\software\cuda-toolkit"

if (!(Test-Path $target)) {
    New-Item -ItemType Directory -Force -Path $target
}

Write-Host "Copying CUDA Toolkit from $source to $target..."
robocopy $source $target /E /R:1 /W:1

# Update Path for the current session
$env:PATH = "$target\bin;$target\libnvvp;$env:PATH"

Write-Host "Verifying nvcc..."
& "$target\bin\nvcc.exe" --version
