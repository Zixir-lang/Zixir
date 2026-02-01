# Optional: install platform-specific GPU dependencies for Zixir (CUDA on Windows).
# Run from repo root: .\scripts\install-gpu-deps.ps1
# See SETUP_GUIDE.md for full GPU setup.

$ErrorActionPreference = "Continue"

Write-Host "Zixir GPU dependencies — checking platform: Windows" -ForegroundColor Cyan

# Check for nvcc (CUDA)
$nvcc = Get-Command nvcc -ErrorAction SilentlyContinue
if ($nvcc) {
    Write-Host "CUDA (nvcc) already in PATH." -ForegroundColor Green
    & nvcc --version 2>$null
    exit 0
}

# Check for NVIDIA GPU
$nvidiaSmi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
if (-not $nvidiaSmi) {
    Write-Host "nvidia-smi not found. Install NVIDIA drivers and CUDA Toolkit if you have an NVIDIA GPU." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "To install CUDA Toolkit on Windows:" -ForegroundColor Cyan
Write-Host "  1. Download: https://developer.nvidia.com/cuda-downloads" -ForegroundColor White
Write-Host "     Select: Windows -> x86_64 -> 10/11 -> exe (local)" -ForegroundColor White
Write-Host "  2. Or use a package manager (run from an elevated shell if needed):" -ForegroundColor White
Write-Host "     winget install Nvidia.CUDA" -ForegroundColor Gray
Write-Host "     choco install cuda" -ForegroundColor Gray
Write-Host ""
Write-Host "After install, restart the terminal and run: nvcc --version" -ForegroundColor White
Write-Host "See SETUP_GUIDE.md for step-by-step CUDA setup." -ForegroundColor Gray

# Optional: try winget if available and user wants it
$useWinget = $env:ZIXIR_GPU_INSTALL_WINGET -eq "1"
if ($useWinget) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host ""
        Write-Host "Attempting: winget install Nvidia.CUDA ..." -ForegroundColor Cyan
        & winget install Nvidia.CUDA --accept-package-agreements --accept-source-agreements 2>$null
    }
}

Write-Host ""
Write-Host 'Verify later with: mix run -e "IO.inspect(Zixir.Compiler.GPU.available?())"' -ForegroundColor Gray
