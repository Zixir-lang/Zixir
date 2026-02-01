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

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.2.0
mix deps.get
mix zig.get
mix compile
```

**Optional (GPU):** Install platform-specific GPU deps from repo root:
- **Unix/macOS:** `./scripts/install-gpu-deps.sh` (Metal on macOS; CUDA or ROCm on Linux)
- **Windows:** `.\scripts\install-gpu-deps.ps1` (CUDA)

## License

**Apache-2.0** — see [LICENSE](LICENSE).
