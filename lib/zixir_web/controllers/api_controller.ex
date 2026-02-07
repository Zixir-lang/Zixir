defmodule ZixirWeb.APIController do
  use Phoenix.Controller, formats: [:html, :json]

  # GET /api/metrics - Dashboard metrics with real data integration
  def metrics(conn, _params) do
    metrics = fetch_real_metrics()
    json(conn, metrics)
  end

  def metrics_fragment(conn, _params) do
    metrics = fetch_real_metrics()
    conn
    |> put_view(ZixirWeb.APIView)
    |> render("metrics.html", metrics: metrics)
  end
  
  # Fetch real metrics from system where available
  defp fetch_real_metrics do
    # Get Python worker pool stats
    python_stats = case Zixir.Python.stats() do
      %{total_workers: total, healthy_workers: healthy} ->
        %{python_workers: total, healthy_workers: healthy}
      _ ->
        %{python_workers: 0, healthy_workers: 0}
    end
    
    # Get memory info (this is a simplified version - in production you'd use :erlang.memory/0)
    memory_mb = case :erlang.memory() do
      mem when is_list(mem) ->
        total = Keyword.get(mem, :total, 0)
        div(total, 1024 * 1024)
      _ -> 245
    end
    
    # Calculate uptime (simplified)
    uptime_seconds = :erlang.system_time(:second) - :erlang.system_info(:start_time)
    
    %{
      active_workflows: 12,
      success_rate: 98.5,
      failed_runs: 3,
      total_runs: 1250,
      uptime_seconds: uptime_seconds,
      memory_mb: memory_mb,
      cpu_percent: 35.2,
      python_workers: python_stats.python_workers,
      healthy_workers: python_stats.healthy_workers
    }
  end

  # GET /api/workflows - List all workflows
  def workflows(conn, _params) do
    workflows = [
      %{
        id: "wf_001",
        name: "order_processing",
        status: "running",
        progress: 85,
        started_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
        steps_completed: 4,
        total_steps: 5,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_002",
        name: "data_enrichment",
        status: "running",
        progress: 45,
        started_at: DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.to_iso8601(),
        steps_completed: 2,
        total_steps: 4,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_003",
        name: "llm_analysis",
        status: "failed",
        progress: 23,
        started_at: DateTime.utc_now() |> DateTime.add(-1800) |> DateTime.to_iso8601(),
        error: "OpenAI API rate limit exceeded",
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_004",
        name: "batch_export",
        status: "completed",
        progress: 100,
        started_at: DateTime.utc_now() |> DateTime.add(-86400) |> DateTime.to_iso8601(),
        completed_at: DateTime.utc_now() |> DateTime.add(-82800) |> DateTime.to_iso8601(),
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    ]
    json(conn, workflows)
  end

  def workflows_fragment(conn, _params) do
    workflows = [
      %{
        id: "wf_001",
        name: "order_processing",
        status: "running",
        progress: 85,
        started_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
        steps_completed: 4,
        total_steps: 5,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_002",
        name: "data_enrichment",
        status: "running",
        progress: 45,
        started_at: DateTime.utc_now() |> DateTime.add(-7200) |> DateTime.to_iso8601(),
        steps_completed: 2,
        total_steps: 4,
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_003",
        name: "llm_analysis",
        status: "failed",
        progress: 23,
        started_at: DateTime.utc_now() |> DateTime.add(-1800) |> DateTime.to_iso8601(),
        error: "OpenAI API rate limit exceeded",
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      %{
        id: "wf_004",
        name: "batch_export",
        status: "completed",
        progress: 100,
        started_at: DateTime.utc_now() |> DateTime.add(-86400) |> DateTime.to_iso8601(),
        completed_at: DateTime.utc_now() |> DateTime.add(-82800) |> DateTime.to_iso8601(),
        last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    ]
    conn
    |> put_view(ZixirWeb.APIView)
    |> render("workflows.html", workflows: workflows)
  end

  # GET /api/workflow/:id - Single workflow detail
  def workflow_detail(conn, %{"id" => id}) do
    workflow = %{
      id: id,
      name: "Sample Workflow",
      status: "running",
      progress: 65,
      steps: [
        %{name: "Validate Input", status: "completed", duration_ms: 150},
        %{name: "Process Data", status: "completed", duration_ms: 3200},
        %{name: "Call LLM", status: "completed", duration_ms: 15000},
        %{name: "Enrich Results", status: "running", duration_ms: nil},
        %{name: "Save Output", status: "pending", duration_ms: nil}
      ],
      logs: [
        %{timestamp: "2024-01-15T10:30:00Z", level: "info", message: "Workflow started"},
        %{timestamp: "2024-01-15T10:30:01Z", level: "info", message: "Step 1 completed"},
        %{timestamp: "2024-01-15T10:30:05Z", level: "info", message: "Step 2 completed"},
        %{timestamp: "2024-01-15T10:30:20Z", level: "info", message: "Step 3 completed"}
      ]
    }
    json(conn, workflow)
  end

  # POST /api/workflow/:id/start
  def workflow_start(conn, %{"id" => id}) do
    json(conn, %{status: "started", id: id})
  end

  # POST /api/workflow/:id/stop
  def workflow_stop(conn, %{"id" => id}) do
    json(conn, %{status: "stopped", id: id})
  end

  # POST /api/workflow/:id/retry
  def workflow_retry(conn, %{"id" => id}) do
    json(conn, %{status: "retrying", id: id})
  end

  # GET /api/connections - List ODBC connections
  def connections(conn, _params) do
    json(conn, fetch_connections())
  end

  def connections_fragment(conn, _params) do
    conn
    |> put_view(ZixirWeb.APIView)
    |> render("connections.html", connections: fetch_connections())
  end

  def connections_dashboard_fragment(conn, _params) do
    conn
    |> put_view(ZixirWeb.APIView)
    |> render("connections_dashboard.html", connections: fetch_connections())
  end

  defp fetch_connections do
    [
      %{
        id: "conn_001",
        name: "SQL Server Production",
        type: "sqlserver",
        dsn: "ProdDB",
        status: "connected",
        latency_ms: 12,
        last_query: DateTime.utc_now() |> DateTime.add(-30) |> DateTime.to_iso8601()
      },
      %{
        id: "conn_002",
        name: "PostgreSQL Analytics",
        type: "postgresql",
        dsn: "AnalyticsDB",
        status: "connected",
        latency_ms: 8,
        last_query: DateTime.utc_now() |> DateTime.add(-120) |> DateTime.to_iso8601()
      },
      %{
        id: "conn_003",
        name: "MySQL Legacy",
        type: "mysql",
        dsn: "LegacyDB",
        status: "disconnected",
        error: "Connection refused",
        last_query: nil
      }
    ]
  end

  # POST /api/connection/test
  def connection_test(conn, _params) do
    json(conn, %{status: "success", latency_ms: 15})
  end

  # POST /api/connection/add
  def connection_add(conn, _params) do
    json(conn, %{status: "created", id: "conn_004"})
  end

  # DELETE /api/connection/:id
  def connection_delete(conn, %{"id" => id}) do
    json(conn, %{status: "deleted", id: id})
  end

  # GET /api/vector-status - Vector DB status
  def vector_status(conn, _params) do
    status = %{
      backends: [
        %{
          name: "pgvector",
          status: "connected",
          vectors: 15420,
          size_mb: 245,
          last_query_ms: 2
        },
        %{
          name: "chroma",
          status: "connected",
          vectors: 45,
          size_mb: 12,
          last_query_ms: 5
        },
        %{
          name: "qdrant",
          status: "disconnected",
          error: "Connection timeout",
          vectors: 0,
          size_mb: 0
        }
      ],
      total_vectors: 15465,
      total_size_mb: 257
    }
    json(conn, status)
  end

  def vector_status_fragment(conn, _params) do
    status = %{
      backends: [
        %{
          name: "pgvector",
          status: "connected",
          vectors: 15420,
          size_mb: 245,
          last_query_ms: 2
        },
        %{
          name: "chroma",
          status: "connected",
          vectors: 45,
          size_mb: 12,
          last_query_ms: 5
        },
        %{
          name: "qdrant",
          status: "disconnected",
          error: "Connection timeout",
          vectors: 0,
          size_mb: 0
        }
      ],
      total_vectors: 15465,
      total_size_mb: 257
    }
    conn
    |> put_view(ZixirWeb.APIView)
    |> render("vector_status.html", status: status)
  end

  # ============================================================================
  # WIZARD API ENDPOINTS
  # ============================================================================

  # POST /api/wizard/connection/test - Test database connection
  def wizard_connection_test(conn, params) do
    driver = params["driver"] || "sqlserver"
    host = params["host"]
    port = parse_port(params["port"])
    database = params["database"]
    username = params["username"]
    password = params["password"]

    if missing_connection_params?(host, database, username, password) do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Missing required connection parameters"})
    else
      start_time = System.monotonic_time(:millisecond)

      result = Zixir.ODBC.connect(
        host: host,
        port: port,
        database: database,
        username: username,
        password: password,
        driver: driver
      )

      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, connection} ->
          Zixir.ODBC.disconnect(connection)
          json(conn, %{status: "success", latency_ms: duration, message: "Connection successful"})

        {:error, reason} ->
          conn
          |> put_status(400)
          |> json(%{status: "error", message: "Connection failed: #{reason}"})
      end
    end
  end

  # POST /api/wizard/connection/create - Create and save database connection
  def wizard_connection_create(conn, params) do
    name = params["name"]
    driver = params["driver"] || "sqlserver"
    host = params["host"]
    port = parse_port(params["port"])
    database = params["database"]
    username = params["username"]
    password = params["password"]

    if is_nil(name) or missing_connection_params?(host, database, username, password) do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Missing required parameters"})
    else
      connection_id = "conn_#{generate_id()}"
      connection_config = %{
        id: connection_id,
        name: name,
        driver: driver,
        host: host,
        port: port,
        database: database,
        username: username,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case Zixir.Cache.put("connection:#{connection_id}", connection_config, persistent: true) do
        :ok ->
          json(conn, %{
            status: "created",
            id: connection_id,
            message: "Connection '#{name}' created successfully"
          })

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{status: "error", message: "Failed to save connection: #{inspect(reason)}"})
      end
    end
  end

  # POST /api/wizard/vector-db/test - Test vector database connection
  def wizard_vector_test(conn, params) do
    backend = params["backend"] || "chroma"
    host = params["host"]
    api_key = params["api_key"]
    dimensions = parse_int(params["dimensions"]) || 1536

    config = [
      backend: String.to_atom(backend),
      dimensions: dimensions
    ]

    config = if host, do: Keyword.put(config, :host, host), else: config
    config = if api_key, do: Keyword.put(config, :api_key, api_key), else: config

    test_name = "test_#{generate_id()}"

    case Zixir.VectorDB.create(test_name, config) do
      {:ok, db} ->
        health = Zixir.VectorDB.health(db)
        Zixir.VectorDB.close(db)
        json(conn, %{status: "success", message: "Vector DB connection successful", health: health})

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{status: "error", message: "Connection failed: #{reason}"})
    end
  end

  # POST /api/wizard/vector-db/create - Create and save vector database
  def wizard_vector_create(conn, params) do
    name = params["name"]
    backend = params["backend"] || "chroma"
    host = params["host"]
    api_key = params["api_key"]
    dimensions = parse_int(params["dimensions"]) || 1536
    collection = params["collection"] || name

    if is_nil(name) do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Vector DB name is required"})
    else
      db_id = "vecdb_#{generate_id()}"
      db_config = %{
        id: db_id,
        name: name,
        backend: backend,
        host: host,
        api_key: api_key && "***REDACTED***",
        dimensions: dimensions,
        collection: collection,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      case Zixir.Cache.put("vector_db:#{db_id}", db_config, persistent: true) do
        :ok ->
          json(conn, %{
            status: "created",
            id: db_id,
            message: "Vector DB '#{name}' created successfully"
          })

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{status: "error", message: "Failed to save vector DB: #{inspect(reason)}"})
      end
    end
  end

  # GET /api/wizard/workflow/templates - Get available workflow templates
  def wizard_workflow_templates(conn, _params) do
    templates = [
      %{
        id: "data_pipeline",
        name: "Data Pipeline",
        description: "Extract, transform, and load data between sources",
        steps: ["extract", "transform", "validate", "load"],
        category: "data"
      },
      %{
        id: "ai_analysis",
        name: "AI Analysis",
        description: "Process data through AI models for insights",
        steps: ["fetch_data", "preprocess", "ai_call", "postprocess", "save_results"],
        category: "ai"
      },
      %{
        id: "order_processing",
        name: "Order Processing",
        description: "Complete order fulfillment workflow",
        steps: ["validate_order", "check_inventory", "process_payment", "fulfill_order"],
        category: "business"
      },
      %{
        id: "custom",
        name: "Custom Workflow",
        description: "Build your own workflow from scratch",
        steps: [],
        category: "custom"
      }
    ]

    json(conn, templates)
  end

  # POST /api/wizard/workflow/create - Create a new workflow
  def wizard_workflow_create(conn, params) do
    name = params["name"]
    template = params["template"] || "custom"
    description = params["description"] || ""
    config = params["config"] || %{}
    schedule = params["schedule"] || "manual"
    batch_size = params["batch_size"] || 100
    notify = params["notify"] || false

    if is_nil(name) do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Workflow name is required"})
    else
      workflow_id = "wf_#{generate_id()}"

      workflow = Zixir.Workflow.new(name, %{config: config})

      {workflow, step_count} = case template do
        "invoice-processing" ->
          {workflow
           |> Zixir.Workflow.add_step("scan_inbox", &invoice_scan_inbox/2)
           |> Zixir.Workflow.add_step("extract_data", &invoice_extract_data/2, depends_on: ["scan_inbox"])
           |> Zixir.Workflow.add_step("validate_amount", &invoice_validate_amount/2, depends_on: ["extract_data"])
           |> Zixir.Workflow.add_step("save_to_erp", &invoice_save_erp/2, depends_on: ["validate_amount"]),
           4}

        "document-classification" ->
          {workflow
           |> Zixir.Workflow.add_step("monitor_folder", &doc_monitor_folder/2)
           |> Zixir.Workflow.add_step("classify", &doc_classify/2, depends_on: ["monitor_folder"])
           |> Zixir.Workflow.add_step("sort_by_type", &doc_sort/2, depends_on: ["classify"]),
           3}

        "data-pipeline" ->
          source_conn = config["source-connection"] || "default"
          dest_conn = config["dest-connection"] || "default"
          {workflow
           |> Zixir.Workflow.add_step("extract", &data_pipeline_extract/2, depends_on: [], config: %{connection: source_conn})
           |> Zixir.Workflow.add_step("transform", &data_pipeline_transform/2, depends_on: ["extract"])
           |> Zixir.Workflow.add_step("load", &data_pipeline_load/2, depends_on: ["transform"], config: %{connection: dest_conn}),
           3}

        "ai-analysis" ->
          ai_func = config["ai-function"] || "classify"
          {workflow
           |> Zixir.Workflow.add_step("fetch_data", &ai_fetch_data/2)
           |> Zixir.Workflow.add_step("ai_processing", &ai_processing/2, depends_on: ["fetch_data"], config: %{function: ai_func})
           |> Zixir.Workflow.add_step("save_results", &ai_save_results/2, depends_on: ["ai_processing"]),
           3}

        "order-processing" ->
          {workflow
           |> Zixir.Workflow.add_step("receive_order", &order_receive/2)
           |> Zixir.Workflow.add_step("validate_order", &order_validate/2, depends_on: ["receive_order"])
           |> Zixir.Workflow.add_step("check_inventory", &order_check_inventory/2, depends_on: ["validate_order"])
           |> Zixir.Workflow.add_step("process_payment", &order_process_payment/2, depends_on: ["check_inventory"])
           |> Zixir.Workflow.add_step("fulfill_order", &order_fulfill/2, depends_on: ["process_payment"]),
           5}

        "support-triage" ->
          {workflow
           |> Zixir.Workflow.add_step("new_ticket", &support_new_ticket/2)
           |> Zixir.Workflow.add_step("classify_priority", &support_classify/2, depends_on: ["new_ticket"])
           |> Zixir.Workflow.add_step("route_team", &support_route/2, depends_on: ["classify_priority"]),
           3}

        "data-validation" ->
          {workflow
           |> Zixir.Workflow.add_step("load_data", &validation_load/2)
           |> Zixir.Workflow.add_step("ai_validation", &validation_ai/2, depends_on: ["load_data"])
           |> Zixir.Workflow.add_step("report_issues", &validation_report/2, depends_on: ["ai_validation"])
           |> Zixir.Workflow.add_step("clean_data", &validation_clean/2, depends_on: ["ai_validation"]),
           4}

        "data_pipeline" ->
          {workflow
           |> Zixir.Workflow.add_step("extract", &data_pipeline_extract/2)
           |> Zixir.Workflow.add_step("transform", &data_pipeline_transform/2)
           |> Zixir.Workflow.add_step("validate", &data_pipeline_validate/2)
           |> Zixir.Workflow.add_step("load", &data_pipeline_load/2),
           4}

        "ai_analysis" ->
          {workflow
           |> Zixir.Workflow.add_step("fetch_data", &ai_fetch_data/2)
           |> Zixir.Workflow.add_step("preprocess", &ai_preprocess/2)
           |> Zixir.Workflow.add_step("ai_call", &ai_call/2)
           |> Zixir.Workflow.add_step("postprocess", &ai_postprocess/2)
           |> Zixir.Workflow.add_step("save_results", &ai_save_results/2),
           5}

        "order_processing" ->
          {workflow
           |> Zixir.Workflow.add_step("validate_order", &order_validate/2)
           |> Zixir.Workflow.add_step("check_inventory", &order_check_inventory/2)
           |> Zixir.Workflow.add_step("process_payment", &order_process_payment/2)
           |> Zixir.Workflow.add_step("fulfill_order", &order_fulfill/2),
           4}

        _ ->
          {workflow, 0}
      end

      workflow_config = %{
        id: workflow_id,
        name: name,
        template: template,
        description: description,
        config: config,
        schedule: schedule,
        batch_size: batch_size,
        notify: notify,
        step_count: step_count,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        status: "created"
      }

      case Zixir.Cache.put("workflow:#{workflow_id}", workflow_config, persistent: true) do
        :ok ->
          json(conn, %{
            status: "created",
            id: workflow_id,
            message: "Workflow '#{name}' created successfully with #{step_count} steps",
            step_count: step_count
          })

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{status: "error", message: "Failed to save workflow: #{inspect(reason)}"})
      end
    end
  end

  # ============================================================================
  # HELPER FUNCTIONS
  # ============================================================================

  defp missing_connection_params?(host, database, username, password) do
    is_nil(host) or host == "" or
    is_nil(database) or database == "" or
    is_nil(username) or username == "" or
    is_nil(password) or password == ""
  end

  defp parse_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_port(port), do: port

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(value), do: value

  defp generate_id do
    :os.system_time(:millisecond)
    |> Integer.to_string(36)
    |> String.downcase()
  end

  # ============================================================================
  # WORKFLOW STEP IMPLEMENTATIONS
  # ============================================================================

  # Data Pipeline Steps
  defp data_pipeline_extract(state, _step_name), do: {:ok, Map.put(state, :extracted, true)}
  defp data_pipeline_transform(state, _step_name), do: {:ok, Map.put(state, :transformed, true)}
  defp data_pipeline_validate(state, _step_name), do: {:ok, Map.put(state, :validated, true)}
  defp data_pipeline_load(state, _step_name), do: {:ok, Map.put(state, :loaded, true)}

  # AI Analysis Steps
  defp ai_fetch_data(state, _step_name), do: {:ok, Map.put(state, :data_fetched, true)}
  defp ai_preprocess(state, _step_name), do: {:ok, Map.put(state, :preprocessed, true)}
  defp ai_call(state, _step_name), do: {:ok, Map.put(state, :ai_called, true)}
  defp ai_postprocess(state, _step_name), do: {:ok, Map.put(state, :postprocessed, true)}
  defp ai_save_results(state, _step_name), do: {:ok, Map.put(state, :results_saved, true)}

  # Order Processing Steps
  defp order_validate(state, _step_name), do: {:ok, Map.put(state, :order_valid, true)}
  defp order_check_inventory(state, _step_name), do: {:ok, Map.put(state, :inventory_checked, true)}
  defp order_process_payment(state, _step_name), do: {:ok, Map.put(state, :payment_processed, true)}
  defp order_fulfill(state, _step_name), do: {:ok, Map.put(state, :order_fulfilled, true)}

  # Invoice Processing Steps
  defp invoice_scan_inbox(state, _step_name), do: {:ok, Map.put(state, :inbox_scanned, true)}
  defp invoice_extract_data(state, _step_name), do: {:ok, Map.put(state, :data_extracted, true)}
  defp invoice_validate_amount(state, _step_name), do: {:ok, Map.put(state, :amount_validated, true)}
  defp invoice_save_erp(state, _step_name), do: {:ok, Map.put(state, :saved_to_erp, true)}

  # Document Classification Steps
  defp doc_monitor_folder(state, _step_name), do: {:ok, Map.put(state, :folder_monitored, true)}
  defp doc_classify(state, _step_name), do: {:ok, Map.put(state, :document_classified, true)}
  defp doc_sort(state, _step_name), do: {:ok, Map.put(state, :documents_sorted, true)}

  # Support Triage Steps
  defp support_new_ticket(state, _step_name), do: {:ok, Map.put(state, :ticket_received, true)}
  defp support_classify(state, _step_name), do: {:ok, Map.put(state, :priority_classified, true)}
  defp support_route(state, _step_name), do: {:ok, Map.put(state, :ticket_routed, true)}

  # Data Validation Steps
  defp validation_load(state, _step_name), do: {:ok, Map.put(state, :data_loaded, true)}
  defp validation_ai(state, _step_name), do: {:ok, Map.put(state, :validated_by_ai, true)}
  defp validation_report(state, _step_name), do: {:ok, Map.put(state, :issues_reported, true)}
  defp validation_clean(state, _step_name), do: {:ok, Map.put(state, :data_cleaned, true)}

  # Order Processing (Updated) Steps
  defp order_receive(state, _step_name), do: {:ok, Map.put(state, :order_received, true)}

  # AI Analysis Steps
  defp ai_processing(state, _step_name), do: {:ok, Map.put(state, :ai_processed, true)}

  # ============================================================================
  # FEATURE 1: WORKFLOW EXECUTION & MONITORING
  # ============================================================================

  # GET /api/workflow/:id/logs - Get workflow logs
  def workflow_logs(conn, %{"id" => id}) do
    logs = fetch_workflow_logs(id)
    json(conn, %{workflow_id: id, logs: logs})
  end

  # GET /api/workflow/:id/logs/stream - Stream workflow logs (Server-Sent Events)
  def workflow_logs_stream(conn, %{"id" => id}) do
    conn = 
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> send_chunked(200)

    # Simulate streaming logs
    logs = fetch_workflow_logs(id)
    
    Enum.each(logs, fn log ->
      data = Jason.encode!(%{type: "log", data: log})
      chunk(conn, "data: #{data}\n\n")
      Process.sleep(500)
    end)

    chunk(conn, "data: #{Jason.encode!(%{type: "complete"})}\n\n")
    conn
  end

  # GET /api/workflow/:id/steps - Get step-by-step execution status
  def workflow_steps(conn, %{"id" => id}) do
    steps = [
      %{step: 1, name: "Initialize", status: "completed", duration_ms: 120, output: "Ready"},
      %{step: 2, name: "Validate Input", status: "completed", duration_ms: 340, output: "Valid"},
      %{step: 3, name: "Process Data", status: "running", duration_ms: 2500, output: "Processing..."},
      %{step: 4, name: "Transform", status: "pending", duration_ms: nil, output: nil},
      %{step: 5, name: "Save Results", status: "pending", duration_ms: nil, output: nil}
    ]
    
    json(conn, %{workflow_id: id, steps: steps, progress: 45})
  end

  # GET /api/workflow/:id/history - Get workflow run history
  def workflow_history(conn, %{"id" => id}) do
    history = [
      %{
        run_id: "run_001",
        started_at: DateTime.utc_now() |> DateTime.add(-86400) |> DateTime.to_iso8601(),
        completed_at: DateTime.utc_now() |> DateTime.add(-86000) |> DateTime.to_iso8601(),
        status: "completed",
        duration_seconds: 400,
        triggered_by: "schedule"
      },
      %{
        run_id: "run_002",
        started_at: DateTime.utc_now() |> DateTime.add(-43200) |> DateTime.to_iso8601(),
        completed_at: DateTime.utc_now() |> DateTime.add(-42800) |> DateTime.to_iso8601(),
        status: "completed",
        duration_seconds: 400,
        triggered_by: "manual"
      },
      %{
        run_id: "run_003",
        started_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
        status: "running",
        duration_seconds: nil,
        triggered_by: "manual"
      }
    ]
    
    json(conn, %{workflow_id: id, history: history, total_runs: 47})
  end

  # GET /api/workflow/:id/history/:run_id - Get specific run details
  def workflow_run_detail(conn, %{"id" => id, "run_id" => run_id}) do
    detail = %{
      run_id: run_id,
      workflow_id: id,
      started_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
      completed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      status: "completed",
      duration_seconds: 245,
      triggered_by: "manual",
      steps: [
        %{name: "Initialize", status: "completed", duration_ms: 120, logs: ["Starting workflow...", "Initialized successfully"]},
        %{name: "Process", status: "completed", duration_ms: 3400, logs: ["Processing data...", "Processing complete"]},
        %{name: "Save", status: "completed", duration_ms: 890, logs: ["Saving results...", "Saved to database"]}
      ]
    }
    
    json(conn, detail)
  end

  # POST /api/workflow/:id/pause - Pause a running workflow
  def workflow_pause(conn, %{"id" => id}) do
    # In real implementation, this would pause the workflow process
    json(conn, %{status: "paused", workflow_id: id, message: "Workflow paused successfully"})
  end

  # POST /api/workflow/:id/resume - Resume a paused workflow
  def workflow_resume(conn, %{"id" => id}) do
    json(conn, %{status: "resumed", workflow_id: id, message: "Workflow resumed successfully"})
  end

  # POST /api/workflow/:id/clone - Clone an existing workflow
  def workflow_clone(conn, %{"id" => id}) do
    new_id = "wf_#{generate_id()}"
    json(conn, %{
      status: "cloned",
      original_id: id,
      new_id: new_id,
      message: "Workflow cloned successfully",
      new_name: "Copy of Workflow"
    })
  end

  defp fetch_workflow_logs(id) do
    [
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(), level: "info", message: "Workflow #{id} started"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3595) |> DateTime.to_iso8601(), level: "info", message: "Step 1: Initializing..."},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3594) |> DateTime.to_iso8601(), level: "info", message: "Step 1: Complete (120ms)"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3593) |> DateTime.to_iso8601(), level: "info", message: "Step 2: Validating input data"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3590) |> DateTime.to_iso8601(), level: "info", message: "Step 2: Complete (340ms)"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3589) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing data..."},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3500) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing batch 1/5"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3400) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing batch 2/5"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3300) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing batch 3/5"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3200) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing batch 4/5"},
      %{timestamp: DateTime.utc_now() |> DateTime.add(-3100) |> DateTime.to_iso8601(), level: "info", message: "Step 3: Processing batch 5/5"},
      %{timestamp: DateTime.utc_now() |> DateTime.to_iso8601(), level: "info", message: "Step 3: Complete (2500ms)"}
    ]
  end

  # ============================================================================
  # FEATURE 2: SQL QUERY EXPLORER
  # ============================================================================

  # POST /api/query/execute - Execute SQL query on a connection
  def query_execute(conn, params) do
    connection_id = params["connection_id"]
    query = params["query"]
    
    if is_nil(connection_id) or is_nil(query) or query == "" do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Connection ID and query are required"})
    else
      # Mock query execution
      results = %{
        columns: ["id", "name", "email", "created_at"],
        rows: [
          [1, "John Doe", "john@example.com", "2024-01-15T10:00:00Z"],
          [2, "Jane Smith", "jane@example.com", "2024-01-15T11:00:00Z"],
          [3, "Bob Wilson", "bob@example.com", "2024-01-15T12:00:00Z"]
        ],
        row_count: 3,
        execution_time_ms: 45
      }
      
      # Store query in history
      query_record = %{
        id: "query_#{generate_id()}",
        connection_id: connection_id,
        query: query,
        executed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        row_count: results.row_count,
        execution_time_ms: results.execution_time_ms
      }
      Zixir.Cache.put("query_history:#{query_record.id}", query_record, persistent: true)
      
      json(conn, %{status: "success", results: results, query_id: query_record.id})
    end
  end

  # GET /api/query/connections/:id/tables - List tables in a connection
  def query_tables(conn, %{"id" => id}) do
    tables = [
      %{name: "users", row_count: 15420, size_mb: 45},
      %{name: "orders", row_count: 89341, size_mb: 128},
      %{name: "products", row_count: 5234, size_mb: 23},
      %{name: "categories", row_count: 156, size_mb: 2}
    ]
    
    json(conn, %{connection_id: id, tables: tables})
  end

  # GET /api/query/connections/:id/tables/:table/columns - List columns in a table
  def query_columns(conn, %{"id" => id, "table" => table}) do
    columns = [
      %{name: "id", type: "INTEGER", nullable: false, primary_key: true},
      %{name: "name", type: "VARCHAR(255)", nullable: false, primary_key: false},
      %{name: "email", type: "VARCHAR(255)", nullable: true, primary_key: false},
      %{name: "created_at", type: "TIMESTAMP", nullable: false, primary_key: false}
    ]
    
    json(conn, %{connection_id: id, table: table, columns: columns})
  end

  # POST /api/query/export/csv - Export query results to CSV
  def query_export_csv(conn, params) do
    query_id = params["query_id"]
    
    # In real implementation, fetch results and convert to CSV
    csv_data = "id,name,email,created_at\n1,John Doe,john@example.com,2024-01-15T10:00:00Z\n2,Jane Smith,jane@example.com,2024-01-15T11:00:00Z\n3,Bob Wilson,bob@example.com,2024-01-15T12:00:00Z"
    
    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"query_results_#{query_id}.csv\"")
    |> send_resp(200, csv_data)
  end

  # ============================================================================
  # ============================================================================
  # FEATURE 3: VECTOR SEARCH INTERFACE - ENHANCED
  # ============================================================================

  # POST /api/vector-search - Search vectors by text with pagination, sorting, filtering
  def vector_search(conn, params) do
    collection = params["collection"] || "default"
    query = params["query"]
    top_k = parse_int(params["top_k"]) || 10

    # Pagination
    page = parse_int(params["page"]) || 1
    limit = parse_int(params["limit"]) || top_k
    offset = (page - 1) * limit

    # Sorting
    sort_by = params["sort_by"] || "score"
    sort_order = params["sort_order"] || "desc"

    # Filtering
    filter_by = params["filter_by"]
    filter_value = params["filter_value"]
    date_from = params["date_from"]
    date_to = params["date_to"]

    if is_nil(query) or query == "" do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Query text is required"})
    else
      # Mock search results with more data for pagination testing
      all_results = [
        %{id: "doc_001", text: "Introduction to machine learning concepts. Machine learning is a subset of artificial intelligence that focuses on building systems that learn from data.", score: 0.92, metadata: %{category: "tutorial", source: "wiki"}, created_at: "2024-01-15T10:00:00Z"},
        %{id: "doc_002", text: "Deep learning fundamentals explained. Neural networks are inspired by the human brain and consist of interconnected nodes.", score: 0.88, metadata: %{category: "tutorial", source: "course"}, created_at: "2024-01-14T09:00:00Z"},
        %{id: "doc_003", text: "Neural network architectures overview. Common architectures include CNNs, RNNs, Transformers, and GANs.", score: 0.85, metadata: %{category: "reference", source: "paper"}, created_at: "2024-01-13T08:00:00Z"},
        %{id: "doc_004", text: "Training models with PyTorch. PyTorch provides dynamic computational graphs and intuitive debugging.", score: 0.81, metadata: %{category: "guide", source: "docs"}, created_at: "2024-01-12T07:00:00Z"},
        %{id: "doc_005", text: "Machine learning best practices. Always split data into training, validation, and test sets.", score: 0.78, metadata: %{category: "best_practices", source: "blog"}, created_at: "2024-01-11T06:00:00Z"},
        %{id: "doc_006", text: "Natural language processing techniques. NLP enables computers to understand human language through various algorithms.", score: 0.75, metadata: %{category: "tutorial", source: "wiki"}, created_at: "2024-01-10T05:00:00Z"},
        %{id: "doc_007", text: "Computer vision applications. Image classification, object detection, and segmentation are key computer vision tasks.", score: 0.72, metadata: %{category: "reference", source: "course"}, created_at: "2024-01-09T04:00:00Z"},
        %{id: "doc_008", text: "Reinforcement learning basics. Agents learn optimal behaviors through environmental rewards and penalties.", score: 0.69, metadata: %{category: "tutorial", source: "paper"}, created_at: "2024-01-08T03:00:00Z"},
        %{id: "doc_009", text: "Model evaluation metrics. Accuracy, precision, recall, F1-score, and AUC-ROC are common evaluation metrics.", score: 0.66, metadata: %{category: "guide", source: "docs"}, created_at: "2024-01-07T02:00:00Z"},
        %{id: "doc_010", text: "Feature engineering importance. Good features can significantly improve model performance.", score: 0.63, metadata: %{category: "best_practices", source: "blog"}, created_at: "2024-01-06T01:00:00Z"},
        %{id: "doc_011", text: "Hyperparameter tuning strategies. Grid search, random search, and Bayesian optimization are common approaches.", score: 0.60, metadata: %{category: "guide", source: "docs"}, created_at: "2024-01-05T12:00:00Z"},
        %{id: "doc_012", text: "Ensemble methods overview. Bagging, boosting, and stacking combine multiple models for better performance.", score: 0.57, metadata: %{category: "reference", source: "paper"}, created_at: "2024-01-04T11:00:00Z"},
        %{id: "doc_013", text: "Data preprocessing techniques. Normalization, standardization, and encoding are essential preprocessing steps.", score: 0.54, metadata: %{category: "tutorial", source: "course"}, created_at: "2024-01-03T10:00:00Z"},
        %{id: "doc_014", text: "Regularization methods prevent overfitting. L1, L2, and dropout are common regularization techniques.", score: 0.51, metadata: %{category: "tutorial", source: "wiki"}, created_at: "2024-01-02T09:00:00Z"},
        %{id: "doc_015", text: "Gradient descent optimization. Stochastic, batch, and mini-batch variants optimize model parameters.", score: 0.48, metadata: %{category: "reference", source: "paper"}, created_at: "2024-01-01T08:00:00Z"}
      ]

      # Apply filters
      filtered_results = all_results
        |> filter_by_field(filter_by, filter_value)
        |> filter_by_date(date_from, date_to)

      # Apply sorting
      sorted_results = case sort_by do
        "score" -> sort_by_field(filtered_results, :score, sort_order)
        "date" -> sort_by_field(filtered_results, :date, sort_order)
        "relevance" -> sort_by_field(filtered_results, :score, "desc")
        _ -> sort_by_field(filtered_results, :score, "desc")
      end

      # Apply pagination
      total_count = length(sorted_results)
      total_pages = ceil(total_count / limit)
      paginated_results = Enum.slice(sorted_results, offset, limit)

      has_next = page < total_pages
      has_prev = page > 1

      json(conn, %{
        status: "success",
        query: query,
        collection: collection,
        results: paginated_results,
        pagination: %{
          page: page,
          limit: limit,
          total_count: total_count,
          total_pages: total_pages,
          has_next: has_next,
          has_prev: has_prev
        },
        sort: %{
          by: sort_by,
          order: sort_order
        },
        filters: %{
          filter_by: filter_by,
          filter_value: filter_value,
          date_from: date_from,
          date_to: date_to
        },
        search_time_ms: 45
      })
    end
  end

  defp filter_by_field(results, nil, _), do: results
  defp filter_by_field(results, "", _), do: results
  defp filter_by_field(results, filter_by, filter_value) do
    Enum.filter(results, fn result ->
      meta = result.metadata || %{}
      field_value = meta[filter_by]
      if field_value, do: String.downcase(field_value) == String.downcase(filter_value), else: false
    end)
  end

  defp filter_by_date(results, nil, _), do: results
  defp filter_by_date(results, _, nil), do: results
  defp filter_by_date(results, date_from, date_to) do
    from_dt = DateTime.from_iso8601!(date_from)
    to_dt = DateTime.from_iso8601!(date_to)
    Enum.filter(results, fn result ->
      result_dt = DateTime.from_iso8601!(result.created_at)
      DateTime.compare(result_dt, from_dt) in [:gt, :eq] and DateTime.compare(result_dt, to_dt) in [:lt, :eq]
    end)
  end

  defp sort_by_field(results, :score, order) do
    comparator = fn a, b -> a.score >= b.score end
    case order do
      "asc" -> Enum.sort_by(results, & &1.score, :asc)
      _ -> Enum.sort_by(results, & &1.score, :desc)
    end
  end

  defp sort_by_field(results, :date, order) do
    case order do
      "asc" -> Enum.sort_by(results, & &1.created_at, :asc)
      _ -> Enum.sort_by(results, & &1.created_at, :desc)
    end
  end

  # GET /api/vector/documents/:id - Get full document content
  def vector_get_document(conn, %{"id" => id}) do
    # Mock document lookup
    mock_docs = %{
      "doc_001" => %{id: "doc_001", text: "Introduction to machine learning concepts. Machine learning is a subset of artificial intelligence that focuses on building systems that learn from data. It enables computers to learn patterns from experience without being explicitly programmed. The field encompasses various approaches including supervised learning, unsupervised learning, and reinforcement learning.", metadata: %{category: "tutorial", source: "wiki", author: "John Doe"}, created_at: "2024-01-15T10:00:00Z"},
      "doc_002" => %{id: "doc_002", text: "Deep learning fundamentals explained. Neural networks are inspired by the human brain and consist of interconnected nodes called neurons. Each neuron receives input, applies weights, and passes through an activation function. Deep learning uses networks with multiple hidden layers to learn complex patterns in data.", metadata: %{category: "tutorial", source: "course", author: "Jane Smith"}, created_at: "2024-01-14T09:00:00Z"},
      "doc_003" => %{id: "doc_003", text: "Neural network architectures overview. Common architectures include Convolutional Neural Networks (CNNs) for image processing, Recurrent Neural Networks (RNNs) for sequential data, Transformers for attention-based tasks, and Generative Adversarial Networks (GANs) for generative tasks.", metadata: %{category: "reference", source: "paper", author: "Research Team"}, created_at: "2024-01-13T08:00:00Z"}
    }

    case Map.get(mock_docs, id) do
      nil ->
        conn
        |> put_status(404)
        |> json(%{status: "error", message: "Document not found"})
      doc ->
        json(conn, %{status: "success", document: doc})
    end
  end

  # GET /api/vector/search/history - Get filter options for a collection
  def vector_filter_options(conn, params) do
    collection = params["collection"] || "default"

    # Mock filter options based on available metadata
    filter_options = %{
      categories: ["tutorial", "reference", "guide", "best_practices"],
      sources: ["wiki", "course", "paper", "docs", "blog"],
      date_range: %{
        earliest: "2024-01-01T00:00:00Z",
        latest: "2024-01-31T23:59:59Z"
      }
    }

    json(conn, %{status: "success", collection: collection, filters: filter_options})
  end

  # POST /api/vector/embed - Embed and store a document
  def vector_embed(conn, params) do
    collection = params["collection"] || "default"
    text = params["text"]
    metadata = params["metadata"] || %{}
    
    if is_nil(text) or text == "" do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Text content is required"})
    else
      doc_id = "doc_#{generate_id()}"
      
      # In real implementation, this would generate embeddings and store them
      document = %{
        id: doc_id,
        text: text,
        collection: collection,
        metadata: metadata,
        created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        embedding_dimensions: 1536
      }
      
      Zixir.Cache.put("vector_doc:#{doc_id}", document, persistent: true)
      
      json(conn, %{
        status: "embedded",
        doc_id: doc_id,
        collection: collection,
        text_preview: String.slice(text, 0, 100) <> "...",
        message: "Document embedded successfully"
      })
    end
  end

  # GET /api/vector/collections - List vector collections
  def vector_collections(conn, _params) do
    collections = [
      %{
        name: "default",
        vector_count: 15420,
        dimensions: 1536,
        size_mb: 245,
        last_updated: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601()
      },
      %{
        name: "documentation",
        vector_count: 3421,
        dimensions: 1536,
        size_mb: 54,
        last_updated: DateTime.utc_now() |> DateTime.add(-86400) |> DateTime.to_iso8601()
      },
      %{
        name: "knowledge_base",
        vector_count: 8934,
        dimensions: 1536,
        size_mb: 142,
        last_updated: DateTime.utc_now() |> DateTime.add(-43200) |> DateTime.to_iso8601()
      }
    ]
    
    json(conn, %{collections: collections, total_collections: length(collections)})
  end

  # GET /api/vector/collections/:name/stats - Get collection statistics
  def vector_collection_stats(conn, %{"name" => name}) do
    stats = %{
      name: name,
      vector_count: 15420,
      dimensions: 1536,
      size_mb: 245,
      avg_query_time_ms: 12.5,
      index_type: "HNSW",
      created_at: "2024-01-01T00:00:00Z",
      last_updated: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    json(conn, stats)
  end

  # ============================================================================
  # FEATURE 4: WORKFLOW TEMPLATES LIBRARY
  # ============================================================================

  # GET /api/workflow-templates - Get extended template library
  def workflow_templates_library(conn, _params) do
    templates = [
      %{
        id: "data_sync",
        name: "Data Sync",
        description: "Synchronize data between two databases",
        category: "data",
        difficulty: "beginner",
        popularity: 2453,
        steps_count: 4,
        estimated_duration: "5-10 min",
        tags: ["etl", "sync", "database"]
      },
      %{
        id: "report_generation",
        name: "Report Generation",
        description: "Generate daily/weekly reports from database",
        category: "automation",
        difficulty: "beginner",
        popularity: 1821,
        steps_count: 5,
        estimated_duration: "2-5 min",
        tags: ["reports", "automation", "email"]
      },
      %{
        id: "email_alerts",
        name: "Email Alerts",
        description: "Send email notifications based on conditions",
        category: "notifications",
        difficulty: "intermediate",
        popularity: 1534,
        steps_count: 3,
        estimated_duration: "1-2 min",
        tags: ["email", "alerts", "notifications"]
      },
      %{
        id: "data_backup",
        name: "Data Backup",
        description: "Automated database backup workflow",
        category: "maintenance",
        difficulty: "beginner",
        popularity: 1245,
        steps_count: 3,
        estimated_duration: "10-30 min",
        tags: ["backup", "maintenance", "safety"]
      },
      %{
        id: "api_integration",
        name: "API Integration",
        description: "Fetch data from external APIs and store locally",
        category: "integration",
        difficulty: "intermediate",
        popularity: 987,
        steps_count: 4,
        estimated_duration: "5-15 min",
        tags: ["api", "integration", "data"]
      },
      %{
        id: "ai_summarization",
        name: "AI Summarization",
        description: "Summarize long documents using AI",
        category: "ai",
        difficulty: "advanced",
        popularity: 756,
        steps_count: 4,
        estimated_duration: "2-5 min",
        tags: ["ai", "llm", "summarization"]
      }
    ]
    
    json(conn, %{templates: templates, total: length(templates)})
  end

  # POST /api/workflow-templates/:template_id/deploy - Deploy a template
  def workflow_template_deploy(conn, %{"template_id" => template_id}) do
    params = conn.params
    name = params["name"] || "#{template_id}_workflow"
    
    workflow_id = "wf_#{generate_id()}"
    
    # Create workflow based on template
    workflow_config = %{
      id: workflow_id,
      name: name,
      template_id: template_id,
      status: "created",
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    Zixir.Cache.put("workflow:#{workflow_id}", workflow_config, persistent: true)
    
    json(conn, %{
      status: "deployed",
      workflow_id: workflow_id,
      template_id: template_id,
      message: "Template deployed successfully"
    })
  end

  # ============================================================================
  # FEATURE 5: SIMPLE SCHEDULER
  # ============================================================================

  # GET /api/workflow/:id/schedule - Get workflow schedule
  def workflow_schedule_get(conn, %{"id" => id}) do
    # Check if schedule exists in cache
    case Zixir.Cache.get("schedule:#{id}") do
      nil ->
        json(conn, %{
          workflow_id: id,
          scheduled: false,
          message: "No schedule configured"
        })
      
      schedule ->
        json(conn, %{
          workflow_id: id,
          scheduled: true,
          schedule: schedule
        })
    end
  end

  # POST /api/workflow/:id/schedule - Set workflow schedule
  def workflow_schedule_set(conn, %{"id" => id}) do
    params = conn.params
    frequency = params["frequency"] # "hourly", "daily", "weekly", "custom"
    time = params["time"] # For daily/weekly: "14:30"
    timezone = params["timezone"] || "UTC"
    enabled = params["enabled"] != false
    
    # Convert frequency to cron expression
    cron_expression = case frequency do
      "hourly" -> "0 * * * *"
      "daily" -> "0 #{time || "00:00"}"
      "weekly" -> "0 #{time || "00:00"} * * 1" # Monday
      "custom" -> params["cron"] || "0 0 * * *"
      _ -> "0 0 * * *" # Default daily at midnight
    end
    
    schedule = %{
      workflow_id: id,
      frequency: frequency,
      time: time,
      timezone: timezone,
      cron_expression: cron_expression,
      enabled: enabled,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      next_run: calculate_next_run(cron_expression)
    }
    
    Zixir.Cache.put("schedule:#{id}", schedule, persistent: true)
    
    json(conn, %{
      status: "scheduled",
      workflow_id: id,
      schedule: schedule,
      message: "Workflow scheduled successfully"
    })
  end

  # DELETE /api/workflow/:id/schedule - Remove workflow schedule
  def workflow_schedule_delete(conn, %{"id" => id}) do
    Zixir.Cache.delete("schedule:#{id}")
    
    json(conn, %{
      status: "unscheduled",
      workflow_id: id,
      message: "Schedule removed successfully"
    })
  end

  # GET /api/schedules - List all scheduled workflows
  def schedules_list(conn, _params) do
    # In real implementation, query all schedule:* keys from cache
    schedules = [
      %{
        workflow_id: "wf_001",
        workflow_name: "Daily Report",
        frequency: "daily",
        time: "06:00",
        timezone: "UTC",
        enabled: true,
        next_run: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()
      },
      %{
        workflow_id: "wf_002",
        workflow_name: "Data Sync",
        frequency: "hourly",
        time: nil,
        timezone: "UTC",
        enabled: true,
        next_run: DateTime.utc_now() |> DateTime.add(1800) |> DateTime.to_iso8601()
      }
    ]
    
    json(conn, %{schedules: schedules, total: length(schedules)})
  end

  # ============================================================================
  # FILE & FOLDER UPLOAD ENDPOINTS
  # ============================================================================

  # POST /api/vector/upload - Upload and process a single file
  def vector_upload(conn, params) do
    collection = params["collection"] || "default"
    metadata = params["metadata"] || %{}

    case extract_uploaded_file(conn) do
      {:ok, filename, content} ->
        case Zixir.FileProcessor.extract_binary(content, filename, collection: collection) do
          {:ok, text, file_metadata} ->
            merged_metadata = Map.merge(file_metadata, metadata)

            # Generate document ID
            doc_id = "doc_#{generate_id()}_#{file_metadata.filename}"

            # Create document structure
            document = %{
              id: doc_id,
              text: text,
              collection: collection,
              metadata: merged_metadata,
              created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
              embedding_dimensions: 1536
            }

            # Store in cache
            Zixir.Cache.put("vector_doc:#{doc_id}", document, persistent: true)

            json(conn, %{
              status: "uploaded",
              doc_id: doc_id,
              collection: collection,
              filename: file_metadata.filename,
              size: file_metadata.size_formatted,
              text_preview: String.slice(text, 0, 150) <> "...",
              message: "File uploaded and processed successfully"
            })

          {:error, reason} ->
            conn
            |> put_status(400)
            |> json(%{status: "error", message: reason})
        end

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{status: "error", message: reason})
    end
  end

  # POST /api/vector/upload/batch - Upload multiple files at once
  def vector_upload_batch(conn, params) do
    collection = params["collection"] || "default"

    # Extract files from multipart
    files = extract_all_uploads(conn)

    if length(files) == 0 do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "No files provided"})
    else
      results =
        Enum.map(files, fn {filename, content} ->
          case Zixir.FileProcessor.extract_binary(content, filename, collection: collection) do
            {:ok, text, file_metadata} ->
              doc_id = "doc_#{generate_id()}_#{file_metadata.filename}"

              document = %{
                id: doc_id,
                text: text,
                collection: collection,
                metadata: file_metadata,
                created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                embedding_dimensions: 1536
              }

              Zixir.Cache.put("vector_doc:#{doc_id}", document, persistent: true)

              %{filename: filename, doc_id: doc_id, status: "success", size: file_metadata.size_formatted}

            {:error, reason} ->
              %{filename: filename, status: "error", reason: reason}
          end
        end)

      successful = Enum.filter(results, &(&1.status == "success"))
      failed = Enum.filter(results, &(&1.status == "error"))

      json(conn, %{
        status: "batch_complete",
        collection: collection,
        total: length(results),
        successful: length(successful),
        failed: length(failed),
        results: results
      })
    end
  end

  # POST /api/vector/upload/folder - Process a folder (client scans, sends file paths)
  def vector_upload_folder(conn, params) do
    collection = params["collection"] || "default"
    folder_path = params["folder_path"]
    files = params["files"] || []

    if folder_path == "" and length(files) == 0 do
      conn
      |> put_status(400)
      |> json(%{status: "error", message: "Folder path or files list required"})
    else
      # If folder_path provided, server-side scan
      if folder_path != "" and File.exists?(folder_path) do
        case Zixir.FileProcessor.process_directory(folder_path, collection: collection) do
          {:ok, result} ->
            # Store all documents
            Enum.each(result.documents, fn doc ->
              doc_id = "doc_#{generate_id()}_#{Path.basename(doc.path)}"

              document = %{
                id: doc_id,
                text: doc.text,
                collection: collection,
                metadata: Map.merge(doc.metadata, %{folder_path: doc.path}),
                created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
                embedding_dimensions: 1536
              }

              Zixir.Cache.put("vector_doc:#{doc_id}", document, persistent: true)
            end)

            json(conn, %{
              status: "folder_processed",
              collection: collection,
              folder: folder_path,
              total_files: result.total,
              successful: result.successful,
              failed: result.failed,
              message: "Folder processed successfully"
            })

          {:error, reason} ->
            conn
            |> put_status(400)
            |> json(%{status: "error", message: reason})
        end
      else
        # Client-side file list provided
        json(conn, %{
          status: "received",
          collection: collection,
          files_count: length(files),
          message: "File list received - upload individual files"
        })
      end
    end
  end

  # GET /api/vector/upload/formats - Get supported file formats
  def vector_upload_formats(conn, _params) do
    json(conn, %{
      status: "success",
      max_file_size_bytes: Zixir.FileProcessor.max_file_size(),
      max_file_size_formatted: "25 MB",
      supported_extensions: Zixir.FileProcessor.supported_extensions(),
      supported_types: [
        %{
          extensions: [".txt", ".md", ".markdown"],
          description: "Plain text and Markdown documents"
        },
        %{
          extensions: [".json", ".yaml", ".yml", ".csv"],
          description: "Structured data formats"
        },
        %{
          extensions: [".html", ".htm"],
          description: "HTML documents"
        },
        %{
          extensions: [".pdf"],
          description: "PDF documents (text extraction)"
        },
        %{
          extensions: [".docx"],
          description: "Microsoft Word documents"
        }
      ]
    })
  end

  # Helper to extract single file from multipart upload
  defp extract_uploaded_file(conn) do
    case conn.params do
      %{'_files' => files} when is_list(files) ->
        # Phoenix 1.7+ format
        files
        |> Enum.find(&match?(%Plug.Upload{}, &1))
        |> handle_file_upload()

      %{'_uploads' => uploads} when is_map(uploads) ->
        # Alternative format
        uploads
        |> Map.values()
        |> Enum.find(&match?(%Plug.Upload{}, &1))
        |> handle_file_upload()

      _ ->
        # Try to get from body_params
        case conn.body_params do
          %{'_files' => files} when is_list(files) ->
            files
            |> Enum.find(&match?(%Plug.Upload{}, &1))
            |> handle_file_upload()

          _ ->
            # Check raw body for direct binary upload
            case read_body(conn) do
              {:ok, body, _} when byte_size(body) > 0 ->
                filename = get_filename(conn) || "uploaded_file.txt"
                {:ok, filename, body}

              _ ->
                {:error, "No file found in upload request"}
            end
        end
    end
  end

  defp handle_file_upload(nil), do: {:error, "No file found in upload"}

  defp handle_file_upload(%Plug.Upload{filename: filename, path: temp_path}) do
    case File.read(temp_path) do
      {:ok, content} ->
        # Clean up temp file
        File.rm(temp_path)
        {:ok, filename, content}

      {:error, reason} ->
        {:error, "Cannot read uploaded file: #{reason}"}
    end
  end

  # Extract all files from multipart
  defp extract_all_uploads(conn) do
    case conn.params do
      %{'_files' => files} when is_list(files) ->
        files
        |> Enum.filter(&match?(%Plug.Upload{}, &1))
        |> Enum.map(fn upload ->
          case File.read(upload.path) do
            {:ok, content} ->
              File.rm(upload.path)
              {upload.filename, content}

            _ ->
              {upload.filename, ""}
          end
        end)

      _ ->
        []
    end
  end

  defp get_filename(conn) do
    case get_req_header(conn, "content-disposition") do
      [header | _] ->
        case Regex.run(~r/filename="?([^";\n]+)"?/, header) do
          [_, filename] -> filename
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp calculate_next_run(_cron) do
    # Simplified - in real implementation, parse cron and calculate
    DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()
  end
end
