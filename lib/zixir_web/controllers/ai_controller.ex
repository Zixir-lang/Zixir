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
