# Full install of optional GPU dependencies for Zixir: CUDA (Windows).
# Run from repo root: .\scripts\install-optional-deps.ps1 [-Install] [-OpenDownload]
# -Install: run winget or choco install if available (elevated may be required).
# -OpenDownload: open the NVIDIA CUDA download page in the browser.
# See SETUP_GUIDE.md for manual steps.

param(
    [switch]$Install,
    [switch]$OpenDownload
)

$ErrorActionPreference = "Continue"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Zixir — Full install of optional GPU deps (Windows)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Check for nvcc (CUDA) already present
$nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
if ($nvcc) {
    Write-Host "CUDA (nvcc) already in PATH." -ForegroundColor Green
    & nvcc --version 2>$null
    exit 0
}

# Options: install via package manager or show manual steps
$doInstall = $Install
$doOpen = $OpenDownload

if (-not $doInstall -and -not $doOpen) {
    Write-Host "CUDA Toolkit not found. Options:" -ForegroundColor Yellow
    Write-Host "  1) Run this script with -Install to try: winget install Nvidia.CUDA (or choco install cuda)" -ForegroundColor White
    Write-Host "  2) Run with -OpenDownload to open the NVIDIA CUDA download page" -ForegroundColor White
    Write-Host "  3) Manual: https://developer.nvidia.com/cuda-downloads" -ForegroundColor White
    Write-Host ""
    $r = Read-Host "Run install now? [y/N]"
    if ($r -match '^[yY]') { $doInstall = $true }
    else {
        $r2 = Read-Host "Open download page in browser? [y/N]"
        if ($r2 -match '^[yY]') { $doOpen = $true }
    }
}

if ($doOpen) {
    $url = "https://developer.nvidia.com/cuda-downloads"
    Write-Host "Opening $url ..." -ForegroundColor Cyan
    Start-Process $url
    Write-Host "Select: Windows -> x86_64 -> 10/11 -> exe (local). After install, restart the terminal." -ForegroundColor White
    exit 0
}

if ($doInstall) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    $choco = Get-Command choco -ErrorAction SilentlyContinue

    if ($winget) {
        Write-Host "Installing CUDA via winget (Nvidia.CUDA)..." -ForegroundColor Cyan
        Write-Host "You may need to run this script as Administrator." -ForegroundColor Gray
        & winget install Nvidia.CUDA --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Install started or completed. Restart the terminal and run: nvcc --version" -ForegroundColor Green
        } else {
            Write-Host "Winget install returned an error. Try manual install: https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
        }
    } elseif ($choco) {
        Write-Host "Installing CUDA via Chocolatey..." -ForegroundColor Cyan
        Write-Host "You may need to run this script as Administrator." -ForegroundColor Gray
        & choco install cuda -y
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Install started or completed. Restart the terminal and run: nvcc --version" -ForegroundColor Green
        } else {
            Write-Host "Choco install returned an error. Try manual install: https://developer.nvidia.com/cuda-downloads" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Neither winget nor Chocolatey found. Open download page? [y/N]" -ForegroundColor Yellow
        $open = Read-Host
        if ($open -match '^[yY]') {
            Start-Process "https://developer.nvidia.com/cuda-downloads"
        }
        Write-Host "Manual install: https://developer.nvidia.com/cuda-downloads" -ForegroundColor White
    }
} else {
    Write-Host "Skipped. To install later:" -ForegroundColor Gray
    Write-Host "  winget install Nvidia.CUDA" -ForegroundColor Gray
    Write-Host "  choco install cuda" -ForegroundColor Gray
    Write-Host "  Or: https://developer.nvidia.com/cuda-downloads" -ForegroundColor Gray
}

Write-Host ""
Write-Host 'Verify Zixir GPU after install: mix run -e "IO.inspect(Zixir.Compiler.GPU.available?())"' -ForegroundColor Gray
