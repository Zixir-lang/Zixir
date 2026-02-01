# Zixir one-shot installer — includes:
#   Quick start: git clone https://github.com/Zixir-lang/Zixir.git, cd Zixir, git checkout v5.2.0,
#                mix deps.get, mix zig.get, mix compile
#   Optional GPU: CUDA (Windows) via install-optional-deps.ps1 -Install
# Usage: .\scripts\install-zixir.ps1 [install-dir]
#   install-dir: where to clone (default: current directory). Repo will be install-dir\Zixir.
# Run from repo root to install into current dir, or from elsewhere: .\path\to\Zixir\scripts\install-zixir.ps1 C:\dev

$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/Zixir-lang/Zixir.git"
$Version = "v5.2.0"
$InstallDir = if ($args[0]) { $args[0] } else { Get-Location }
$ZixirDir = Join-Path $InstallDir "Zixir"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Zixir installer — Quick start + GPU (CUDA)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# If we're already in repo root (mix.exs + .git), use current dir
if ((Test-Path "mix.exs") -and (Test-Path ".git")) {
    $ZixirDir = (Get-Location).Path
    Write-Host "Using repo at $ZixirDir"
    Set-Location $ZixirDir
    git fetch origin tag $Version 2>$null; if (-not $?) { git fetch origin }
    git checkout $Version
} elseif (Test-Path (Join-Path $ZixirDir ".git")) {
    Write-Host "Existing clone at $ZixirDir — updating and checking out $Version"
    Set-Location $ZixirDir
    git fetch origin tag $Version 2>$null; if (-not $?) { git fetch origin }
    git checkout $Version
} else {
    Write-Host "Cloning Zixir into $ZixirDir ..."
    git clone $RepoUrl $ZixirDir
    Set-Location $ZixirDir
    git checkout $Version
}

Write-Host ""
Write-Host "--- mix deps.get ---" -ForegroundColor Gray
mix deps.get

Write-Host ""
Write-Host "--- mix zig.get ---" -ForegroundColor Gray
mix zig.get

Write-Host ""
Write-Host "--- mix compile ---" -ForegroundColor Gray
mix compile

Write-Host ""
Write-Host "Quick start done. Verify: mix zixir.run examples/hello.zixir" -ForegroundColor Green
Write-Host ""

$ans = Read-Host "Install optional GPU deps (CUDA)? [y/N]"
if ($ans -match '^[yY]') {
    Set-Location $ZixirDir
    & (Join-Path $ZixirDir "scripts\install-optional-deps.ps1") -Install
} else {
    Write-Host "Skipped. Run from repo root later: .\scripts\install-optional-deps.ps1 -Install (CUDA)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Done. From $ZixirDir run: mix zixir.run examples/hello.zixir" -ForegroundColor Green
