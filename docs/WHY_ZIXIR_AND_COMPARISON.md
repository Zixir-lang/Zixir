# Why Zixir and how it compares

This document gives a single place for “why Zixir exists” and how it compares to common alternatives.

## The problem Zixir addresses

Production AI and data pipelines often require:

- A **scheduler/orchestrator** (e.g. Airflow, Prefect)
- **State and queues** (e.g. Redis, a database)
- **Monitoring** (e.g. Prometheus, Grafana)
- **Custom code** for retries, timeouts, and fault tolerance

That’s multiple systems, YAML, and glue code. Zixir aims to provide **one language and one runtime** where orchestration, limits, caching, and observability are built in—so you can run pipelines without standing up Airflow, Redis, or K8s.

## Why Zixir?

- **One runtime** — No separate scheduler, queue, or state store. Run a Zixir release or `mix zixir run` and you get orchestration, caching, and supervision.
- **Three tiers in one process** — Elixir (orchestration, “let it crash”), Zig (hot path, predictable performance), Python (libraries when you need them). You write Zixir; the runtime splits work across tiers.
- **Fault tolerance by default** — Supervision, circuit breakers, retries, and resource limits are part of the runtime, not something you wire from scratch.
- **Predictable hot path** — Numeric and hot code run in Zig NIFs (no GC pauses, small binaries).
- **Optional MLIR** — When you want extra optimizations (and are on Unix), you can add Beaver; otherwise you still get AST-level optimizations.

See [README.md](../README.md) and [project_Analysis_for_fork.md](../project_Analysis_for_fork.md) for more on the stack and goals.

## When to choose Zixir

- You want **pipelines or agentic workflows** without adding Airflow, Redis, or K8s.
- You care about a **fast, predictable numeric path** (e.g. scoring, aggregates) and are okay with a new language.
- You like **Elixir/FP**, pattern matching, and type inference, and want **Python only where necessary** (e.g. numpy, APIs).
- You prefer **one codebase and one deployable** over a mesh of services.

## When not to choose Zixir

- You need **very large distributed DAGs** (thousands of tasks, many workers)—ecosystems like Airflow/Temporal are more proven at that scale.
- Your team is **Python-only** and unwilling to adopt a new language.
- You are **already standardized** on Airflow/Kubeflow and don’t need an alternative.

## Comparison at a glance

| Aspect | Zixir | Airflow | Prefect | Temporal |
|--------|--------|---------|---------|----------|
| **Extra infra** | None (single runtime) | Redis + DB typical | Minimal | Temporal server |
| **Setup time** | ~20 min | ~2 hours | ~1 hour | ~1 hour |
| **Orchestration** | Built-in | DAGs | Flows | Workflows |
| **State/cache** | ETS + disk (built-in) | DB + optional Redis | DB | Temporal |
| **Hot path** | Zig NIFs | Python | Python | Your code |
| **Fault tolerance** | Supervision, circuit breakers | Basic / custom | Basic / custom | Durable workflows |
| **Pattern matching** | Native in language | No | No | No |
| **REPL** | Yes | No | No | No |
| **Ecosystem size** | Small (newer) | Large | Large | Growing |

**Bottom line:** Zixir is a strong fit for small/medium pipelines and agentic workflows where you want one runtime and no extra infra; it is not yet positioned for “massive distributed DAG” or “Python-only” as the main requirement.

For real-world use cases, see [USE_CASES.md](USE_CASES.md). For implementation status, see [PROJECT_ANALYSIS.md](../PROJECT_ANALYSIS.md).
