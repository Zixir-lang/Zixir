defmodule ZixirWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug ZixirWeb.Plugs.HTMX
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug Plug.Parsers,
      parsers: [:urlencoded, :multipart, :json],
      pass: ["*/*"],
      json_decoder: Jason
  end

  scope "/", ZixirWeb do
    pipe_through :browser

    get "/", DashboardController, :index
    get "/dashboard", DashboardController, :index
    
    # Workflows
    get "/workflows", WorkflowController, :index
    get "/workflows/wizard", WorkflowController, :wizard
    
    # Connections with Wizard
    get "/connections", ConnectionController, :index
    get "/connections/wizard", ConnectionController, :wizard
    
    # Vector DB with Wizard
    get "/vector-db", VectorController, :index
    get "/vector-db/wizard", VectorController, :wizard
    
    # AI Management
    get "/ai", AIController, :index
    get "/ai/playground", AIController, :playground
    
    get "/settings", SettingsController, :index
    
    # New Feature Routes
    # SQL Query Explorer
    get "/query", QueryController, :index
    
    # Vector Search
    get "/vector-search", VectorSearchController, :index
    
    # Workflow History & Logs
    get "/workflows/:id/logs", WorkflowController, :logs
    get "/workflows/:id/history", WorkflowController, :history
  end

  # SSE endpoints - no pipeline needed (bypasses content-type checks)
  scope "/api", ZixirWeb do
    get "/events", SSEController, :stream
    get "/events/:topic", SSEController, :stream_topic
  end

  scope "/api", ZixirWeb do
    pipe_through [:api]

    get "/metrics", APIController, :metrics
    get "/metrics/fragment", APIController, :metrics_fragment
    get "/workflows", APIController, :workflows
    get "/workflows/fragment", APIController, :workflows_fragment
    get "/workflow/:id", APIController, :workflow_detail
    post "/workflow/:id/start", APIController, :workflow_start
    post "/workflow/:id/stop", APIController, :workflow_stop
    post "/workflow/:id/retry", APIController, :workflow_retry
    get "/connections", APIController, :connections
    get "/connections/fragment", APIController, :connections_fragment
    get "/connections/dashboard-fragment", APIController, :connections_dashboard_fragment
    post "/connection/test", APIController, :connection_test
    post "/connection/add", APIController, :connection_add
    delete "/connection/:id", APIController, :connection_delete
    get "/vector-status", APIController, :vector_status
    get "/vector-status/fragment", APIController, :vector_status_fragment
    
    # Wizard API endpoints
    post "/wizard/connection/test", APIController, :wizard_connection_test
    post "/wizard/connection/create", APIController, :wizard_connection_create
    post "/wizard/vector-db/test", APIController, :wizard_vector_test
    post "/wizard/vector-db/create", APIController, :wizard_vector_create
    post "/wizard/workflow/create", APIController, :wizard_workflow_create
    get "/wizard/workflow/templates", APIController, :wizard_workflow_templates
    
    # Feature 1: Workflow Execution & Monitoring
    get "/workflow/:id/logs", APIController, :workflow_logs
    get "/workflow/:id/logs/stream", APIController, :workflow_logs_stream
    get "/workflow/:id/steps", APIController, :workflow_steps
    get "/workflow/:id/history", APIController, :workflow_history
    get "/workflow/:id/history/:run_id", APIController, :workflow_run_detail
    post "/workflow/:id/pause", APIController, :workflow_pause
    post "/workflow/:id/resume", APIController, :workflow_resume
    post "/workflow/:id/clone", APIController, :workflow_clone
    
    # Feature 2: SQL Query Explorer
    post "/query/execute", APIController, :query_execute
    get "/query/connections/:id/tables", APIController, :query_tables
    get "/query/connections/:id/tables/:table/columns", APIController, :query_columns
    post "/query/export/csv", APIController, :query_export_csv
    
    # Feature 3: Vector Search Interface
    post "/vector-search", APIController, :vector_search
    post "/vector/embed", APIController, :vector_embed
    get "/vector/collections", APIController, :vector_collections
    get "/vector/collections/:name/stats", APIController, :vector_collection_stats
    post "/vector/upload", APIController, :vector_upload
    post "/vector/upload/batch", APIController, :vector_upload_batch
    post "/vector/upload/folder", APIController, :vector_upload_folder
    get "/vector/upload/formats", APIController, :vector_upload_formats
    
    # Feature 4: Workflow Templates Library
    get "/workflow-templates", APIController, :workflow_templates_library
    post "/workflow-templates/:template_id/deploy", APIController, :workflow_template_deploy
    
    # Feature 5: Simple Scheduler
    get "/workflow/:id/schedule", APIController, :workflow_schedule_get
    post "/workflow/:id/schedule", APIController, :workflow_schedule_set
    delete "/workflow/:id/schedule", APIController, :workflow_schedule_delete
    get "/schedules", APIController, :schedules_list
    
    # AI Management API
    get "/ai/providers", AIController, :list_providers
    get "/ai/providers/:provider", AIController, :get_provider
    post "/ai/providers/:provider", AIController, :configure_provider
    delete "/ai/providers/:provider", AIController, :delete_provider
    post "/ai/providers/:provider/test", AIController, :test_provider
    get "/ai/usage", AIController, :get_usage
    get "/ai/budget", AIController, :get_budget
    post "/ai/budget", AIController, :set_budget
    get "/ai/alerts/check", AIController, :check_budget_alert
    post "/ai/test", AIController, :test_ai_function
    get "/ai/logs", AIController, :get_logs
    get "/ai/logs/fragment", AIController, :logs_fragment

    # Custom AI Providers
    post "/ai/custom", AIController, :configure_custom_provider
    get "/ai/custom", AIController, :list_custom_providers
    delete "/ai/custom/:provider_id", AIController, :delete_custom_provider
    post "/ai/custom/:provider_id/test", AIController, :test_custom_provider
  end
end
