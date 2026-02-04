# Zixir Project Analysis

## Purpose

Zixir is a three-tier runtime combining Elixir (orchestrator), Zig (engine), and Python (specialist) for high-success agentic workloads with minimal human intervention. This document aligns fork structure, goals, and production-extension requirements.

## Stack

| Layer | Technology | Role |
|-------|------------|------|
| Orchestrator | Elixir / OTP | Failures, concurrency, intent, routing |
| Engine | Zig + Zigler | Memory-critical math, high-speed data (NIFs) |
| Specialist | Python via Port | Library calls only (no Python in BEAM) |
| IR (optional) | Beaver / MLIR | Codegen and optimization |

## Goals

- **Python library compatibility**: Call Python libraries via port protocol from Elixir.
- **Minimal human interaction**: Supervision and routing handle failures; structured errors and optional alerts.
- **High success rate and memory**: Intent router + state/memory layer; Zig for hot path; Python for library-only workloads.
- **Let it crash**: Fail safely under supervision; design to **minimize** failures (restart limits, circuit breaker, input validation).

## Failure Model ("Let It Crash" + Minimal Failures)

1. **Supervision**: All long-lived components under a supervision tree (application, intent router, memory, Python port workers).
2. **Restart limits**: Max restarts (e.g. 3) in a short window (e.g. 5s) so a flapping Python process or NIF doesn't spin forever; supervisor terminates and parent can escalate or replace.
3. **Zig NIFs**: Short (< 1ms when possible); use dirty CPU/threaded only when needed; validate inputs in Elixir to reduce NIF-side crashes.
4. **Python ports**: Supervised port process; circuit breaker records failures and opens after threshold so repeated Python failures don't overwhelm the supervisor.
5. **Routing**: Hot path → Zig; library calls → Python; return structured errors (or retry with backoff) when specialist is down; log for minimal human intervention.

## Repo Layout

- **Root**: `project_Analysis_for_fork.md`, `README.md`, `mix.exs`, `config/`
- **Orchestrator**: `lib/zixir/` — application, supervisor, intent router, memory, python/, engine/
- **Engine**: Zigler modules in `lib/zixir/engine/` or `zig/`/`native/`
- **Specialist**: `priv/python/` — single entry script, wire format, adapter for libraries
- **Optional MLIR**: `lib/zixir/mlir.ex` or mix task
- **VS Code**: `.vscode/` — Zixir language extension (syntax, LSP client); install from this folder for “Install Extension from Location”. See `docs/VSCODE_INTEGRATION.md` and `PROJECT_ANALYSIS.md` for implementation status.

## Production Extension Alignment

- One entry point for invoking Zixir from the agentic extension.
- No duplicate routing or protocol code.
- Document OS (Windows/macOS/Linux), Elixir/OTP, Zig, and Python versions; test in VS Code (e.g. Ctrl+Shift+P) before rollout.
