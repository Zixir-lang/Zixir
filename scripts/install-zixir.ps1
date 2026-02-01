# Zixir one-shot installer — includes:
#   Quick start: git clone https://github.com/Zixir-lang/Zixir.git, cd Zixir, git checkout v5.2.0,
#                mix deps.get, mix zig.get, mix compile
#   Optional GPU: CUDA (Windows) via install-optional-deps.ps1 -Install
# Usage: .\scripts\install-zixir.ps1 [install-dir] [-Force]
#   install-dir: where to clone (default: current directory). Repo will be install-dir\Zixir.
#   -Force: Replace existing installation if present
# Run from repo root to install into current dir, or from elsewhere: .\path\to\Zixir\scripts\install-zixir.ps1 C:\dev

param(
    [string]$InstallDir = $null,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/Zixir-lang/Zixir.git"
$Version = "v5.2.0"

# Determine install directory
if (-not $InstallDir) {
    $InstallDir = Get-Location
}
$ZixirDir = Join-Path $InstallDir "Zixir"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Zixir installer — Quick start + GPU (CUDA)" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# Check if we're already in repo root
if ((Test-Path "mix.exs") -and (Test-Path ".git")) {
    $ZixirDir = (Get-Location).Path
    Write-Host "Using current repo at $ZixirDir" -ForegroundColor Green
    Set-Location $ZixirDir
    
    # Fetch all tags to ensure version exists
    Write-Host "Fetching latest tags..." -ForegroundColor Gray
    git fetch origin --tags 2>$null
    if (-not $?) { git fetch origin }
    
    git checkout $Version
    if (-not $?) {
        Write-Error "Failed to checkout $Version. Please check your internet connection or the version tag."
        exit 1
    }
} 
# Check for existing installation
elseif (Test-Path $ZixirDir) {
    if (Test-Path (Join-Path $ZixirDir ".git")) {
        # Existing git repo - upgrade
        Write-Host "Existing Zixir installation found at $ZixirDir" -ForegroundColor Yellow
        
        if (-not $Force) {
            $ans = Read-Host "Upgrade existing installation to $Version? [Y/n]"
            if ($ans -match '^[nN]') {
                Write-Host "Installation cancelled. Use -Force flag to skip this prompt." -ForegroundColor Yellow
                exit 0
            }
        }
        
        Write-Host "Upgrading existing installation to $Version..." -ForegroundColor Cyan
        Set-Location $ZixirDir
        
        # Stash any local changes
        git stash 2>$null
        
        # Fetch all tags
        Write-Host "Fetching latest tags..." -ForegroundColor Gray
        git fetch origin --tags 2>$null
        if (-not $?) { git fetch origin }
        
        git checkout $Version
        if (-not $?) {
            Write-Error "Failed to checkout $Version. You may need to resolve conflicts manually."
            exit 1
        }
    } else {
        # Directory exists but is not a git repo
        Write-Host "Directory $ZixirDir exists but is not a Zixir installation" -ForegroundColor Yellow
        
        if (-not $Force) {
            $ans = Read-Host "Remove existing directory and install fresh? [y/N]"
            if ($ans -notmatch '^[yY]') {
                Write-Host "Installation cancelled. Use -Force flag to skip this prompt." -ForegroundColor Yellow
                exit 0
            }
        }
        
        Write-Host "Removing existing directory..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force $ZixirDir
        
        Write-Host "Cloning Zixir $Version into $ZixirDir..." -ForegroundColor Cyan
        git clone $RepoUrl $ZixirDir
        Set-Location $ZixirDir
        git checkout $Version
    }
} else {
    # Fresh install
    Write-Host "Cloning Zixir $Version into $ZixirDir..." -ForegroundColor Cyan
    git clone $RepoUrl $ZixirDir
    Set-Location $ZixirDir
    git checkout $Version
}

Write-Host ""
Write-Host "--- mix deps.get ---" -ForegroundColor Gray
mix deps.get
if (-not $?) {
    Write-Error "mix deps.get failed. Please check your internet connection."
    exit 1
}

Write-Host ""
Write-Host "--- mix zig.get ---" -ForegroundColor Gray
mix zig.get
if (-not $?) {
    Write-Error "mix zig.get failed. Please check your internet connection."
    exit 1
}

Write-Host ""
Write-Host "--- mix compile ---" -ForegroundColor Gray
mix compile
if (-not $?) {
    Write-Error "mix compile failed. Please check the error messages above."
    exit 1
}

Write-Host ""
Write-Host "✓ Quick start complete!" -ForegroundColor Green
Write-Host "Verify installation: mix zixir.run examples/hello.zixir" -ForegroundColor Green
Write-Host ""

# Optional GPU installation
Write-Host "Optional: Install GPU dependencies (CUDA) for GPU acceleration." -ForegroundColor Cyan
$ans = Read-Host "Install CUDA support now? [y/N]"
if ($ans -match '^[yY]') {
    if (Test-Path (Join-Path $ZixirDir "scripts\install-optional-deps.ps1")) {
        & (Join-Path $ZixirDir "scripts\install-optional-deps.ps1") -Install
    } else {
        Write-Host "GPU installer not found. You can install CUDA manually later." -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipped. Install later with: .\scripts\install-optional-deps.ps1 -Install" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "Location: $ZixirDir" -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. cd $ZixirDir" -ForegroundColor Gray
Write-Host "  2. mix zixir.run examples/hello.zixir" -ForegroundColor Gray
Write-Host "  3. See README.md and SETUP_GUIDE.md for more" -ForegroundColor Gray
