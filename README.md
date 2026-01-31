# Zixir

<p align="center"><img src="assets/zixir-icon.png" alt="Zixir" width="128" /></p>

**Repository:** [github.com/PersistenceOS/Zixir](https://github.com/PersistenceOS/Zixir)

Zixir is an **AI automation programming language** that combines workflow orchestration, resource management, and observability into a single, cohesive tool—so you don’t need to glue together Airflow, Redis, and Prometheus. It’s a small, expression-oriented language on a **three-tier runtime**: **Elixir** (orchestrator), **Zig** (engine), **Python** (specialist).

## Why Zixir?

**The problem:** Building production AI pipelines usually means combining Airflow for orchestration, Kubernetes for deployment, Redis for caching, Prometheus for monitoring, custom code for fault tolerance, and YAML for configuration.

**The Zixir solution:** One language that does it all. Workflow orchestration, checkpointing, resource limits, circuit breakers, and built-in caching (ETS + disk, no Redis) are part of the runtime—not bolted on.

**Accurate highlights:**

- **Built-in caching** — ETS (in-memory) and local disk; no Redis/Memcached required.
- **Pattern matching** — Native language feature; no other workflow tool has this.
- **Interactive REPL** — Built-in REPL for workflow development; Airflow/Kubeflow/Prefect don’t have this.
- **Fault tolerance built-in** — Supervision trees, circuit breakers, retries; not bolted-on like other tools.
- **Three-tier architecture** — Elixir + Zig + Python; unique combination for orchestration, native speed, and ML.

**Trade-offs:**

- ✅ Less infrastructure to manage  
- ✅ Faster development (interactive REPL)  
- ✅ Strong fault tolerance and type safety  
- ⚠️ Requires learning Elixir/Zixir syntax  
- ⚠️ Smaller ecosystem than Python  
- ⚠️ Newer project (less battle-tested)

## Why a three-tier runtime?

Each tier does what it’s best at; together they cover orchestration, speed, and ecosystem in one stack.

| Tier | Role | Strength |
|------|------|----------|
| **Elixir** | Orchestrator | Concurrency, fault tolerance, supervision (“let it crash”), distributed systems, hot reload, OTP. Coordinates many tasks and keeps the system up. |
| **Zig** | Engine | Predictable performance, no GC pauses, low-level control, small binaries. Ideal for hot paths: parsing, math, core ops, NIFs. |
| **Python** | Specialist | Huge ecosystem: ML (PyTorch, TensorFlow), data (pandas, numpy), scripting, APIs. Run existing libraries without rewriting them. |

**Benefits:**

- **Right tool per layer** — Orchestration in Elixir, heavy computation in Zig, ML/data/scripts in Python, instead of forcing everything into one language.
- **Performance where it matters** — Zig runs the hot path with predictable latency and no GC; Python is used for “expensive but occasional” work (e.g. model inference, data prep).
- **Reuse, don’t rewrite** — Python’s libraries (ML, science, tooling) are called from the same runtime; you don’t reimplement them in Elixir or Zig.
- **Resilience at the top** — Elixir supervises workers and restarts them on failure; a crashing Zig NIF or Python subprocess can be isolated and restarted without bringing down the whole system.
- **Good fit for agentic / AI workflows** — Elixir coordinates many steps and tools; Zig runs core logic and parsing fast; Python runs models and specialist tools.

**When you’d want this:** building agentic coding or AI tooling (many tools + fast core + Python ML/data), needing throughput and low latency in the core engine but also Python libraries, or wanting fault tolerance and concurrency (Elixir) without giving up predictable performance (Zig) or ecosystem (Python).

### Zixir vs. alternatives (honest assessment)

| Feature | Zixir | Airflow | Kubeflow | Prefect |
|---------|-------|---------|----------|---------|
| **External infrastructure** | Elixir runtime only* | Redis + DB | Kubernetes | Minimal |
| **Setup time** | ~20 min | ~2 hours | ~2 days | ~1 hour |
| **Lines of code (typical ML pipeline)** | 50–150 | 200–500 | 500–1000 | 150–400 |
| **Workflow orchestration** | ✅ Built-in | ✅ | ✅ | ✅ |
| **Checkpointing** | ✅ Any type | ⚠️ JSON only (XCom) | ✅ | ✅ |
| **Resource limits** | ✅ Code-level primitives | ✅ Config (e.g. execution_timeout) | ✅ YAML | ✅ Decorators |
| **Fault tolerance** | ✅ Supervision + circuit breakers | ⚠️ Basic | ⚠️ K8s | ⚠️ Basic |
| **Observability** | ✅ Built-in | ⚠️ Manual | ⚠️ Complex | ⚠️ UI |
| **Pattern matching** | ✅ Native | ❌ | ❌ | ❌ |
| **Interactive REPL** | ✅ | ❌ | ❌ | ❌ |
| **Type inference** | ✅ | ❌ | ❌ | ❌ |
| **Native performance** | ✅ Zig NIFs | ❌ | ❌ | ❌ |

\* Requires Elixir and Zig (build-time) to run; no Redis, K8s, or separate DB for workflows.

**Key difference:** Zixir bakes orchestration, resource limits, and observability into the language. Other tools add these via configuration and external services.

**Bottom line:** Zixir is a new AI automation language that puts workflow orchestration, resource management, and observability directly into the language—so you don’t need to glue together Airflow + Redis + Prometheus. It requires Elixir and Zig to run, but once set up, you get features that would normally require 3–5 external services. It’s particularly strong for teams that want functional patterns (pattern matching, type inference) and built-in fault tolerance.

### Layout (three-tier flow)

```mermaid
flowchart TB
  Source[Zixir source / eval]

  subgraph T1["Tier 1: Elixir - Orchestrator"]
    Intent[Intent / routing]
    Memory[Memory / state]
    Supervisor[Supervision]
  end

  subgraph T2["Tier 2: Zig - Engine"]
    NIF[NIFs]
    Math[Math, parsing, core ops]
  end

  subgraph T3["Tier 3: Python - Specialist"]
    Port[Port bridge]
    Libs[ML, data, scripts]
  end

  Source --> Intent
  Intent --> Memory
  Intent --> Supervisor
  Intent -->|hot path| NIF
  Intent -->|library calls| Port
  NIF --> Math
  Port --> Libs
```

## Requirements

**Minimum:**

- **Elixir** 1.14+ / OTP 25+ (runtime)
- **Zig** 0.15+ (build-time only; Zigler fetches via `mix zig.get` after `mix deps.get`)
- ~100 MB disk space
- File system (for persistence / checkpoints / cache)

**Optional:**

- **Python** 3.8+ (if using ML models or specialist calls; recommend virtualenv)
- Extra disk (for checkpoints and cache)

## Supported platforms

- Windows, macOS, Linux. Test on your target OS (e.g. VS Code Ctrl+Shift+P) before rollout.
- **Elixir/OTP**: 1.14+ / 25+
- **Zig**: Zigler 0.15 expects Zig 0.15.x. Run `mix zig.get` so Zigler uses its cached 0.15.2; if you have Zig 0.16 on PATH, the verify script prefers the Zigler cache.
- **Python**: 3.10+ for specialist; recommend virtualenv or container for reproducible library calls.
- **Optional MLIR (Beaver)**: add `{:beaver, "~> 0.4"}` to deps on Unix only; Kinda (Beaver’s dep) does not support Windows.

## Environment

- Set `config :zixir, :python_path, "/path/to/python"` if Python is not on `PATH`.
- Python specialist script: `priv/python/port_bridge.py` (shipped with app; use `Application.app_dir(:zixir)` for path).
- Zig: Zigler compiles NIFs at compile time; ensure Zig is available when running `mix compile`.

## Entry point (agentic extension)

Single public API for invoking Zixir from an agentic coding extension:

- `Zixir.run_engine(op, args)` — hot path (math, data) → Zig.
- `Zixir.call_python(module, function, args)` — library calls → Python.

No duplicate routing or protocol code; intent and routing live in `Zixir.Intent`.

## Setup

```bash
mix deps.get
mix zig.get   # after deps.get, for Zigler
mix compile
```

For Python specialist: ensure Python is on `PATH` or set in config; recommend a virtualenv.

## Usage

### Zixir language (source)

Run Zixir source with `eval/1` or `run/1`:

```elixir
Zixir.eval("engine.list_sum([1.0, 2.0, 3.0])")
# => {:ok, 6.0}

Zixir.run("let x = 5\nlet y = 5\nx + y")
# => 10
```

Run a `.zixir` file:

```bash
mix zixir.run examples/hello.zixir
```

Grammar, types, and standard library: see [docs/LANGUAGE.md](docs/LANGUAGE.md).

### Elixir API

- `Zixir.run_engine/2` — hot path (math, data) → Zig NIFs
- `Zixir.call_python/3` — library calls → Python via port

See [project_Analysis_for_fork.md](project_Analysis_for_fork.md) for architecture and failure model.

## Build

```bash
mix compile
```

## Test

```bash
mix test
```

## Verification (full check)

From the project root, run in order:

```bash
mix deps.get
mix zig.get
mix compile
mix test
mix zixir.run examples/hello.zixir
```

Expected: tests pass; `examples/hello.zixir` prints `11.0`. On Windows run `scripts\verify.ps1`; if you see "mix is not recognized", install [Elixir](https://elixir-lang.org/install.html#windows) and add it to your PATH (or open a terminal from the Elixir start menu entry and run the script again).

## License

**Apache-2.0** — see [LICENSE](LICENSE).
