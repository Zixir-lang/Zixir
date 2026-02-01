#!/usr/bin/env sh
# Zixir one-shot installer — includes:
#   Quick start: git clone https://github.com/Zixir-lang/Zixir.git, cd Zixir, git checkout v5.2.0,
#                mix deps.get, mix zig.get, mix compile
#   Optional GPU: Metal (macOS), CUDA (Linux NVIDIA), ROCm (Linux AMD) via install-optional-deps.sh
# Usage: ./scripts/install-zixir.sh [install-dir]
#   install-dir: where to clone (default: current directory). Repo will be clone-dir/Zixir.
# Run from repo root to install into current dir, or from elsewhere: ./path/to/Zixir/scripts/install-zixir.sh /opt

set -e

REPO_URL="https://github.com/Zixir-lang/Zixir.git"
VERSION="v5.2.0"
INSTALL_DIR="${1:-.}"

echo "=============================================="
echo "Zixir installer — Quick start + GPU (Metal/CUDA/ROCm)"
echo "=============================================="
echo ""

# If we're already in repo root (mix.exs + .git), use current dir
if [ -f mix.exs ] && [ -d .git ]; then
  ZIXIR_DIR="$(pwd)"
  echo "Using repo at $ZIXIR_DIR"
  cd "$ZIXIR_DIR"
  git fetch origin tag "$VERSION" 2>/dev/null || git fetch origin
  git checkout "$VERSION"
# Clone or use existing
else
  ZIXIR_DIR="${INSTALL_DIR%/}/Zixir"
  if [ -d "$ZIXIR_DIR/.git" ]; then
    echo "Existing clone at $ZIXIR_DIR — updating and checking out $VERSION"
    cd "$ZIXIR_DIR"
    git fetch origin tag "$VERSION" 2>/dev/null || git fetch origin
    git checkout "$VERSION"
  else
    echo "Cloning Zixir into $ZIXIR_DIR ..."
    git clone "$REPO_URL" "$ZIXIR_DIR"
    cd "$ZIXIR_DIR"
    git checkout "$VERSION"
  fi
fi

echo ""
echo "--- mix deps.get ---"
mix deps.get

echo ""
echo "--- mix zig.get ---"
mix zig.get

echo ""
echo "--- mix compile ---"
mix compile

echo ""
echo "Quick start done. Verify: mix zixir.run examples/hello.zixir"
echo ""

# Optional GPU: Metal (macOS), CUDA (Linux/Windows NVIDIA), ROCm (Linux AMD)
printf "Install optional GPU deps (Metal on macOS, CUDA or ROCm on Linux)? [y/N] "
read -r ans
case "$ans" in
  [yY]*)
    cd "$ZIXIR_DIR"
    [ -x "./scripts/install-optional-deps.sh" ] || chmod +x ./scripts/install-optional-deps.sh
    ./scripts/install-optional-deps.sh
    ;;
  *)
    echo "Skipped. Run from repo root later: ./scripts/install-optional-deps.sh (Metal/CUDA/ROCm)"
    ;;
esac

echo ""
echo "Done. From $ZIXIR_DIR run: mix zixir.run examples/hello.zixir"
