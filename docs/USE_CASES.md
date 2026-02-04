# Real-world use cases for Zixir

This document describes concrete scenarios where Zixir is a good fit.

## 1. ML and data pipelines (without Airflow/Redis)

- **Batch feature computation** — Ingest events, compute features (e.g. with `engine.list_sum`, `engine.dot_product`), write to storage. One process, no DAG YAML or separate scheduler.
- **Model scoring** — Load weights, run `engine.dot_product(weights, features)` per request or batch; optionally call Python for post-processing. Elixir handles concurrency and restarts.
- **Data validation and drift** — Run validation and drift checks as steps in a pipeline; use built-in circuit breakers and retries when steps fail.

**Why Zixir:** One language and runtime; Zig for fast math; Python only where you need libraries.

## 2. Agentic and AI automation

- **Multi-step agent workflows** — Plan → call tools (APIs, DBs) → reason → act. Each step can be a Zixir workflow step with checkpoints and retries; state in memory or disk cache (no Redis).
- **Orchestrating LLM + code + data** — Elixir coordinates calls; Zig runs fast numeric or parsing steps; Python runs numpy/scipy or LLM SDKs when needed.
- **CI/CD or ops automation** — Scripts that run experiments, run models, or validate data; use Zixir’s resource limits and timeouts to avoid runaway jobs.

**Why Zixir:** Built for high-success agentic workloads; supervision and circuit breakers; optional observability and checkpointing.

## 3. Real-time or low-latency numeric services

- **Recommendation / ranking** — Per-request score with `engine.dot_product(weights, features)` (and similar) in Zig; optional Python for heavier ML libs; Elixir for concurrency and failure handling.
- **Metrics and analytics aggregation** — Stream of events → aggregate (sum, product, counts) in Zig; cache results (ETS/disk); dashboards or alerts read from cache.
- **Pricing or risk calculations** — Deterministic numeric formulas in Zixir (Zig for hot path); workflow steps and logging for auditability.

**Why Zixir:** Predictable performance from Zig NIFs; no GC on the hot path; Elixir for reliability.

## 4. Internal tools and data prep

- **ETL / data prep** — Load → transform (Zixir + `engine.*` + Python for pandas/numpy) → validate → write; run as one-off or on a schedule via mix or scripts.
- **A/B and experimentation** — Use Zixir’s experiment framework (stats, confidence intervals, winner promotion) in pipelines that prepare and analyze experiment data.
- **Report generation** — Pull data → compute aggregates (Zig) → optional charts (Python) → emit report; orchestration and retries in Zixir.

**Why Zixir:** Single stack for orchestration, math, and Python libs; less glue than “Python script + cron + Redis.”

## 5. Embedded, edge, or resource-constrained

- **On-device or on-prem scoring** — Compile Zixir to a native binary (`mix zixir compile`); run scoring or small pipelines without a heavy runtime; Python only if the environment has it.
- **Raspberry Pi / gateways** — Lightweight binaries; Elixir’s supervision for long-running or periodic jobs.

**Why Zixir:** Small binaries (Zig), no JVM; optional Python when needed.

---

For setup and capabilities, see [README.md](../README.md) and [PROJECT_ANALYSIS.md](../PROJECT_ANALYSIS.md). For “why Zixir vs others,” see [WHY_ZIXIR_AND_COMPARISON.md](WHY_ZIXIR_AND_COMPARISON.md).
