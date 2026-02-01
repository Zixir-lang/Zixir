# Zixir v5.2.0 — Hotfixes: type system, Python bridge, specs, errors

Patch release with bug fixes, documentation improvements, and type-safety enhancements. No breaking changes.

---

## Bug Fixes

- **Type system** — Fixed pattern matching bugs in TypeSystem module (3 issues)
- **Python bridge** — Added missing Python bridge functions: `math/2`, `numpy/2`, `stats/0`, `healthy?/0`, `parallel/2`

---

## Improvements

- **Type safety** — Added comprehensive `@spec` annotations (85+ functions)
- **Errors** — Added standardized error module (`Zixir.Errors`)
- **Compiler** — Removed compiler warning suppressions (5 files)
- **Documentation** — Improved code documentation across 20 files

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist calls
- **GPU** *(optional)* — CUDA (NVIDIA, Windows/Linux), ROCm (AMD, Linux), or Metal (macOS). See [SETUP_GUIDE.md](SETUP_GUIDE.md#gpu-computing).

## Quick start

**One-shot installer (includes Quick start + optional GPU: Metal / CUDA / ROCm):**

```bash
# Unix/macOS — clone, checkout v5.2.0, mix deps.get, mix zig.get, mix compile, then optional Metal (macOS) or CUDA/ROCm (Linux)
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.2.0
./scripts/install-zixir.sh
```

```powershell
# Windows — clone, checkout v5.2.0, mix deps.get, mix zig.get, mix compile, then optional CUDA
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.2.0
.\scripts\install-zixir.ps1
```

The installer runs `mix deps.get`, `mix zig.get`, `mix compile`, then prompts to install platform GPU deps: **Metal** (macOS), **CUDA** (Windows/Linux NVIDIA), **ROCm** (Linux AMD).

**Manual (no installer script):**

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.2.0
mix deps.get
mix zig.get
mix compile
```

**Optional (GPU) after manual setup:** From repo root: `./scripts/install-optional-deps.sh` (Unix: Metal/CUDA/ROCm) or `.\scripts\install-optional-deps.ps1 -Install` (Windows: CUDA).

## License

**Apache-2.0** — see [LICENSE](LICENSE).
