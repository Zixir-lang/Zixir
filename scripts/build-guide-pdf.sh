#!/usr/bin/env bash
# Build Zixir Language complete guide PDF from Markdown.
# Requires: pandoc (https://pandoc.org). For PDF: texlive (Linux) or MacTeX (macOS).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INPUT="$REPO_ROOT/docs/Zixir Language complete guide.md"
OUTPUT="$REPO_ROOT/docs/Zixir-Language-complete-guide.pdf"

if [ ! -f "$INPUT" ]; then
  echo "Error: Guide not found at $INPUT"
  exit 1
fi

if ! command -v pandoc &>/dev/null; then
  echo "Error: pandoc is required. Install from https://pandoc.org"
  exit 1
fi

echo "Building PDF from $INPUT ..."
pandoc "$INPUT" \
  -o "$OUTPUT" \
  --pdf-engine=xelatex \
  -V geometry:margin=1in \
  -V fontsize=11pt \
  -V documentclass=article \
  --toc \
  --toc-depth=2 \
  -f markdown+smart

echo "Done: $OUTPUT"
ls -la "$OUTPUT"
