# Zixir v7.0.0 — Web UI Dashboard

Release 7.0 introduces the **Zixir Web UI Dashboard**: a full-featured local dashboard for workflow execution, SQL exploration, vector search, templates, and scheduling. Run it with Zixir and access everything from your browser.

---

## New Features

### 1. Workflow Execution & Monitoring

- **Live workflow execution logs** with real-time streaming (Server-Sent Events)
- **Step-by-step progress tracking** with duration metrics
- **Workflow history** — last 50 runs with full audit trail
- **Pause / resume** workflow controls
- **Clone** existing workflows
- **Run details** with step-by-step breakdown

### 2. SQL Query Explorer

- **Visual query editor** with syntax highlighting
- **Direct database querying** on any saved ODBC connection
- **Table browser** with schema viewer
- **Results table** with CSV export
- **Query history** tracking
- **Column autocomplete** from schema

### 3. Vector Search Interface

- **Semantic document search** with similarity scores
- **Upload and embed** new documents
- **Collection management** (default, docs, knowledge base)
- **Visual similarity score** charts
- **Real-time search** with top-k results

### 4. Workflow Templates Library

- **6 pre-built templates:**
  - **Data Sync** — ETL automation
  - **Report Generation** — scheduled reports
  - **Email Alerts** — conditional notifications
  - **Data Backup** — automated backups
  - **API Integration** — external data fetch
  - **AI Summarization** — LLM-powered
- **One-click template deployment**
- **Difficulty levels** and popularity metrics

### 5. Simple Scheduler

- **Easy scheduling:** Hourly / Daily / Weekly presets
- **Custom cron expressions** for advanced users
- **Schedule management** per workflow
- **Next run** calculation
- **Schedule list** view

---

## UI/UX Enhancements

### Visual Design

- **Zixir brand colors** — orange–purple–yellow gradient theme
- **Logo integration** — Zixir icon with animated gradient glow
- **Welcome banner** — animated gradient backgrounds
- **Themed components** — buttons, cards, badges, progress bars
- **Quick actions** — floating gradient action button

### User Experience

- **Toast notification** system
- **Skeleton loading** states
- **Global search** (Ctrl+K shortcut)
- **Keyboard shortcuts**
- **Real-time auto-refresh** (5s intervals)
- **HTMX-powered** dynamic updates (no full page reloads)
- **Responsive sidebar** navigation

---

## Technical Improvements

### Backend API (40+ endpoints)

**Workflow management**

- `GET /api/workflow/:id/logs` — fetch execution logs
- `GET /api/workflow/:id/logs/stream` — Server-Sent Events streaming
- `GET /api/workflow/:id/steps` — step-by-step status
- `GET /api/workflow/:id/history` — run history
- `POST /api/workflow/:id/pause` | `resume` | `clone`

**SQL query**

- `POST /api/query/execute` — execute SQL
- `GET /api/query/connections/:id/tables` — list tables
- `GET /api/query/connections/:id/tables/:table/columns` — schema
- `POST /api/query/export/csv` — export results

**Vector operations**

- `POST /api/vector-search` — semantic search
- `POST /api/vector/embed` — embed documents
- `GET /api/vector/collections` — list collections
- `GET /api/vector/collections/:name/stats` — collection stats

**Templates & scheduling**

- `GET /api/workflow-templates` — template library
- `POST /api/workflow-templates/:id/deploy` — deploy template
- `GET` / `POST` / `DELETE /api/workflow/:id/schedule` — schedule CRUD
- `GET /api/schedules` — all schedules

### Integration

- **Real ODBC connection testing** (Zixir.ODBC)
- **Real VectorDB connection testing** (Zixir.VectorDB)
- **Zixir.Cache** persistence for configurations
- **Live workflow execution** tracking

---

## Infrastructure

### New pages

- `/query` — SQL Query Explorer
- `/vector-search` — Vector Search Interface
- `/workflows/:id/logs` — workflow logs viewer
- `/workflows/:id/history` — workflow history

### Tech stack

- **Framework:** Phoenix 1.8 with Bandit
- **Frontend:** HTMX + Tailwind CSS
- **Real-time:** Server-Sent Events for log streaming
- **Storage:** Zixir.Cache with disk persistence

---

## Requirements

- **Elixir** 1.14+ / OTP 25+
- **Zig** 0.15+ (build-time; run `mix zig.get` after `mix deps.get`)
- **Python** 3.8+ *(optional)* for ODBC bridge and VectorDB Python backends

---

## Quick start

```bash
git clone https://github.com/Zixir-lang/Zixir.git
cd Zixir
git checkout v7.0.0
mix deps.get
mix zig.get
mix compile
mix test
```

### Run the dashboard

```bash
# Start the app (dashboard at http://localhost:4000)
mix phx.server
```

Or run `iex -S mix` and open http://localhost:4000 — the dashboard starts with the application.

---

## License

**Apache-2.0** — see [LICENSE](LICENSE).
