# Zixir v5.3.0 — Minor Release ⭐ RECOMMENDED

Minor release with installer improvements and enhancements. Follows semantic versioning (new features = minor version bump). No breaking changes.

---

## New Features & Improvements

### Installer improvements
- **Windows (install-zixir.ps1)** — Production installer: structured logging, `-InstallDir` / `-Force` / `-SkipCUDA`, cleanup flow, prerequisite checks, clearer CUDA prompt
- **Unix (install-zixir.sh)** — Version aligned to v5.3.0; one-shot quick start + optional Metal/CUDA/ROCm
- **Bootstrap installers** — `install-zixir-bootstrap.sh` and `install-zixir-bootstrap.ps1` updated for v5.3.0 (curl/iwr one-liners)

### Other enhancements
- Version bump to **5.3.0** across mix.exs and all installer scripts
- Documentation and quick start paths updated for v5.3.0

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist calls
- **GPU** *(optional)* — CUDA (NVIDIA, Windows/Linux), ROCm (AMD, Linux), or Metal (macOS). See [SETUP_GUIDE.md](SETUP_GUIDE.md#gpu-computing).

## Quick start

**One-shot installer (includes Quick start + optional GPU: Metal / CUDA / ROCm):**

```bash
# Unix/macOS — clone, checkout v5.3.0, mix deps.get, mix zig.get, mix compile, then optional Metal (macOS) or CUDA/ROCm (Linux)
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.3.0
./scripts/install-zixir.sh
```

```powershell
# Windows — clone, checkout v5.3.0, mix deps.get, mix zig.get, mix compile, then optional CUDA
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.3.0
.\scripts\install-zixir.ps1
```

The installer runs `mix deps.get`, `mix zig.get`, `mix compile`, then prompts to install platform GPU deps: **Metal** (macOS), **CUDA** (Windows/Linux NVIDIA), **ROCm** (Linux AMD).

**Manual (no installer script):**

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.3.0
mix deps.get
mix zig.get
mix compile
```

**Optional (GPU) after manual setup:** From repo root: `./scripts/install-optional-deps.sh` (Unix: Metal/CUDA/ROCm) or `.\scripts\install-optional-deps.ps1 -Install` (Windows: CUDA).

## License

**Apache-2.0** — see [LICENSE](LICENSE).
