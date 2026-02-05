
# IDE Asset Migration Script
# Targets: Trae, VS Code, and Visual Studio caches/extensions

$userName = $env:USERNAME
$userProfile = $env:USERPROFILE
$targetBase = "D:\software\ide-assets"

if (-not (Test-Path $targetBase)) {
    New-Item -ItemType Directory -Path $targetBase
}

$migrationTasks = @(
    @{
        Name = "VS Code Extensions"
        Source = "$userProfile\.vscode\extensions"
        Target = "$targetBase\vscode-extensions"
    },
    @{
        Name = "Trae Extensions"
        Source = "$userProfile\.trae\extensions"
        Target = "$targetBase\trae-extensions"
    },
    @{
        Name = "VS Code Data"
        Source = "$env:APPDATA\Code"
        Target = "$targetBase\vscode-data"
    },
    @{
        Name = "Trae Data"
        Source = "$env:APPDATA\Trae"
        Target = "$targetBase\trae-data"
    },
    @{
        Name = "Visual Studio Packages"
        Source = "C:\ProgramData\Microsoft\VisualStudio\Packages"
        Target = "$targetBase\vs-packages"
    }
)

foreach ($task in $migrationTasks) {
    $src = $task.Source
    $dst = $task.Target
    
    Write-Host "--- Processing: $($task.Name) ---"
    
    if (Test-Path $src) {
        # 1. Copy data if target doesn't exist
        if (-not (Test-Path $dst)) {
            Write-Host "Copying data from $src to $dst..."
            robocopy $src $dst /E /R:1 /W:1 /MT:32 /MOVE
        } else {
            Write-Host "Target $dst already exists. Skipping copy."
        }
        
        # 2. Create Junction
        if (-not (Test-Path $src)) {
            Write-Host "Creating Junction: $src -> $dst"
            New-Item -ItemType Junction -Path $src -Value $dst
        } else {
            Write-Warning "Source $src still exists. Please close the application and delete the source folder manually before creating junction."
        }
    } else {
        Write-Host "Source $src not found. Skipping."
    }
}
