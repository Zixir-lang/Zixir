# Zixir v6.1.0 — Bug fixes

Patch release with stability and correctness fixes across VectorDB, observability, checkpoints, and tests.

---

## Bug fixes

1. **Memory storage not supported** — Added complete `:memory` backend so in-memory VectorDB works without external services.

2. **JSON encoding failures** — Replaced JSON encoding with binary format where appropriate to avoid serialization failures on complex data.

3. **Observability crashes** — Added defensive checks in observability code to prevent crashes under edge conditions.

4. **Ecto.UUID dependency** — Removed; uses native Elixir for UUID/ID generation (no Ecto dependency).

5. **Test compilation errors** — Fixed pattern matching in tests so the test suite compiles and runs cleanly.

6. **Checkpoint ordering** — Uses checkpoint ID for reliable sorting so workflow checkpoints are ordered correctly.

7. **State loading** — Properly extracts state from checkpoint structure when resuming workflows.

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist and VectorDB Python backends

## Quick start

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v6.1.0
mix deps.get
mix zig.get
mix compile
mix test
```

## License

**Apache-2.0** — see [LICENSE](LICENSE).
