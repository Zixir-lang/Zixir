# Zixir verification script (Windows). Run from repo root.
# Requires: Elixir (mix) and Zig on PATH.

$ErrorActionPreference = "Stop"
$repoRoot = if ($PSScriptRoot) { Join-Path $PSScriptRoot ".." } else { ".." }
Set-Location $repoRoot

# Find mix (Elixir): check PATH, then common Windows install locations
$mixPath = $null
$mix = Get-Command mix -ErrorAction SilentlyContinue
if ($mix) {
    $mixPath = $mix.Source
} else {
    $candidates = @(
        "C:\Program Files\Elixir\bin",
        "C:\Program Files (x86)\Elixir\bin",
        (Join-Path $env:LOCALAPPDATA "Programs\Elixir\bin"),
        (Join-Path $env:USERPROFILE "Programs\Elixir\bin")
    )
    foreach ($dir in $candidates) {
        if (Test-Path (Join-Path $dir "mix.bat")) {
            $env:PATH = "$dir;$env:PATH"
            $mixPath = Join-Path $dir "mix.bat"
            Write-Host "Using Elixir at: $dir" -ForegroundColor Cyan
            break
        }
    }
}
if (-not $mixPath) {
    Write-Host "ERROR: 'mix' (Elixir) is not on your PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "You installed Elixir (elixir-otp-28.exe). Do one of the following:"
    Write-Host "  1. Close this terminal, open a NEW terminal, then run this script again."
    Write-Host "  2. Or add Elixir to PATH: find where Elixir installed (e.g. C:\Program Files\Elixir\bin)"
    Write-Host "     and add that folder to your user PATH in Environment Variables."
    Write-Host "  3. Run the commands manually from a shell where mix works:"
    Write-Host "     mix deps.get"
    Write-Host "     mix zig.get"
    Write-Host "     mix compile"
    Write-Host "     mix test"
    Write-Host "     mix zixir.run examples/hello.zixir"
    Write-Host ""
    exit 1
}

# Elixir needs Erlang (erl.exe). If not on PATH, try common Windows Erlang install locations.
$erl = Get-Command erl -ErrorAction SilentlyContinue
if (-not $erl) {
    $erlangCandidates = @(
        "C:\Program Files\Erlang OTP\bin",
        "C:\Program Files (x86)\Erlang OTP\bin"
    )
    # Elixir install dir (if we found it): look for erl-* sibling folders
    if ($mixPath) {
        $elixirParent = Split-Path (Split-Path $mixPath -Parent) -Parent
        if (Test-Path $elixirParent) {
            Get-ChildItem $elixirParent -Directory -Filter "erl*" -ErrorAction SilentlyContinue | ForEach-Object {
                $bin = Join-Path $_.FullName "bin"
                if (Test-Path (Join-Path $bin "erl.exe")) { $erlangCandidates = @($bin) + $erlangCandidates }
            }
        }
    }
    # Scan Program Files for erl-* versioned folders
    foreach ($pf in @("C:\Program Files", "C:\Program Files (x86)")) {
        if (Test-Path $pf) {
            Get-ChildItem $pf -Directory -Filter "erl*" -ErrorAction SilentlyContinue | ForEach-Object {
                $bin = Join-Path $_.FullName "bin"
                if (Test-Path (Join-Path $bin "erl.exe")) { $erlangCandidates += $bin }
            }
        }
    }
    foreach ($dir in $erlangCandidates) {
        if (Test-Path (Join-Path $dir "erl.exe")) {
            $env:PATH = "$dir;$env:PATH"
            Write-Host "Using Erlang at: $dir" -ForegroundColor Cyan
            break
        }
    }
}
# Re-check: mix will call erl, so we need it now
if (-not (Get-Command erl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: 'erl' (Erlang) is not on your PATH. Elixir needs Erlang to run." -ForegroundColor Red
    Write-Host ""
    Write-Host "Add Erlang's bin folder to your PATH (e.g. C:\Program Files\Erlang OTP\bin"
    Write-Host "or the folder where you ran otp_win64_28.3.1.exe)." -ForegroundColor Red
    exit 1
}

Write-Host "Zixir verification: deps.get, zig.get, compile, run example"
mix deps.get
if ($LASTEXITCODE -ne 0) { exit 1 }
mix zig.get
if ($LASTEXITCODE -ne 0) { exit 1 }
# Prefer Zigler's Zig 0.15.x over system Zig 0.16 (Zigler 0.15 needs Zig 0.15)
$ziglerCache = Join-Path $env:LOCALAPPDATA "zigler\Cache"
if (Test-Path $ziglerCache) {
    $zigDir = Get-ChildItem $ziglerCache -Directory -Filter "zig-*" -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName "zig.exe") } | Select-Object -First 1
    if ($zigDir) {
        $env:PATH = "$($zigDir.FullName);$env:PATH"
        Write-Host "Using Zig at: $($zigDir.FullName)" -ForegroundColor Cyan
    }
}
mix compile
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Running examples/hello.zixir..."
mix zixir.run examples/hello.zixir
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Verification complete."
