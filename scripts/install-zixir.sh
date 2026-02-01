#!/usr/bin/env sh
# Zixir one-shot installer — includes:
#   Quick start: git clone https://github.com/Zixir-lang/Zixir.git, cd Zixir, git checkout v5.2.0,
#                mix deps.get, mix zig.get, mix compile
#   Optional GPU: Metal (macOS), CUDA (Linux NVIDIA), ROCm (Linux AMD) via install-optional-deps.sh
# Usage: ./scripts/install-zixir.sh [install-dir] [--force]
#   install-dir: where to clone (default: current directory). Repo will be clone-dir/Zixir.
#   --force: Replace existing installation if present
# Run from repo root to install into current dir, or from elsewhere: ./path/to/Zixir/scripts/install-zixir.sh /opt

set -e

REPO_URL="https://github.com/Zixir-lang/Zixir.git"
VERSION="v5.2.0"
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

echo "=============================================="
echo "Zixir installer — Quick start + GPU (Metal/CUDA/ROCm)"
echo "Version: $VERSION"
echo "=============================================="
echo ""

# Check if we're already in repo root
if [ -f mix.exs ] && [ -d .git ]; then
  ZIXIR_DIR="$(pwd)"
  echo "Using current repo at $ZIXIR_DIR"
  cd "$ZIXIR_DIR"
  
  # Fetch all tags
  echo "Fetching latest tags..."
  git fetch origin --tags 2>/dev/null || git fetch origin
  
  git checkout "$VERSION" || {
    echo "ERROR: Failed to checkout $VERSION"
    exit 1
  }
# Check for existing installation
else
  ZIXIR_DIR="${INSTALL_DIR%/}/Zixir"
  
  if [ -d "$ZIXIR_DIR" ]; then
    if [ -d "$ZIXIR_DIR/.git" ]; then
      # Existing git repo - upgrade
      echo "Existing Zixir installation found at $ZIXIR_DIR"
      
      if [ $FORCE -eq 0 ]; then
        printf "Upgrade existing installation to $VERSION? [Y/n] "
        read -r ans
        case "$ans" in
          [nN]*)
            echo "Installation cancelled. Use --force flag to skip this prompt."
            exit 0
            ;;
        esac
      fi
      
      echo "Upgrading existing installation to $VERSION..."
      cd "$ZIXIR_DIR"
      
      # Stash any local changes
      git stash 2>/dev/null || true
      
      # Fetch all tags
      echo "Fetching latest tags..."
      git fetch origin --tags 2>/dev/null || git fetch origin
      
      git checkout "$VERSION" || {
        echo "ERROR: Failed to checkout $VERSION. You may need to resolve conflicts manually."
        exit 1
      }
    else
      # Directory exists but is not a git repo
      echo "Directory $ZIXIR_DIR exists but is not a Zixir installation"
      
      if [ $FORCE -eq 0 ]; then
        printf "Remove existing directory and install fresh? [y/N] "
        read -r ans
        case "$ans" in
          [yY]*)
            ;;
          *)
            echo "Installation cancelled. Use --force flag to skip this prompt."
            exit 0
            ;;
        esac
      fi
      
      echo "Removing existing directory..."
      rm -rf "$ZIXIR_DIR"
      
      echo "Cloning Zixir $VERSION into $ZIXIR_DIR..."
      git clone "$REPO_URL" "$ZIXIR_DIR"
      cd "$ZIXIR_DIR"
      git checkout "$VERSION"
    fi
  else
    # Fresh install
    echo "Cloning Zixir $VERSION into $ZIXIR_DIR..."
    git clone "$REPO_URL" "$ZIXIR_DIR"
    cd "$ZIXIR_DIR"
    git checkout "$VERSION"
  fi
fi

echo ""
echo "--- mix deps.get ---"
mix deps.get || {
  echo "ERROR: mix deps.get failed"
  exit 1
}

echo ""
echo "--- mix zig.get ---"
mix zig.get || {
  echo "ERROR: mix zig.get failed"
  exit 1
}

echo ""
echo "--- mix compile ---"
mix compile || {
  echo "ERROR: mix compile failed"
  exit 1
}

echo ""
echo "✓ Quick start complete!"
echo "Verify installation: mix zixir.run examples/hello.zixir"
echo ""

# Optional GPU installation
echo "Optional: Install GPU dependencies (Metal/CUDA/ROCm) for GPU acceleration."
printf "Install GPU support now? [y/N] "
read -r ans
case "$ans" in
  [yY]*)
    if [ -x "./scripts/install-optional-deps.sh" ]; then
      ./scripts/install-optional-deps.sh
    else
      echo "GPU installer not found. You can install GPU dependencies manually later."
    fi
    ;;
  *)
    echo "Skipped. Install later with: ./scripts/install-optional-deps.sh"
    ;;
esac

echo ""
echo "=============================================="
echo "Installation complete!"
echo "Location: $ZIXIR_DIR"
echo "Version: $VERSION"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. cd $ZIXIR_DIR"
echo "  2. mix zixir.run examples/hello.zixir"
echo "  3. See README.md and SETUP_GUIDE.md for more"
