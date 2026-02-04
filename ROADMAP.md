# Zixir public roadmap

High-level direction for the project. Priorities may shift; this is a guide, not a contract.

## Near term (current focus)

- **Stability** — Keep the core pipeline (parse → Zig → JIT/compile) and engine NIFs stable; fix regressions and improve error messages.
- **Documentation** — Clear “why Zixir,” use cases, config, deploy, and standard library so evaluators and operators have one place to look.
- **CI** — Automated build and test (e.g. GitHub Actions) on push/PR so changes are validated consistently.
- **Developer experience** — First-run experience (fewer noisy warnings), VS Code extension install path, and clear distinction between `mix zixir run` (short path) and full compiler pipeline (MLIR/typecheck).

## Medium term

- **List comprehensions** — Complete codegen so list comps execute correctly (parser and type inference already exist).
- **Pattern matching** — Broaden codegen and tests for more pattern shapes and edge cases.
- **Observability** — Document and, where useful, provide a simple integration path (e.g. Prometheus/ Grafana) for production.
- **Examples and content** — More runnable examples (pipelines, retries, cache, Python call) and a consolidated use-cases doc.

## Longer term / exploratory

- **Optional MLIR (Beaver)** — Keep optional; improve “quick start with Beaver” on Unix for users who want full MLIR.
- **Python NIF** — Document when NIF vs port is used; improve build/deploy story for the NIF path.
- **GPU** — Keep toolchain-dependent; document one “quick start” (e.g. CUDA) for users who need it.
- **Ecosystem** — Hex package, possible VS Code extension publish, CONTRIBUTING and community guidelines.

---

*Last updated: 2026. For implementation status and gaps, see [PROJECT_ANALYSIS.md](PROJECT_ANALYSIS.md).*
