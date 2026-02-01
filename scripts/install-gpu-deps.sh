#!/usr/bin/env sh
# Optional: install platform-specific GPU dependencies for Zixir (CUDA / ROCm / Metal).
# Run from repo root: ./scripts/install-gpu-deps.sh
# See SETUP_GUIDE.md for full GPU setup.

set -e

echo "Zixir GPU dependencies — checking platform..."

case "$(uname -s)" in
  Darwin)
    echo "Platform: macOS (Metal)"
    if command -v xcrun >/dev/null 2>&1 && xcrun -f metal >/dev/null 2>&1; then
      echo "Metal SDK (Xcode Command Line Tools) already available."
    else
      echo "Installing Xcode Command Line Tools (required for Metal)..."
      xcode-select --install
      echo "Complete the installer, then re-run this script if needed."
    fi
    ;;
  Linux)
    echo "Platform: Linux (CUDA or ROCm)"
    if command -v nvcc >/dev/null 2>&1; then
      echo "CUDA (nvcc) already in PATH."
    elif command -v hipcc >/dev/null 2>&1; then
      echo "ROCm (hipcc) already in PATH."
    else
      echo ""
      echo "Choose one:"
      echo "  NVIDIA GPU (CUDA) — Ubuntu/Debian:"
      echo "    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1-all.deb"
      echo "    sudo dpkg -i cuda-keyring_1.1-1-all.deb"
      echo "    sudo apt-get update && sudo apt-get install cuda-toolkit-12-0"
      echo ""
      echo "  AMD GPU (ROCm) — Ubuntu:"
      echo "    wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg.key"
      echo "    echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/5.4.3 ubuntu22.04 main' | sudo tee /etc/apt/sources.list.d/rocm.list"
      echo "    sudo apt update && sudo apt install rocm-dev"
      echo ""
      echo "See SETUP_GUIDE.md for other distros and details."
    fi
    ;;
  *)
    echo "Platform not supported for GPU scripts. See SETUP_GUIDE.md for manual setup."
    exit 1
    ;;
esac

echo "Done. Verify with: mix run -e \"IO.inspect(Zixir.Compiler.GPU.available?())\""
