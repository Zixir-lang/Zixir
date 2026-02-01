#!/usr/bin/env sh
# Full install of optional GPU dependencies for Zixir: Metal (macOS), CUDA (Linux), ROCm (Linux).
# Run from repo root: ./scripts/install-optional-deps.sh [cuda|rocm|metal|auto]
# With no argument, auto-detects platform and offers CUDA or ROCm on Linux.
# See SETUP_GUIDE.md for manual options.

set -e

# Detect OS
OS="$(uname -s)"
# Optional: detect Ubuntu version for repo URLs
detect_ubuntu_codename() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "${VERSION_CODENAME:-unknown}"
  else
    echo "unknown"
  fi
}

echo "=============================================="
echo "Zixir — Full install of optional GPU deps"
echo "=============================================="
echo ""

case "$OS" in
  Darwin)
    echo "Platform: macOS (Metal)"
    if command -v xcrun >/dev/null 2>&1 && xcrun -f metal >/dev/null 2>&1; then
      echo "Metal (Xcode Command Line Tools) already available."
      exit 0
    fi
    echo "Installing Xcode Command Line Tools (required for Metal)..."
    xcode-select --install
    echo "Complete the installer dialog. Then re-run: mix run -e \"IO.inspect(Zixir.Compiler.GPU.available?())\""
    ;;
  Linux)
    echo "Platform: Linux (CUDA or ROCm)"
    if command -v nvcc >/dev/null 2>&1; then
      echo "CUDA (nvcc) already in PATH."
      nvcc --version 2>/dev/null || true
      exit 0
    fi
    if command -v hipcc >/dev/null 2>&1; then
      echo "ROCm (hipcc) already in PATH."
      exit 0
    fi

    # Choose backend: first arg or prompt
    BACKEND="${1:-}"
    if [ -z "$BACKEND" ]; then
      echo "Which GPU stack do you want to install?"
      echo "  1) CUDA (NVIDIA)"
      echo "  2) ROCm (AMD)"
      echo "  3) Skip"
      printf "Choice [1-3]: "
      read -r choice
      case "$choice" in
        2) BACKEND="rocm" ;;
        3) echo "Skipped. See SETUP_GUIDE.md for manual install."; exit 0 ;;
        *) BACKEND="cuda" ;;
      esac
    fi

    # Require apt (Ubuntu/Debian) for automated install
    if ! command -v apt-get >/dev/null 2>&1; then
      echo "This script uses apt (Ubuntu/Debian). For other distros see SETUP_GUIDE.md."
      echo ""
      echo "CUDA (NVIDIA) — example: https://developer.nvidia.com/cuda-downloads"
      echo "ROCm (AMD)   — example: https://rocm.docs.amd.com/project/install.html"
      exit 1
    fi

    CODENAME="$(detect_ubuntu_codename)"
    echo "Detected distro codename: $CODENAME"
    echo "Using Ubuntu 22.04 repo paths; if your distro differs, see SETUP_GUIDE.md."
    echo ""

    case "$BACKEND" in
      cuda|nvidia)
        echo "--- Installing CUDA Toolkit (NVIDIA) ---"
        CUDA_REPO="ubuntu2204"
        [ "$CODENAME" = "jammy" ] || CUDA_REPO="ubuntu2204"
        cd "$(mktemp -d)"
        wget -q "https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_REPO}/x86_64/cuda-keyring_1.1-1-all.deb" || {
          echo "Fallback: try ubuntu2204 repo."
          wget -q "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1-all.deb"
        }
        sudo dpkg -i cuda-keyring_1.1-1-all.deb
        sudo apt-get update
        sudo apt-get install -y cuda-toolkit-12-0
        echo "CUDA installed. You may need to add to PATH: /usr/local/cuda/bin"
        echo "Verify: nvcc --version"
        ;;
      rocm|amd)
        echo "--- Installing ROCm (AMD) ---"
        wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg.key
        echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/5.4.3 ubuntu22.04 main" | sudo tee /etc/apt/sources.list.d/rocm.list
        sudo apt update
        sudo apt install -y rocm-dev
        echo "ROCm installed. Verify: hipcc --version"
        ;;
      *)
        echo "Unknown backend: $BACKEND. Use cuda or rocm."
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported OS: $OS. See SETUP_GUIDE.md for manual setup."
    exit 1
    ;;
esac

echo ""
echo "Done. Verify Zixir GPU: mix run -e \"IO.inspect(Zixir.Compiler.GPU.available?())\""
