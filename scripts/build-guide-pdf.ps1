# Build Zixir Language complete guide PDF from Markdown.
# Requires: pandoc (https://pandoc.org). For PDF on Windows: install MiKTeX or TeX Live.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$InputPath = Join-Path $RepoRoot "docs\Zixir Language complete guide.md"
$OutputPath = Join-Path $RepoRoot "docs\Zixir Language complete guide.pdf"

if (-not (Test-Path $InputPath)) {
    Write-Error "Guide not found at $InputPath"
    exit 1
}

$pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
if (-not $pandoc) {
    Write-Error "pandoc is required. Install from https://pandoc.org"
    exit 1
}

Write-Host "Building PDF from $InputPath ..."
& pandoc $InputPath `
    -o $OutputPath `
    --pdf-engine=xelatex `
    -V geometry:margin=1in `
    -V fontsize=11pt `
    -V documentclass=article `
    --toc `
    --toc-depth=2 `
    -f markdown+smart

Write-Host "Done: $OutputPath"
Get-Item $OutputPath | Format-List Name, Length
