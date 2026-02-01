# Zixir v5.1.0 — Hotfix: Shared utils, dedup, config, engine retry fix

Hotfix release: shared utilities module, elimination of code duplication, centralized configuration, and a critical engine retry bug fix.

---

## 1. Created Shared Utilities Module ✅

- **New file:** `lib/zixir/utils.ex`
- **Functions:** `format_bytes/1`, `generate_id/1`, `now_ms/0`, `iso8601_now/0`
- Centralized helpers used across the codebase

---

## 2. Eliminated Code Duplication ✅

- Removed **8 duplicate function clauses** from 2 files
- Updated **5 modules** to use centralized ID generation
- **Files affected:** `cache.ex`, `sandbox.ex`, `workflow.ex`, `quality.ex`, `experiment.ex`, `checkpoint.ex`

---

## 3. Centralized Configuration ✅

- **New config values** in `config/config.exs`:
  - `python_timeout: 30_000`
  - `workflow_step_timeout: 30_000`
- **Files updated:** `worker.ex`, `pool.ex`, `workflow.ex`
- All now read from config instead of hardcoded values

---

## 4. Fixed Critical Bug ✅

- **File:** `lib/zixir/engine.ex`
- **Problem:** Infinite loop risk in rescue block
- **Solution:** Added retry tracking to prevent endless retries

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist calls

## Quick start

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v5.1.0
mix deps.get
mix zig.get
mix compile
mix test
```

## License

**Apache-2.0** — see [LICENSE](LICENSE).
