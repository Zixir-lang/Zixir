# Zixir Bootstrap Installer
# This script can be run from ANY location - it downloads and runs the full installer
# Usage: iwr -useb https://raw.githubusercontent.com/Zixir-lang/Zixir/v5.2.0/scripts/install-zixir.ps1 | iex
# Or save and run: .\install-zixir.ps1 [install-dir] [-Force]

param(
    [string]$InstallDir = $null,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/Zixir-lang/Zixir.git"
$Version = "v5.2.0"
$ScriptUrl = "https://raw.githubusercontent.com/Zixir-lang/Zixir/$Version/scripts/install-zixir.ps1"

# Determine install directory
if (-not $InstallDir) {
    $InstallDir = Get-Location
}
$ZixirDir = Join-Path $InstallDir "Zixir"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Zixir Bootstrap Installer" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Check for existing installation
if (Test-Path $ZixirDir) {
    Write-Host "Existing Zixir directory found at $ZixirDir" -ForegroundColor Yellow
    
    if (-not $Force) {
        $ans = Read-Host "Remove and reinstall fresh? [Y/n]"
        if ($ans -match '^[nN]') {
            Write-Host "Installation cancelled. Use -Force flag to skip this prompt." -ForegroundColor Yellow
            exit 0
        }
    }
    
    Write-Host "Removing existing directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $ZixirDir
}

# Clone fresh
Write-Host "Cloning Zixir $Version..." -ForegroundColor Cyan
git clone $RepoUrl $ZixirDir
if (-not $?) {
    Write-Error "Failed to clone repository. Please check your internet connection."
    exit 1
}

Set-Location $ZixirDir

# Checkout version
git checkout $Version
if (-not $?) {
    Write-Error "Failed to checkout $Version"
    exit 1
}

# Check if the full installer exists
$FullInstaller = Join-Path $ZixirDir "scripts\install-zixir.ps1"
if (Test-Path $FullInstaller) {
    Write-Host "Running full installer..." -ForegroundColor Green
    & $FullInstaller -InstallDir $InstallDir
} else {
    # Fallback: run the install steps directly
    Write-Host "Running installation steps..." -ForegroundColor Green
    
    Write-Host ""
    Write-Host "--- mix deps.get ---" -ForegroundColor Gray
    mix deps.get
    if (-not $?) { exit 1 }
    
    Write-Host ""
    Write-Host "--- mix zig.get ---" -ForegroundColor Gray
    mix zig.get
    if (-not $?) { exit 1 }
    
    Write-Host ""
    Write-Host "--- mix compile ---" -ForegroundColor Gray
    mix compile
    if (-not $?) { exit 1 }
    
    Write-Host ""
    Write-Host "✓ Installation complete!" -ForegroundColor Green
    Write-Host "Location: $ZixirDir" -ForegroundColor Green
    Write-Host "Verify: mix zixir.run examples/hello.zixir" -ForegroundColor Green
}
