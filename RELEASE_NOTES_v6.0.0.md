# Zixir v6.0.0 — Major Release ⭐ RECOMMENDED

Major release with **VectorDB backend expansion** and **cloud resilience**. Nine backends supported; cloud backends use connection pooling, exponential backoff, circuit breaker, query caching, health checks, and request metrics. Follows semantic versioning (new backends + resilience = major).

---

## New Features & Improvements

### VectorDB: 3 new backends (9 total)

| Backend   | Type   | Best For                          |
|-----------|--------|------------------------------------|
| **:pgvector** | Python | PostgreSQL users, ACID compliance |
| **:redis**    | Python | Real-time apps, sub-ms latency    |
| **:azure**    | Python | Microsoft ecosystems              |

Existing: `:memory`, `:chroma`, `:pinecone`, `:weaviate`, `:qdrant`, `:milvus`.

### Cloud backends: real-world resilience

| Feature           | Benefit                              |
|-------------------|--------------------------------------|
| Connection Pooling| Better resource utilization          |
| Exponential Backoff | Handles transient failures gracefully |
| Circuit Breaker   | Prevents cascade failures            |
| Query Caching     | Reduces redundant DB calls           |
| Health Checks     | Real-time monitoring                 |
| Request Metrics   | Track latency, success rates         |

### Documentation

- **[docs/VECTORDB_BACKENDS.md](docs/VECTORDB_BACKENDS.md)** — Setup and `pip install` for each backend; resilience options; examples for create/health/metrics from Elixir.

---

## Complete Backend Support (9 Total)

| Backend   | Type   | Best For                          |
|-----------|--------|------------------------------------|
| :memory   | Native | Prototyping (< 100K vectors)       |
| :chroma   | Python | Simple local development          |
| :pinecone | Python | Production cloud                  |
| :weaviate | Python | Self-hosted, GraphQL               |
| :qdrant   | Python | High-performance                   |
| :milvus   | Python | Enterprise distributed             |
| :pgvector | Python | PostgreSQL users                  |
| :redis    | Python | Real-time apps                    |
| :azure    | Python | Microsoft ecosystems              |

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ML/specialist and VectorDB backends
- **VectorDB** — Install backend-specific client, e.g. `pip install chromadb` or `pip install pgvector`. See [docs/VECTORDB_BACKENDS.md](docs/VECTORDB_BACKENDS.md).

## Quick start

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v6.0.0
mix deps.get
mix zig.get
mix compile
```

**VectorDB (optional):** Pick a backend and install its client, then see [docs/VECTORDB_BACKENDS.md](docs/VECTORDB_BACKENDS.md) for create/health/metrics examples.

## License

**Apache-2.0** — see [LICENSE](LICENSE).
