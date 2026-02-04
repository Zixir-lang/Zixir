# Configuration and deployment

This document describes Zixir configuration options and how to deploy in production.

## Configuration

All options are under the `:zixir` application key in `config/config.exs` (or environment-specific config).

### Python

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `python_path` | path/string | `System.find_executable("python3") \|\| ...` | Python interpreter path. Set if Python is not on PATH. |
| `python_workers_max` | integer | 4 (1 in test) | Max Python port workers. |
| `python_timeout` | integer (ms) | 30_000 | Timeout for Python calls. |

### Timeouts (milliseconds)

| Key | Default | Description |
|-----|---------|-------------|
| `default_timeout` | 30_000 | General default. |
| `sandbox_timeout` | 30_000 | Sandbox execution. |
| `workflow_step_timeout` | 30_000 | Workflow step. |
| `stream_timeout` | 30_000 | Stream operations. |
| `modules_timeout` | 30_000 | Module operations. |
| `circuit_breaker_cooldown` | 30_000 | Cooldown after circuit opens. |

### Supervision and resilience

| Key | Default | Description |
|-----|---------|-------------|
| `restart_window_seconds` | 5 | Window for counting restarts. |
| `max_restarts` | 3 | Max restarts in window before supervisor gives up. |

### Persistence

| Key | Default | Description |
|-----|---------|-------------|
| `workflow_checkpoint_dir` | `"_zixir_workflows"` | Directory for workflow checkpoints. |
| `cache_persist_dir` | `"_zixir_cache"` | Directory for cache persistence. |

### Example override

In `config/config.exs` or `config/prod.exs`:

```elixir
config :zixir,
  python_path: "/usr/bin/python3",
  python_timeout: 60_000,
  workflow_step_timeout: 120_000,
  cache_persist_dir: "/var/lib/zixir/cache"
```

## Deployment (production)

### Build a release

From the project root:

```bash
mix deps.get
mix zig.get
mix release
```

Artifacts are under `_build/prod/rel/zixir/`.

### Run the release

**Unix:**

```bash
_build/prod/rel/zixir/bin/zixir start
```

Or foreground:

```bash
_build/prod/rel/zixir/bin/zixir start_iex
```

**Windows:**

```bat
_build\prod\rel\zixir\bin\zixir.bat start
```

### Portable CLI (run scripts from anywhere)

After building a release, add the release `bin` directory to your PATH:

- Unix: `_build/prod/rel/zixir/bin/`
- Windows: `_build\prod\rel\zixir\bin\`

Then use the included scripts to run Zixir files from any directory:

- Unix: `zixir_run.sh path/to/script.zixir`
- Windows: `zixir_run.bat path\to\script.zixir`

Scripts live under `rel/overlays/bin/` and are copied into the release.

### Environment variables

- No Zixir-specific env vars are required for basic operation.
- For Python: ensure the interpreter is on PATH or set `python_path` in config.
- For production, set `MIX_ENV=prod` when building (e.g. `MIX_ENV=prod mix release`).

### Production checklist

1. Build with `MIX_ENV=prod mix release`.
2. Configure `config/prod.exs` (or prod env) with timeouts and paths appropriate for your environment.
3. Set workflow and cache dirs to writable, persistent paths if you use checkpoints or cache.
4. Run the release under a process supervisor (systemd, Windows Service, or your platform’s standard) if you need automatic restarts.
5. For observability, use the built-in logging/tracing/metrics (see `lib/zixir/observability.ex`) and plug into your existing monitoring (e.g. log aggregation, Prometheus) as needed.

For observability APIs, see [PROJECT_ANALYSIS.md](../PROJECT_ANALYSIS.md) and `lib/zixir/observability.ex`.
