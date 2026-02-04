# Zixir Setup Guide v1.0

A complete setup guide for the Zixir programming language with all implemented features.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
3. [Project Setup](#project-setup)
   - [Global / portable CLI (run from any directory)](#global--portable-cli-run-from-any-directory)
4. [Python Integration](#python-integration)
5. [GPU Computing](#gpu-computing)
6. [Standard Library](#standard-library)
7. [Building & Testing](#building--testing)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

| Software | Minimum Version | Recommended |
|----------|----------------|-------------|
| **Erlang/OTP** | 25.0+ | 26.x |
| **Elixir** | 1.14+ | 1.16.x |
| **Zig** | 0.15+ (or via `mix zig.get`) | Zigler downloads 0.15.x automatically |
| **Git** | 2.0+ | Latest |
| **Python** | 3.8+ (optional) | 3.11/3.12 for ML/specialist |

### Optional Software

| Software | Purpose | Platform |
|----------|---------|----------|
| **Beaver** (`{:beaver, "~> 0.4"}` in deps) | MLIR (Phase 4) optimizations | Unix only; not Windows |
| **CUDA Toolkit** | NVIDIA GPU | Linux/Windows |
| **ROCm** | AMD GPU | Linux |
| **Xcode Command Line Tools** | Metal GPU | macOS |
| **NumPy** | Python array support | All |

See [docs/MLIR_AND_PYTHON.md](docs/MLIR_AND_PYTHON.md) for how to enable optional MLIR.

---

## Installation

### Step 1: Install Erlang and Elixir

**Windows:**
- **Option A (Scoop):** `scoop install erlang elixir`
- **Option B (installers):** [Elixir install guide](https://elixir-lang.org/install.html#windows) — download the Windows installer, then add the install directory (e.g. `C:\Program Files\Elixir\bin`) to PATH.

**macOS (via Homebrew):**
```bash
brew install erlang elixir
```

**Ubuntu/Debian:**
```bash
wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb
sudo dpkg -i erlang-solutions_2.0_all.deb
sudo apt-get update
sudo apt-get install erlang elixir
```

### Step 2: Install Zig (optional if using Zigler)

Zigler will download Zig 0.15.x when you run `mix zig.get`. If you prefer a system Zig (e.g. for other tools), use 0.15+:

**Windows:**
```powershell
scoop install zig
# Or: download from https://ziglang.org/download/
```

**macOS:**
```bash
brew install zig
```

**Linux:**
```bash
# Example: Zig 0.15.x
wget https://ziglang.org/download/0.15.2/zig-linux-x86_64-0.15.2.tar.xz
tar -xf zig-linux-x86_64-0.15.2.tar.xz
sudo mv zig-linux-x86_64-0.15.2 /opt/zig
export PATH=/opt/zig:$PATH
```

### Step 3: Install Python (with development headers)

**Windows:**
```powershell
scoop install python
pip install numpy
```

**macOS:**
```bash
brew install python numpy
```

**Ubuntu/Debian:**
```bash
sudo apt-get install python3-dev python3-pip python3-numpy
```

### Step 4: Install Git

Ensure Git is installed and available in PATH.

---

## Project Setup

### Clone and Setup

**One-shot installer (Quick start + optional GPU):** Runs `git clone`, `cd Zixir`, `git checkout v5.3.0`, `mix deps.get`, `mix zig.get`, `mix compile`, then optionally installs platform GPU deps: **Metal** (macOS), **CUDA** (Windows/Linux NVIDIA), **ROCm** (Linux AMD).
- **Unix/macOS:** `./scripts/install-zixir.sh [install-dir]` — e.g. `./scripts/install-zixir.sh` (current dir) or `./scripts/install-zixir.sh /opt`
- **Windows:** `.\scripts\install-zixir.ps1 [install-dir]` — e.g. `.\scripts\install-zixir.ps1` or `.\scripts\install-zixir.ps1 C:\dev` (includes CUDA script)

**Manual steps:**

```bash
# Clone the repository
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir

# Install Elixir dependencies
mix deps.get

# Fetch Zig for Zigler (required for NIF compilation)
mix zig.get

# Compile the project
mix compile

# Run a simple example to verify installation
mix zixir.run examples/hello.zixir
```

**Windows:** You can also run `.\scripts\verify.ps1` from the repo root to run deps.get, zig.get, compile, and the hello example in one go.

**Optional (GPU):** To install platform-specific GPU dependencies (CUDA / ROCm / Metal) for ML or GPU offload, run from the repo root:
- **Quick check (prints instructions):** `./scripts/install-gpu-deps.sh` (Unix/macOS) or `.\scripts\install-gpu-deps.ps1` (Windows).
- **Full install (runs install steps):** `./scripts/install-optional-deps.sh` (Unix/macOS: Metal or Linux CUDA/ROCm) or `.\scripts\install-optional-deps.ps1 [-Install] [-OpenDownload]` (Windows: CUDA).
See [GPU Computing](#gpu-computing) below for manual setup.

### Using Zixir in Your Project

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:zixir, "~> 1.0"}
  ]
end
```

### Global / portable CLI (run from any directory)

For tools and integrations, you can install Zixir so it runs from **any terminal path**:

1. **Build the release** (from the Zixir repo root):
   ```bash
   mix release
   ```
   By default this creates a dev release. For a production release: `MIX_ENV=prod mix release`.

2. **Add the release `bin/` to your PATH:**
   - **Unix/macOS:** `_build/dev/rel/zixir/bin/` (default) or `_build/prod/rel/zixir/bin/` (after `MIX_ENV=prod mix release`).
   - **Windows:** Same folder; use `zixir_run.bat` for the portable runner.

3. **Run a `.zixir` file from any directory:**
   - **Unix/macOS:** `zixir_run.sh /path/to/script.zixir`
   - **Windows:** `zixir_run.bat C:\path\to\script.zixir`

   Paths can be absolute or relative to the current working directory. The scripts call `Zixir.CLI.run_file_from_argv()` and pass the path after `--`.

4. **Alternative (any OS):** Use the release `eval` command with argv (same as the scripts):
   ```bash
   bin/zixir eval "Zixir.CLI.run_file_from_argv()" -- /path/to/file.zixir
   ```

Once `bin/` is on PATH, you can run Zixir scripts from any folder (CI, scripts, other tools) without `cd`-ing into the Zixir project.

---

## Python Integration

### Quick Start

```elixir
# Initialize Python
Zixir.Python.init()
# => {:ok, "3.11"} or {:error, :not_available}

# Call Python functions
Zixir.Python.call("math", "sqrt", [16.0])
# => {:ok, 4.0}

# Check module availability
Zixir.Python.has_module?("numpy")
# => true

# Create NumPy arrays (fast with NIF)
{:ok, arr} = Zixir.Python.numpy_array([1.0, 2.0, 3.0])

# Execute Python code
Zixir.Python.exec("result = sum(range(10))")
# => {:ok, "45"}

# Cleanup
Zixir.Python.finalize()
```

### Configuration

In `config/config.exs`:

```elixir
config :zixir,
  python_mode: :auto    # :nif, :port, or :auto
```

- **`:nif`** - Force direct C API (fastest when NIF is built)
- **`:port`** - Use port-based (works without NIF)
- **`:auto`** - Auto-detect (default)

### Performance Modes

| Mode | Speed | Requirements |
|------|-------|--------------|
| NIF (default) | 100-1000x faster | Python dev headers, Zig |
| Port | Standard | Python only |

---

## GPU Computing

### Supported Backends

| Backend | Platform | Requirements |
|---------|----------|--------------|
| **CUDA** | Linux/Windows | NVIDIA GPU, CUDA Toolkit |
| **ROCm** | Linux | AMD GPU, ROCm |
| **Metal** | macOS | Apple Silicon or Intel Mac |

### Usage

```elixir
# Check available backends
Zixir.Compiler.GPU.available?()
# => true

# Compile for specific backend (returns kernel path and backend)
{:ok, kernel_path, backend} = Zixir.Compiler.GPU.compile(ast, backend: :cuda)
# backend is :cuda, :rocm, or :metal

# Execute with automatic data transfer (returns {:ok, result_data})
{:ok, result} = Zixir.Compiler.GPU.execute_kernel(kernel_path, data, backend: :cuda)

# Allocate GPU buffer
{:ok, buffer} = Zixir.Compiler.GPU.allocate_buffer(size, backend: :cuda)

# Get device info
Zixir.Compiler.GPU.device_info(0)
# => {:ok, %{name: "NVIDIA GeForce RTX 3080", ...}}
```

### CUDA Setup (NVIDIA)

```bash
# Install CUDA Toolkit (Ubuntu)
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1-all.deb
sudo dpkg -i cuda-keyring_1.1-1-all.deb
sudo apt-get update
sudo apt-get install cuda-toolkit-12-0
```

### CUDA Setup (Windows)

**Prerequisites:**

- NVIDIA GPU with compute capability 5.0+
- Windows 10/11 64-bit

**Installation:**

1. **Download CUDA Toolkit:**
   - Visit: https://developer.nvidia.com/cuda-downloads
   - Select: Windows → x86_64 → 10/11 → exe (local)
   - Download CUDA Toolkit 12.x (or latest)

2. **Run Installer:**
   - Double-click the downloaded `.exe`
   - Choose "Express Installation" (recommended)
   - Or "Custom Installation" to select specific components
   - Ensure "CUDA" → "Development" → "Compiler" is selected (for `nvcc`)

3. **Verify PATH:**

   The installer should add CUDA to your PATH automatically. Verify:

   ```powershell
   nvcc --version
   ```

   If not found, manually add to PATH:
   - `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0\bin`
   - `C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.0\libnvvp`

4. **Verify GPU Detection:**

   ```powershell
   nvidia-smi
   ```

**Quick install via package managers:**

- **Chocolatey:** `choco install cuda`
- **Winget:** `winget install Nvidia.CUDA`

**Post-installation:** Restart your terminal or IDE to pick up the new PATH variables.

**Note:** Zixir's GPU detection (`gpu.ex`) uses `nvcc --version` to detect CUDA. This works on Windows as long as `nvcc` is in your system PATH.

### ROCm Setup (AMD)

```bash
# Install ROCm (Ubuntu)
wget https://repo.radeon.com/rocm/rocm.gpg.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg.key
echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/5.4.3 ubuntu22.04 main' | sudo tee /etc/apt/sources.list.d/rocm.list
sudo apt update
sudo apt install rocm-dev
```

### Metal Setup (macOS)

```bash
# Install Xcode Command Line Tools
xcode-select --install
```

---

## Standard Library

### std/math

```elixir
Zixir.Modules.call("std/math", :sin, [0.5])        # => {:ok, 0.4794}
Zixir.Modules.call("std/math", :cos, [0.5])        # => {:ok, 0.8776}
Zixir.Modules.call("std/math", :sqrt, [16])        # => {:ok, 4.0}
Zixir.Modules.call("std/math", :log, [2.71828])    # => {:ok, 1.0}
Zixir.Modules.call("std/math", :pi, [])            # => {:ok, 3.14159}
```

### std/list

```elixir
Zixir.Modules.call("std/list", :map, [[1, 2, 3], fn x -> x * 2 end])
# => {:ok, [2, 4, 6]}

Zixir.Modules.call("std/list", :filter, [[1, 2, 3, 4], fn x -> x > 2 end])
# => {:ok, [3, 4]}

Zixir.Modules.call("std/list", :reduce, [[1, 2, 3, 4], 0, fn a, b -> a + b end])
# => {:ok, 10}

Zixir.Modules.call("std/list", :sort, [[3, 1, 4, 1, 5, 9, 2, 6]])
# => {:ok, [1, 1, 2, 3, 4, 5, 6, 9]}
```

### std/string

```elixir
Zixir.Modules.call("std/string", :length, ["hello"])
# => {:ok, 5}

Zixir.Modules.call("std/string", :split, ["hello world", " "])
# => {:ok, ["hello", "world"]}

Zixir.Modules.call("std/string", :upper, ["hello"])
# => {:ok, "HELLO"}
```

### std/io

```elixir
Zixir.Modules.call("std/io", :print, ["Hello, World!"])
Zixir.Modules.call("std/io", :println, ["Line with newline"])
Zixir.Modules.call("std/io", :read_line, [])
```

### std/json

```elixir
Zixir.Modules.call("std/json", :encode, [%{name: "John", age: 30}])
# => {:ok, "{\"name\":\"John\",\"age\":30}"}

Zixir.Modules.call("std/json", :decode, ["{\"name\":\"John\"}"])
# => {:ok, %{name: "John"}}
```

### std/random

```elixir
Zixir.Modules.call("std/random", :uniform, [1, 100])
# => {:ok, random integer between 1-100}

Zixir.Modules.call("std/random", :shuffle, [[1, 2, 3, 4, 5]])
# => {:ok, shuffled list}
```

### std/stat

```elixir
Zixir.Modules.call("std/stat", :mean, [[1, 2, 3, 4, 5]])
# => {:ok, 3.0}

Zixir.Modules.call("std/stat", :median, [[1, 2, 3, 4, 5]])
# => {:ok, 3.0}

Zixir.Modules.call("std/stat", :std_dev, [[1, 2, 3, 4, 5]])
# => {:ok, 1.4142}
```

### std/time

```elixir
Zixir.Modules.call("std/time", :now, [])
# => {:ok, 1706745600000}

Zixir.Modules.call("std/time", :sleep, [1000])
# Sleeps for 1 second
```

---

## Building & Testing

### Build Commands

```bash
# Compile with all warnings
mix compile

# Clean and recompile
mix clean && mix compile

# Build release
mix release

# Build documentation
mix docs
```

### Test Commands

```bash
# Run all tests
mix test

# Run specific test file
mix test test/zixir/compiler/parser_test.exs

# Run tests with coverage
mix coveralls

# Run tests in parallel
mix test --cover
```

### Benchmarking

```bash
# Run benchmarks
mix bench
```

---

## Troubleshooting

### Common Issues

#### Python Not Found

```error
{:error, :not_available}
```

**Solution:** Ensure Python is installed and in PATH:
```bash
python3 --version
```

#### NumPy Not Available

```error
{:error, :numpy_not_available}
```

**Solution:** Install NumPy:
```bash
pip install numpy
```

#### CUDA Not Available

```error
{:error, :cuda_not_available}
```

**Solution:** 
1. Verify NVIDIA GPU: `nvidia-smi`
2. Install CUDA Toolkit
3. Ensure `nvcc` is in PATH

#### Metal Not Available (macOS)

```error
{:error, :metal_not_available}
```

**Solution:** Install Xcode Command Line Tools:
```bash
xcode-select --install
```

#### Zigler Build Errors

```error
could not find zig executable
```

**Solution:** 
1. Verify Zig installation: `zig version`
2. Add Zig to PATH
3. Clean build: `mix deps.clean --build zigler && mix compile`

### Getting Help

- **GitHub Issues:** Report bugs and feature requests
- **Documentation:** See `docs/` directory
- **REPL:** Use `iex -S mix` for interactive testing

---

## Project Structure

```
Zixir/
├── lib/                    # Elixir source
│   ├── zixir/             # Main application
│   ├── compiler/           # Compiler components
│   └── mix/                # Mix tasks
├── priv/                   # Native code
│   ├── python/             # Port bridge (port_bridge.py)
│   ├── python_nif.zig       # Python NIF (Zig)
│   └── zig/                 # Zig runtime
├── rel/overlays/bin/       # Release scripts (zixir_run.sh, zixir_run.bat)
├── test/                   # Test files
├── docs/                   # Documentation
├── mix.exs                 # Mix project file
└── README.md               # Project README
```

---

## Next Steps

1. **Read the README** for language basics
2. **Try the REPL:** `iex -S mix`
3. **Build a sample project** using the standard library
4. **Explore GPU computing** with CUDA/Metal
5. **Integrate Python libraries** for data science

---

**Happy Coding with Zixir!**
