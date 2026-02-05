# VectorDB backends — setup and options

Zixir's VectorDB supports **9 backends**: one native in-memory backend and eight Python-based backends (Chroma, Pinecone, Weaviate, Qdrant, Milvus, pgvector, Redis, Azure). Cloud backends use **connection pooling**, **exponential backoff**, **circuit breaker**, **query caching**, **health checks**, and **request metrics** so they survive real-world failures.

---

## Cloud backends — resilience features

| Feature | Benefit |
|---------|---------|
| **Connection pooling** | Better resource utilization |
| **Exponential backoff** | Handles transient failures gracefully |
| **Circuit breaker** | Prevents cascade failures |
| **Query caching** | Reduces redundant DB calls |
| **Health checks** | Real-time monitoring |
| **Request metrics** | Track latency, success rates |

Use `Zixir.VectorDB.health/1`, `Zixir.VectorDB.metrics/1`, `Zixir.VectorDB.cache_stats/1`, and `Zixir.VectorDB.circuit_breaker/1` to monitor cloud backends from Elixir.

---

## Complete backend support (9 total)

| Backend | Type | Best for |
|---------|------|----------|
| `:memory` | Native | Prototyping (&lt;100K vectors) |
| `:chroma` | Python | Simple local development |
| `:pinecone` | Python | Production cloud |
| `:weaviate` | Python | Self-hosted, GraphQL |
| `:qdrant` | Python | High-performance |
| `:milvus` | Python | Enterprise distributed |
| `:pgvector` | Python | PostgreSQL users needing ACID compliance |
| `:redis` | Python | Real-time apps needing sub-ms latency |
| `:azure` | Python | Microsoft ecosystems |

---

## 3 new backends (v6.0)

| Backend | For |
|---------|-----|
| **:pgvector** | PostgreSQL users needing ACID compliance |
| **:redis** | Real-time apps needing sub-ms latency |
| **:azure** | Microsoft ecosystems |

---

## How to set up backends

### Native (no Python install)

- **:memory** — Built in. No extra setup. Use for prototyping and small datasets.

### Python backends — install by backend

Install only the packages for the backends you use. Zixir’s Python bridge runs under your project’s Python (or the interpreter set in `config :zixir, :python_path`).

**Chroma (local dev):**
```bash
pip install chromadb
```

**Pinecone (cloud):**
```bash
pip install pinecone-client
```

**Weaviate (self-hosted):**
```bash
pip install weaviate-client
```

**Qdrant (high-performance):**
```bash
pip install qdrant-client
```

**Milvus (enterprise):**
```bash
pip install pymilvus
```

**pgvector (PostgreSQL):**
```bash
pip install psycopg2-binary pgvector
```
You also need PostgreSQL with the [pgvector](https://github.com/pgvector/pgvector) extension enabled.

**Redis:**
```bash
pip install redis
```
Use a Redis instance with RediSearch/vector support (e.g. Redis Stack).

**Azure (AI Search / vector search):**
```bash
pip install azure-search-documents azure-identity
```
Configure Azure AI Search and credentials (e.g. `AZURE_SEARCH_ENDPOINT`, `AZURE_SEARCH_KEY` or managed identity).

### Install multiple backends

Example for Chroma + Pinecone + pgvector:
```bash
pip install chromadb pinecone-client psycopg2-binary pgvector
```

---

## Creating a VectorDB in Zixir

```elixir
# Memory (no Python)
db = Zixir.VectorDB.create("my_db", dimensions: 384)

# Chroma (local)
db = Zixir.VectorDB.create("local",
  backend: :chroma,
  collection: "docs",
  dimensions: 384
)

# Pinecone (cloud)
db = Zixir.VectorDB.create("prod",
  backend: :pinecone,
  api_key: System.get_env("PINECONE_API_KEY"),
  environment: "us-east-1",
  index_name: "my-index",
  dimensions: 384
)

# pgvector (PostgreSQL)
db = Zixir.VectorDB.create("pg",
  backend: :pgvector,
  connection_string: System.get_env("DATABASE_URL"),
  table_name: "embeddings",
  dimensions: 384
)

# Redis
db = Zixir.VectorDB.create("redis",
  backend: :redis,
  host: "localhost",
  port: 6379,
  index_name: "vec",
  dimensions: 384
)

# Azure
db = Zixir.VectorDB.create("azure",
  backend: :azure,
  endpoint: System.get_env("AZURE_SEARCH_ENDPOINT"),
  api_key: System.get_env("AZURE_SEARCH_KEY"),
  index_name: "my-index",
  dimensions: 384
)
```

---

## Health and resilience from Elixir

```elixir
# Health (circuit breaker, pool, cache)
health = Zixir.VectorDB.health(db)

# Request metrics (latency, success rate)
metrics = Zixir.VectorDB.metrics(db)

# Cache stats (if query caching enabled)
cache_stats = Zixir.VectorDB.cache_stats(db)

# Circuit breaker state (:closed | :open | :half_open)
state = Zixir.VectorDB.circuit_breaker(db)

# Quick healthy check
Zixir.VectorDB.healthy?(db)
```

---

## See also

- [Zixir.VectorDB](https://github.com/Zixir-lang/Zixir) — module docs and `lib/zixir/vector_db.ex`
- [SETUP_GUIDE.md](../SETUP_GUIDE.md) — Python and Elixir setup
- [RELEASE_NOTES_v6.0.0.md](../RELEASE_NOTES_v6.0.0.md) — v6.0 VectorDB release notes
