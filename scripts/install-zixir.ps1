# Zixir Production Installer
# Universal installer that works from any location
# Usage: .\scripts\install-zixir.ps1 [[-InstallDir] <path>] [-Force] [-SkipCUDA]
#   -InstallDir: Where to install (default: $env:USERPROFILE\Zixir or current dir)
#   -Force: Uninstall existing installation and reinstall fresh
#   -SkipCUDA: Skip CUDA installation prompt

param(
    [string]$InstallDir = $null,
    [switch]$Force,
    [switch]$SkipCUDA
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Configuration
$RepoUrl = "https://github.com/Zixir-lang/Zixir.git"
$Version = "v5.3.0"
$RepoName = "Zixir"

# Logging functions
function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        "Info" = "White"
        "Success" = "Green"
        "Warning" = "Yellow"
        "Error" = "Red"
        "Header" = "Cyan"
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $colorMap[$Level]
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}

# Cleanup function
function Invoke-Cleanup {
    param([string]$TargetDir)
    if (Test-Path $TargetDir) {
        Write-Log "Cleaning up: $TargetDir" "Warning"
        try {
            Remove-Item -Recurse -Force $TargetDir -ErrorAction Stop
            Write-Log "Cleanup successful" "Success"
        } catch {
            Write-Log "Failed to cleanup $TargetDir. You may need to run as Administrator or close any open files." "Error"
            throw
        }
    }
}

# Check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"
    
    $required = @(
        @{ Name = "git"; Command = "git --version" },
        @{ Name = "elixir"; Command = "elixir --version" },
        @{ Name = "mix"; Command = "mix --version" }
    )
    
    foreach ($tool in $required) {
        try {
            $null = Invoke-Expression $tool.Command 2>&1
            Write-Log "✓ $($tool.Name) found" "Success"
        } catch {
            Write-Log "✗ $($tool.Name) not found. Please install $($tool.Name) first." "Error"
            exit 1
        }
    }
}

# Main installation logic
function Install-Zixir {
    param(
        [string]$TargetDir,
        [bool]$IsReinstall = $false
    )
    
    # If reinstalling, clean up first
    if ($IsReinstall -and (Test-Path $TargetDir)) {
        Invoke-Cleanup $TargetDir
    }
    
    # Clone repository
    Write-Log "Cloning Zixir $Version..." "Info"
    try {
        git clone $RepoUrl $TargetDir 2>&1 | ForEach-Object { Write-Log $_ "Info" }
        if (-not $?) { throw "Git clone failed" }
    } catch {
        Write-Log "Failed to clone repository: $_" "Error"
        exit 1
    }
    
    # Checkout version
    Write-Log "Checking out $Version..." "Info"
    try {
        Set-Location $TargetDir
        git fetch origin --tags 2>&1 | Out-Null
        git checkout $Version 2>&1 | ForEach-Object { Write-Log $_ "Info" }
        if (-not $?) { throw "Git checkout failed" }
    } catch {
        Write-Log "Failed to checkout version: $_" "Error"
        Invoke-Cleanup $TargetDir
        exit 1
    }
    
    # Install dependencies
    Write-Log "Installing dependencies (mix deps.get)..." "Info"
    try {
        mix deps.get 2>&1 | ForEach-Object { Write-Log $_ "Info" }
        if (-not $?) { throw "mix deps.get failed" }
    } catch {
        Write-Log "Failed to get dependencies: $_" "Error"
        exit 1
    }
    
    Write-Log "Installing Zig dependencies (mix zig.get)..." "Info"
    try {
        mix zig.get 2>&1 | ForEach-Object { Write-Log $_ "Info" }
        if (-not $?) { throw "mix zig.get failed" }
    } catch {
        Write-Log "Failed to get Zig dependencies: $_" "Error"
        exit 1
    }
    
    # Compile
    Write-Log "Compiling Zixir (mix compile)..." "Info"
    try {
        mix compile 2>&1 | ForEach-Object { Write-Log $_ "Info" }
        if (-not $?) { throw "mix compile failed" }
    } catch {
        Write-Log "Compilation failed: $_" "Error"
        exit 1
    }
    
    Write-Log "✓ Zixir $Version installed successfully!" "Success"
}

# Optional CUDA installation
function Install-CUDA {
    param([string]$ZixirDir)
    
    if ($SkipCUDA) {
        Write-Log "Skipping CUDA installation (--SkipCUDA specified)" "Info"
        return
    }
    
    Write-Log "Optional: Install GPU dependencies (CUDA) for GPU acceleration." "Header"
    $response = Read-Host "Install CUDA support now? [y/N]"
    
    if ($response -match '^[yY]') {
        $cudaScript = Join-Path $ZixirDir "scripts\install-optional-deps.ps1"
        if (Test-Path $cudaScript) {
            Write-Log "Installing CUDA support..." "Info"
            try {
                & $cudaScript -Install 2>&1 | ForEach-Object { Write-Log $_ "Info" }
            } catch {
                Write-Log "CUDA installation failed: $_" "Warning"
                Write-Log "You can install CUDA manually later with: $cudaScript -Install" "Info"
            }
        } else {
            Write-Log "CUDA installer not found at $cudaScript" "Warning"
        }
    } else {
        Write-Log "Skipped CUDA installation" "Info"
    }
}

# Main execution
Write-Header "Zixir Production Installer v$Version"

# Check prerequisites
Test-Prerequisites

# Determine installation directory
if (-not $InstallDir) {
    # Default to user's home directory
    $InstallDir = Join-Path $env:USERPROFILE $RepoName
    Write-Log "No install directory specified, using default: $InstallDir" "Info"
} else {
    $InstallDir = Resolve-Path $InstallDir -ErrorAction SilentlyContinue
    if (-not $InstallDir) {
        $InstallDir = $InstallDir
    }
}

$ZixirDir = Join-Path $InstallDir $RepoName

# Check for existing installation
$IsReinstall = $false
if (Test-Path $ZixirDir) {
    if (Test-Path (Join-Path $ZixirDir ".git")) {
        Write-Log "Existing Zixir installation found at $ZixirDir" "Warning"
        
        if (-not $Force) {
            $response = Read-Host "Reinstall will DELETE existing installation and start fresh. Continue? [y/N]"
            if ($response -notmatch '^[yY]') {
                Write-Log "Installation cancelled" "Info"
                exit 0
            }
        }
        $IsReinstall = $true
    } else {
        Write-Log "Directory $ZixirDir exists but is not a Zixir installation" "Warning"
        if (-not $Force) {
            $response = Read-Host "Remove existing directory and install? [y/N]"
            if ($response -notmatch '^[yY]') {
                Write-Log "Installation cancelled" "Info"
                exit 0
            }
        }
        $IsReinstall = $true
    }
}

# Save current location
$OriginalLocation = Get-Location

# Perform installation
try {
    Install-Zixir -TargetDir $ZixirDir -IsReinstall $IsReinstall
    
    # Optional CUDA
    Install-CUDA -ZixirDir $ZixirDir
    
    # Success message
    Write-Header "Installation Complete!"
    Write-Log "Location: $ZixirDir" "Success"
    Write-Log "Version: $Version" "Success"
    Write-Log "Next steps:" "Info"
    Write-Log "  1. cd '$ZixirDir'" "Info"
    Write-Log "  2. mix zixir.run examples/hello.zixir" "Info"
    Write-Log "  3. See README.md and SETUP_GUIDE.md for more" "Info"
    
} catch {
    Write-Log "Installation failed: $_" "Error"
    exit 1
} finally {
    # Return to original location
    Set-Location $OriginalLocation
}
