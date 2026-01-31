# Zixir v3.0.0 — AI automation release

This release adds full AI automation support: workflow orchestration with checkpointing, resource sandboxing, streaming/async, observability, and a cache layer. Plus universal improvements for binary serialization, tracing, sandbox results, and GenServer startup.

## AI automation features

### 1. Workflow orchestration with checkpointing ✅

- **Files:** `lib/zixir/workflow.ex`, `lib/zixir/workflow/checkpoint.ex`
- **Features:** DAG execution, dependency management, automatic checkpointing, resume from failure, retry policies, dead letter queues
- **Usage:** Build fault-tolerant AI pipelines that recover automatically

### 2. Resource limits & sandboxing ✅

- **File:** `lib/zixir/sandbox.ex`
- **Features:** Time limits, memory limits (e.g. "2GB"), CPU monitoring, automatic process termination, call depth limits
- **Usage:** Prevent runaway AI processes from consuming all resources

### 3. Streaming & async support ✅

- **File:** `lib/zixir/stream.ex`
- **Features:** Async/await, parallel execution, lazy sequences, stream transformations (map, filter, batch), backpressure
- **Usage:** Handle streaming AI responses (LLMs) and parallel model inference

### 4. Structured observability ✅

- **File:** `lib/zixir/observability.ex`
- **Features:** JSON logging, execution tracing with spans, Prometheus-compatible metrics, performance monitoring
- **Usage:** Monitor AI workflows without manual intervention

### 5. Cache & persistence layer ✅

- **File:** `lib/zixir/cache.ex`
- **Features:** In-memory caching with TTL, disk persistence, database-like operations (insert/query/update), cache warming
- **Usage:** Store intermediate results and avoid redundant computation

## Universal improvements

| Improvement | Benefit |
|-------------|---------|
| **Binary serialization** (instead of JSON) | Handles all Elixir data types (tuples, atoms, PIDs, etc.); more reliable for internal state persistence |
| **Span struct initialization** | Prevents KeyError in all tracing scenarios; works regardless of span lifecycle |
| **Result wrapping in Sandbox** | Follows Elixir `{:ok, result}` / `{:error, reason}` convention; consistent across all sandboxed operations |
| **GenServer startup handling** | Standard Elixir pattern for idempotent service startup; works in supervision trees and manual startup |

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist calls

## Quick start

```bash
git clone https://github.com/PersistenceOS/Zixir.git
cd Zixir
git checkout v3.0.0
mix deps.get
mix zig.get
mix compile
mix test
```

## License

**Apache-2.0** — see [LICENSE](LICENSE).
