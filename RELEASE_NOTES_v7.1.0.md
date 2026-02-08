# Zixir v7.1.0 — Enhanced AI Playground

Release 7.1 adds the **Enhanced AI Playground**: chat and task modes with integrated context (workflows, databases, system metrics, vectors), document upload and search, and natural language to SQL.

---

## New in 7.1

### AI Playground — Chat (primary interface)

- **Natural conversation** with your Ollama model (e.g. Llama 3.1)
- **Context-aware responses** — the AI can see:
  - Active workflows and status
  - Database connections (sample data)
  - System metrics (uptime, memory)
  - Vector collections
- **Quick action buttons** for common queries
- **Conversation history** (per session, localStorage)
- **Provider selection** (Ollama, OpenAI, etc.)

### AI Playground — Tasks

- **Classify Text** — categorize into custom labels
- **Extract Entities** — names, dates, amounts
- **Summarize** — condense to specified length
- **Analyze Sentiment** — positive / negative / neutral  
All with your configured model, latency tracking, and JSON output.

### Integrated context (what the AI knows)

- **Workflows:** count, status, recent activity, success rates
- **Databases:** configured connections, status, sample schema
- **System:** Zixir version, uptime, memory, errors
- **Vectors:** collection names, document counts

### Document upload & search

- **Upload files** (PDF, DOCX, TXT, MD, JSON) from the Vector Search UI
- **Hash-based embeddings** (~1ms), no external API
- **Semantic search** across uploaded documents (~2–4ms)
- **Works offline**, zero extra dependencies

### Database query bridge

- **Natural language → SQL** conversion
- **Read-only** query execution (safety enforced)
- **SQL shown** in responses (mock/sample results in this release)

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ODBC and VectorDB
- **Ollama** *(optional)* for local AI Playground chat

---

## Quick start

### First-time install

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v7.1.0
mix deps.get
mix zig.get
mix compile
mix phx.server   # start web UI
```

Then open **http://localhost:4000**. Use **AI Playground** from the sidebar.

### Clean build (troubleshoot or reinstall)

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout -- .
git fetch origin --tags
git checkout v7.1.0
mix clean
mix deps.clean --all
mix deps.get
mix zig.get
mix compile
mix phx.server   # start web UI
```

Then open **http://localhost:4000** in your browser.

---

## License

**Apache-2.0** — see [LICENSE](LICENSE).
