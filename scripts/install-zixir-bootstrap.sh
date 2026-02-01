#!/bin/bash
# Zixir Bootstrap Installer for Unix/Linux/macOS
# This script can be run from ANY location - it downloads and runs the full installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Zixir-lang/Zixir/v5.3.0/scripts/install-zixir-bootstrap.sh | bash
# Or save and run: ./install-zixir-bootstrap.sh [install-dir] [--force]

set -e

REPO_URL="https://github.com/Zixir-lang/Zixir.git"
VERSION="v5.3.0"
FORCE=0

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --force|-f)
      FORCE=1
      shift
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Usage: $0 [install-dir] [--force]"
      exit 1
      ;;
    *)
      INSTALL_DIR="$1"
      shift
      ;;
  esac
done

# Default install directory
INSTALL_DIR="${INSTALL_DIR:-.}"
ZIXIR_DIR="${INSTALL_DIR%/}/Zixir"

echo "=============================================="
echo "Zixir Bootstrap Installer"
echo "Version: $VERSION"
echo "=============================================="
echo ""

# Check for existing installation
if [ -d "$ZIXIR_DIR" ]; then
  echo "Existing Zixir directory found at $ZIXIR_DIR"
  
  if [ $FORCE -eq 0 ]; then
    printf "Remove and reinstall fresh? [Y/n] "
    read -r ans
    case "$ans" in
      [nN]*)
        echo "Installation cancelled. Use --force flag to skip this prompt."
        exit 0
        ;;
    esac
  fi
  
  echo "Removing existing directory..."
  rm -rf "$ZIXIR_DIR"
fi

# Clone fresh
echo "Cloning Zixir $VERSION..."
git clone "$REPO_URL" "$ZIXIR_DIR" || {
  echo "ERROR: Failed to clone repository"
  exit 1
}

cd "$ZIXIR_DIR"

# Checkout version
git checkout "$VERSION" || {
  echo "ERROR: Failed to checkout $VERSION"
  exit 1
}

# Check if the full installer exists
if [ -x "./scripts/install-zixir.sh" ]; then
  echo "Running full installer..."
  ./scripts/install-zixir.sh "$INSTALL_DIR"
else
  # Fallback: run the install steps directly
  echo "Running installation steps..."
  
  echo ""
  echo "--- mix deps.get ---"
  mix deps.get || exit 1
  
  echo ""
  echo "--- mix zig.get ---"
  mix zig.get || exit 1
  
  echo ""
  echo "--- mix compile ---"
  mix compile || exit 1
  
  echo ""
  echo "✓ Installation complete!"
  echo "Location: $ZIXIR_DIR"
  echo "Verify: mix zixir.run examples/hello.zixir"
fi
