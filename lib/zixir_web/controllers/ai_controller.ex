defmodule ZixirWeb.AIController do
  @moduledoc """
  Controller for AI Management Dashboard.

  Provides endpoints for:
  - AI provider configuration (OpenAI, Anthropic, Azure, Local)
  - Usage tracking and cost monitoring
  - Budget alerts and limits
  - AI testing playground
  - Error logs and debugging
  """

  use Phoenix.Controller, formats: [:html, :json]
  alias Zixir.AI.Config, as: AIConfig

  @supported_providers [:openai, :anthropic, :azure, :local]

  # ============================================================================
  # Dashboard Views
  # ============================================================================

  @doc """
  Main AI management page - shows provider configuration and usage overview.
  """
  def index(conn, _params) do
    providers = AIConfig.list_providers()
    budget = AIConfig.get_budget_status()
    usage = AIConfig.get_usage_stats()
    layout = if conn.assigns[:htmx_request], do: false, else: {ZixirWeb.LayoutView, "app.html"}
    conn
    |> put_view(ZixirWeb.AIView)
    |> render("index.html",
      providers: providers,
      budget: budget,
      usage: usage,
      layout: layout
    )
  end

  @doc """
  AI usage dashboard with charts and metrics.
  """
  def dashboard(conn, _params) do
    usage = AIConfig.get_usage_stats()
    budget = AIConfig.get_budget_status()
    providers = AIConfig.list_providers()
    
    conn
    |> put_view(ZixirWeb.AIView)
    |> render("dashboard.html",
      usage: usage,
      budget: budget,
      providers: providers
    )
  end

  @doc """
  AI testing playground for trying prompts.
  """
  def playground(conn, _params) do
    providers = AIConfig.list_providers()
    layout = if conn.assigns[:htmx_request], do: false, else: {ZixirWeb.LayoutView, "app.html"}
    conn
    |> put_view(ZixirWeb.AIView)
    |> render("playground.html", providers: providers, layout: layout)
  end

  # ============================================================================
  # API Endpoints
  # ============================================================================

  @doc """
  GET /api/ai/providers - List all configured AI providers.
  """
  def list_providers(conn, _params) do
    providers = AIConfig.list_providers()
    json(conn, %{providers: providers})
  end

  @doc """
  GET /api/ai/providers/:provider - Get specific provider configuration.
  """
  def get_provider(conn, %{"provider" => provider}) do
    provider_atom = String.to_atom(provider)
    
    case AIConfig.get_provider(provider_atom) do
      {:ok, config} ->
        # Remove API key for security, return config structure
        safe_config = Map.delete(config, :api_key)
        json(conn, %{config: safe_config})
      
      {:error, :not_configured} ->
        # Return defaults for unconfigured providers
        defaults = case provider_atom do
          :local -> %{host: "localhost", port: 11434, model: "llama3.1", embedding_model: "nomic-embed-text"}
          :openai -> %{model: "gpt-4o-mini"}
          :anthropic -> %{model: "claude-3-5-sonnet-20241022"}
          :azure -> %{model: "gpt-4", deployment: ""}
        end
        json(conn, %{config: Map.merge(%{enabled: true, temperature: 0.1}, defaults)})
    end
  end

  @doc """
  POST /api/ai/providers/:provider - Configure or update an AI provider.
  """
  def configure_provider(conn, %{"provider" => provider} = params) do
    provider_atom = String.to_atom(provider)
    
    if provider_atom not in @supported_providers do
      conn
      |> put_status(400)
      |> json(%{error: "Unsupported provider: #{provider}"})
    else
      config = %{
        name: params["name"],
        api_key: params["api_key"],
        model: params["model"],
        temperature: parse_float(params["temperature"]),
        max_tokens: parse_int(params["max_tokens"]),
        enabled: params["enabled"] || true
      }

      # Add provider-specific settings
      config = case provider do
        "local" ->
          Map.merge(config, %{
            host: params["host"] || "localhost",
            port: parse_int(params["port"]) || 11434,
            embedding_model: params["embedding_model"]
          })
        "azure" ->
          Map.merge(config, %{
            endpoint: params["endpoint"],
            deployment: params["deployment"]
          })
        _ ->
          config
      end
      
      case AIConfig.configure_provider(provider_atom, config) do
        :ok ->
          # Also save to Ollama config for local provider
          if provider_atom == :local do
            Zixir.Ollama.save_config(%{
              host: config[:host],
              port: config[:port],
              model: config[:model],
              embedding_model: config[:embedding_model]
            })
          end
          
          json(conn, %{
            status: "success",
            message: "Provider #{provider} configured successfully"
          })
        
        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Failed to configure provider: #{inspect(reason)}"})
      end
    end
  end

  @doc """
  DELETE /api/ai/providers/:provider - Remove a provider configuration.
  """
  def delete_provider(conn, %{"provider" => provider}) do
    provider_atom = String.to_atom(provider)
    
    case AIConfig.delete_provider(provider_atom) do
      :ok ->
        json(conn, %{status: "success", message: "Provider #{provider} deleted"})
      
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to delete provider: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/ai/providers/:provider/test - Test provider connection.
  """
  def test_provider(conn, %{"provider" => provider}) do
    provider_atom = String.to_atom(provider)
    
    case AIConfig.test_provider(provider_atom) do
      {:ok, result} ->
        json(conn, %{
          status: "success",
          result: result
        })
      
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          error: reason
        })
    end
  end

  @doc """
  POST /api/ai/custom - Configure a custom AI provider.
  """
  def configure_custom_provider(conn, params) do
    provider_id = params["provider_id"]

    if is_nil(provider_id) or provider_id == "" do
      conn
      |> put_status(400)
      |> json(%{error: "Provider ID is required"})
    else
      config = %{
        name: params["name"],
        api_key: params["api_key"],
        endpoint: params["endpoint"],
        model: params["model"],
        temperature: parse_float(params["temperature"]),
        max_tokens: parse_int(params["max_tokens"]),
        enabled: params["enabled"] !== false
      }

      case AIConfig.configure_custom_provider(provider_id, config) do
        :ok ->
          json(conn, %{
            status: "success",
            message: "Provider #{provider_id} configured successfully",
            provider_id: provider_id
          })

        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{error: "Failed to configure provider: #{inspect(reason)}"})
      end
    end
  end

  @doc """
  GET /api/ai/custom - List all custom providers.
  """
  def list_custom_providers(conn, _params) do
    providers = AIConfig.list_custom_providers()
    json(conn, %{providers: providers})
  end

  @doc """
  DELETE /api/ai/custom/:provider_id - Delete a custom provider.
  """
  def delete_custom_provider(conn, %{"provider_id" => provider_id}) do
    case AIConfig.delete_custom_provider(provider_id) do
      :ok ->
        json(conn, %{status: "success", message: "Provider #{provider_id} deleted"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to delete provider: #{inspect(reason)}"})
    end
  end

  @doc """
  POST /api/ai/custom/:provider_id/test - Test custom provider connection.
  """
  def test_custom_provider(conn, %{"provider_id" => provider_id}) do
    case AIConfig.test_custom_provider(provider_id) do
      {:ok, result} ->
        json(conn, %{
          status: "success",
          result: result
        })

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          error: reason
        })
    end
  end

  @doc """
  GET /api/ai/usage - Get AI usage statistics.
  """
  def get_usage(conn, _params) do
    usage = AIConfig.get_usage_stats()
    json(conn, %{usage: usage})
  end

  @doc """
  GET /api/ai/budget - Get budget configuration and status.
  """
  def get_budget(conn, _params) do
    budget = AIConfig.get_budget_status()
    json(conn, %{budget: budget})
  end

  @doc """
  POST /api/ai/budget - Set budget configuration.
  """
  def set_budget(conn, params) do
    config = %{
      enabled: params["enabled"] || false,
      daily_limit_usd: parse_float(params["daily_limit_usd"]),
      alert_threshold_percent: parse_int(params["alert_threshold_percent"]),
      current_spend_today: 0.0,
      alert_triggered: false
    }
    
    case AIConfig.set_budget_config(config) do
      :ok ->
        json(conn, %{
          status: "success",
          message: "Budget configuration updated"
        })
      
      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to update budget: #{inspect(reason)}"})
    end
  end

  @doc """
  GET /api/ai/alerts/check - Check if budget alert should be triggered.
  """
  def check_budget_alert(conn, _params) do
    case AIConfig.check_budget_alert() do
      {:alert, budget} ->
        json(conn, %{
          alert: true,
          budget: budget
        })
      
      {:ok, budget} ->
        json(conn, %{
          alert: false,
          budget: budget
        })
    end
  end

  @doc """
  POST /api/ai/test - Test AI function in playground.
  """
  def test_ai_function(conn, params) do
    function = params["function"]
    input = params["input"]
    provider = String.to_atom(params["provider"] || "openai")
    options = params["options"] || %{}
    
    start_time = System.monotonic_time(:millisecond)
    
    result = case function do
      "classify" ->
        Zixir.AI.classify(input, 
          labels: options["labels"] || ["positive", "negative"],
          provider: provider
        )
      
      "extract" ->
        Zixir.AI.extract(input,
          fields: options["fields"] || [:value],
          provider: provider
        )
      
      "summarize" ->
        Zixir.AI.summarize(input,
          max_length: options["max_length"] || 100,
          provider: provider
        )
      
      "sentiment" ->
        Zixir.AI.analyze_sentiment(input, provider: provider)
      
      _ ->
        {:error, "Unknown function: #{function}"}
    end
    
    latency = System.monotonic_time(:millisecond) - start_time
    
    case result do
      {:ok, output} ->
        json(conn, %{
          status: "success",
          function: function,
          input: input,
          output: output,
          latency_ms: latency,
          provider: provider
        })
      
      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{
          status: "error",
          function: function,
          input: input,
          error: inspect(reason),
          latency_ms: latency,
          provider: provider
        })
    end
  end

  @doc """
  GET /api/ai/logs - Get AI error logs.
  """
  def get_logs(conn, params) do
    # This would integrate with observability/logging
    # For now, return placeholder structure
    logs = [
      %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        provider: "openai",
        function: "classify",
        status: "success",
        latency_ms: 450,
        tokens_used: 150
      },
      %{
        timestamp: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.to_iso8601(),
        provider: "anthropic",
        function: "extract",
        status: "error",
        error: "Rate limit exceeded",
        latency_ms: 0,
        tokens_used: 0
      }
    ]
    
    # Filter by params if provided
    logs = if params["provider"] do
      Enum.filter(logs, fn log -> log.provider == params["provider"] end)
    else
      logs
    end
    
    json(conn, %{logs: logs})
  end

  @doc """
  GET /api/ai/logs/fragment - Get AI logs fragment for HTMX updates.
  """
  def logs_fragment(conn, params) do
    logs = [
      %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        provider: "openai",
        function: "classify",
        status: "success",
        latency_ms: 450,
        tokens_used: 150
      }
    ]
    
    conn
    |> put_view(ZixirWeb.AIView)
    |> render("logs_fragment.html", logs: logs)
  end

  # ============================================================================
  # Enhanced Playground Chat Functions
  # ============================================================================

  @doc """
  GET /api/ai/context - Get full system context for AI assistant.
  """
  def get_context(conn, _params) do
    context = Zixir.ContextAggregator.build_full_context()
    json(conn, %{context: context})
  end

  @doc """
  POST /api/ai/chat - Send a message to the AI assistant.
  """
  def chat(conn, params) do
    message = params["message"]
    provider = String.to_atom(params["provider"] || "local")
    session_id = params["session_id"] || generate_session_id()
    
    if is_nil(message) or message == "" do
      conn
      |> put_status(400)
      |> json(%{error: "Message is required"})
    else
      start_time = System.monotonic_time(:millisecond)
      
      # Save user message
      Zixir.Playground.Memory.save_message(session_id, :user, message)
      
      # Build context
      system_context = Zixir.ContextAggregator.build_full_context()
      conversation_history = Zixir.Playground.Memory.get_conversation_history(session_id, 10)
      
      # Build system prompt
      system_prompt = build_system_prompt(system_context, conversation_history)
      
      # Check if this is a database query
      result = case detect_database_intent(message, system_context) do
        {:database, connection_id} ->
          handle_database_query(message, connection_id, provider, system_context)
        
        _ ->
          # Regular chat
          handle_chat_message(message, system_prompt, provider)
      end
      
      latency = System.monotonic_time(:millisecond) - start_time
      
      case result do
        {:ok, response, metadata} ->
          # Save assistant response
          Zixir.Playground.Memory.save_message(session_id, :assistant, response, metadata)
          
          json(conn, %{
            status: "success",
            message: response,
            session_id: session_id,
            latency_ms: latency,
            provider: provider,
            metadata: metadata
          })
        
        {:error, reason} ->
          conn
          |> put_status(500)
          |> json(%{
            status: "error",
            error: inspect(reason),
            session_id: session_id,
            latency_ms: latency
          })
      end
    end
  end

  @doc """
  POST /api/ai/chat/stream - Stream AI assistant response.
  """
  def chat_stream(conn, params) do
    message = params["message"]
    provider = String.to_atom(params["provider"] || "local")
    session_id = params["session_id"] || generate_session_id()
    
    if is_nil(message) or message == "" do
      conn
      |> put_status(400)
      |> json(%{error: "Message is required"})
    else
      # Save user message
      Zixir.Playground.Memory.save_message(session_id, :user, message)
      
      # Set up SSE stream
      conn = conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)
      
      # Build context
      system_context = Zixir.ContextAggregator.build_full_context()
      conversation_history = Zixir.Playground.Memory.get_conversation_history(session_id, 10)
      system_prompt = build_system_prompt(system_context, conversation_history)
      
      # Stream response
      full_response = ""
      
      try do
        case Zixir.LLM.stream(provider, message, 
          system: system_prompt,
          temperature: 0.7
        ) do
          {:ok, stream} ->
            Enum.each(stream, fn chunk ->
              full_response = full_response <> chunk
              chunk = Jason.encode!(%{chunk: chunk, done: false})
              chunk(conn, "data: #{chunk}\n\n")
            end)
            
            # Send completion
            done_chunk = Jason.encode!(%{done: true, full_response: full_response})
            chunk(conn, "data: #{done_chunk}\n\n")
            
            # Save complete response
            Zixir.Playground.Memory.save_message(session_id, :assistant, full_response)
            
          {:error, reason} ->
            error_chunk = Jason.encode!(%{error: inspect(reason), done: true})
            chunk(conn, "data: #{error_chunk}\n\n")
        end
      rescue
        e ->
          error_chunk = Jason.encode!(%{error: "Stream error: #{inspect(e)}", done: true})
          chunk(conn, "data: #{error_chunk}\n\n")
      end
      
      conn
    end
  end

  @doc """
  GET /api/ai/chat/history/:session_id - Get conversation history.
  """
  def get_chat_history(conn, %{"session_id" => session_id}) do
    history = Zixir.Playground.Memory.get_conversation_history(session_id)
    stats = Zixir.Playground.Memory.get_stats(session_id)
    
    json(conn, %{
      session_id: session_id,
      messages: history,
      stats: stats
    })
  end

  @doc """
  DELETE /api/ai/chat/history/:session_id - Clear conversation history.
  """
  def clear_chat_history(conn, %{"session_id" => session_id}) do
    Zixir.Playground.Memory.clear_conversation(session_id)
    json(conn, %{status: "success", message: "Conversation history cleared"})
  end

  # Private functions for chat handling

  defp build_system_prompt(context, history) do
    workflows_summary = format_workflows_context(context.workflows)
    databases_summary = format_databases_context(context.databases)
    
    """
    You are Zixir AI, an intelligent assistant for the Zixir workflow automation platform (v#{context.system.version}).

    ## Current System State

    **Workflows:**
    #{workflows_summary}

    **Database Connections:**
    #{databases_summary}

    **System:**
    - Uptime: #{context.system.uptime_minutes} minutes
    - Memory: #{context.system.memory_usage} MB
    - Active Connections: #{context.system.active_connections}

    ## Your Capabilities
    1. Answer questions about workflows, their status, and history
    2. Query databases using natural language (I'll convert to SQL)
    3. Explain system metrics and performance
    4. Provide insights and recommendations
    5. Help debug issues and errors

    ## Guidelines
    - Be helpful, concise, and technical when appropriate
    - Use markdown formatting for clarity
    - When querying databases, I'll show you the SQL used
    - If you need specific data, ask me to query it
    - Always provide actionable next steps when relevant

    ## Recent Conversation
    #{format_conversation_history(history)}

    Current time: #{context.timestamp}
    """
  end

  defp format_workflows_context(workflows) do
    summary = "#{workflows.active} active, #{workflows.paused} paused, #{workflows.failed} failed, #{workflows.completed} completed"
    
    recent = workflows.recent
    |> Enum.map(fn w -> "- #{w.name} (#{w.status}, #{w.time_ago})" end)
    |> Enum.join("\n")
    
    "#{summary}\nRecent activity:\n#{recent}"
  end

  defp format_databases_context(databases) do
    databases.connections
    |> Enum.map(fn conn ->
      "- #{conn.name} (#{conn.type}): #{length(conn.tables)} tables, status: #{conn.status}"
    end)
    |> Enum.join("\n")
  end

  defp format_conversation_history([]), do: "No previous messages in this session."
  defp format_conversation_history(history) do
    history
    |> Enum.map(fn msg ->
      role = if msg.role == :user, do: "User", else: "Assistant"
      "#{role}: #{msg.content}"
    end)
    |> Enum.join("\n")
  end

  defp detect_database_intent(message, context) do
    # Simple intent detection
    lowered = String.downcase(message)
    
    database_keywords = [
      "show", "query", "select", "from", "table", "database",
      "how many", "count", "rows", "records", "data"
    ]
    
    has_db_keyword = Enum.any?(database_keywords, &String.contains?(lowered, &1))
    
    if has_db_keyword and length(context.databases.connections) > 0 do
      # Return first available connection
      conn = hd(context.databases.connections)
      {:database, conn.id}
    else
      :chat
    end
  end

  defp handle_database_query(message, connection_id, provider, context) do
    # Get schema info
    # Get schema info
    {:ok, schema_info} = Zixir.Playground.DatabaseBridge.get_schema_info(connection_id)
    
    # Generate SQL
    case Zixir.Playground.DatabaseBridge.natural_language_to_sql(
      message, connection_id, schema_info
    ) do
      {:ok, sql} ->
        # Execute query
        case Zixir.Playground.DatabaseBridge.execute_read_query(connection_id, sql) do
          {:ok, results} ->
            # Format response
            text_results = Zixir.Playground.DatabaseBridge.format_results_to_text(results)
            
            response = """
            I queried the database for you:

            ```sql
            #{sql}
            ```

            **Results:**
            #{text_results}
            """
            
            metadata = %{
              sql: sql,
              row_count: results.row_count,
              connection_id: connection_id
            }
            
            {:ok, response, metadata}
          
          {:error, reason} ->
            {:ok, "I tried to run this query but got an error:\n\n```sql\n#{sql}\n```\n\nError: #{inspect(reason)}", %{}}
        end
      
      {:error, reason} ->
        {:ok, "I couldn't generate a query for that. Error: #{inspect(reason)}", %{}}
    end
  end

  defp handle_chat_message(message, system_prompt, provider) do
    case Zixir.LLM.call(provider, message, 
      system: system_prompt,
      temperature: 0.7,
      max_tokens: 2000
    ) do
      {:ok, %{text: response}} ->
        {:ok, response, %{}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp parse_float(nil), do: nil
  defp parse_float(val) when is_binary(val) do
    case Float.parse(val) do
      {f, _} -> f
      :error -> nil
    end
  end
  defp parse_float(val) when is_number(val), do: val
  defp parse_float(_), do: nil

  defp parse_int(nil), do: nil
  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      :error -> nil
    end
  end
  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: nil
end
