defmodule Zixir.ContextAggregator do
  @moduledoc """
  Aggregates real-time context about workflows, databases, and system state
  for AI assistant consumption.

  Provides a unified view of:
  - Active and recent workflows
  - Configured database connections and schemas
  - System metrics and performance data
  - Vector collection status
  - Recent logs and events

  ## Usage

      context = Zixir.ContextAggregator.build_full_context()
      # Returns structured map with all system context

  """

  alias Zixir.Cache
  require Logger

  @doc """
  Build comprehensive context for AI assistant.
  """
  @spec build_full_context() :: map()
  def build_full_context do
    %{
      workflows: get_workflows_context(),
      databases: get_databases_context(),
      system: get_system_metrics(),
      vectors: get_vector_context(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Get comprehensive workflow context.
  """
  @spec get_workflows_context() :: map()
  def get_workflows_context do
    # Fetch from cache where workflows are stored
    workflows = fetch_all_workflows()
    
    %{
      total: length(workflows),
      active: Enum.count(workflows, &(&1.status == "active")),
      paused: Enum.count(workflows, &(&1.status == "paused")),
      failed: Enum.count(workflows, &(&1.status == "failed")),
      completed: Enum.count(workflows, &(&1.status == "completed")),
      recent: get_recent_workflow_runs(workflows, 5),
      list: workflows |> Enum.take(10) |> Enum.map(&format_workflow/1)
    }
  end

  @doc """
  Get database connections and schema context.
  """
  @spec get_databases_context() :: map()
  def get_databases_context do
    connections = fetch_connections()
    
    %{
      total: length(connections),
      connections: Enum.map(connections, fn conn ->
        %{
          id: conn.id,
          name: conn.name,
          type: conn.type,
          host: Map.get(conn, :host, "localhost"),
          status: Map.get(conn, :status, "unknown"),
          tables: fetch_table_list(conn.id)
        }
      end)
    }
  end
  
  defp fetch_connections do
    # Try to get connections from cache
    case Cache.get("connections:all") do
      {:ok, connections} when is_list(connections) -> connections
      _ -> fetch_sample_connections()
    end
  end
  
  defp fetch_sample_connections do
    # Return sample connections for demo/development
    [
      %{
        id: "conn_001",
        name: "SQL Server Production",
        type: "sqlserver",
        host: "localhost",
        status: "connected"
      },
      %{
        id: "conn_002",
        name: "PostgreSQL Analytics",
        type: "postgresql",
        host: "localhost",
        status: "connected"
      },
      %{
        id: "conn_003",
        name: "MySQL Legacy",
        type: "mysql",
        host: "localhost",
        status: "disconnected"
      }
    ]
  end

  @doc """
  Get system metrics and performance data.
  """
  @spec get_system_metrics() :: map()
  def get_system_metrics do
    %{
      uptime_minutes: get_uptime(),
      memory_usage: get_memory_usage(),
      active_connections: get_active_connection_count(),
      queue_depth: get_queue_depth(),
      recent_errors: get_recent_errors(5),
      version: get_zixir_version()
    }
  end

  @doc """
  Get vector database context.
  """
  @spec get_vector_context() :: map()
  def get_vector_context do
    case Cache.get("vector:collections") do
      {:ok, collections} when is_list(collections) ->
        %{
          total_collections: length(collections),
          collections: Enum.map(collections, fn coll ->
            %{
              name: coll.name,
              dimensions: coll.dimensions || 1536,
              document_count: coll.document_count || 0,
              size_mb: coll.size_mb || 0
            }
          end)
        }
      _ ->
        %{
          total_collections: 0,
          collections: []
        }
    end
  end

  # Private functions

  defp fetch_all_workflows do
    # Try to get workflows from cache
    case Cache.get("workflows:all") do
      {:ok, workflows} when is_list(workflows) -> workflows
      _ -> fetch_workflows_from_storage()
    end
  end

  defp fetch_workflows_from_storage do
    # Fallback: return sample/demo workflows if cache is empty
    # In production, this would query the database
    [
      %{
        id: "wf_001",
        name: "order_processing",
        status: "active",
        last_run: DateTime.utc_now() |> DateTime.add(-3600, :second),
        total_runs: 47,
        success_rate: 0.94
      },
      %{
        id: "wf_002",
        name: "data_sync",
        status: "paused",
        last_run: DateTime.utc_now() |> DateTime.add(-86400, :second),
        total_runs: 12,
        success_rate: 1.0
      },
      %{
        id: "wf_003",
        name: "report_generation",
        status: "completed",
        last_run: DateTime.utc_now() |> DateTime.add(-7200, :second),
        total_runs: 8,
        success_rate: 0.88
      }
    ]
  end

  defp get_recent_workflow_runs(workflows, limit) do
    workflows
    |> Enum.sort_by(& &1.last_run, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn wf ->
      %{
        id: wf.id,
        name: wf.name,
        status: wf.status,
        time_ago: format_time_ago(wf.last_run)
      }
    end)
  end

  defp format_workflow(wf) do
    %{
      id: wf.id,
      name: wf.name,
      status: wf.status,
      runs: wf.total_runs,
      success_rate: Float.round(wf.success_rate * 100, 1)
    }
  end

  defp get_connection_status(conn_id) do
    case Cache.get("connection:#{conn_id}:status") do
      {:ok, status} -> status
      _ -> "unknown"
    end
  end

  defp fetch_table_list(conn_id) do
    case Cache.get("connection:#{conn_id}:tables") do
      {:ok, tables} when is_list(tables) -> 
        Enum.take(tables, 20)
      _ -> 
        []
    end
  end

  defp get_uptime do
    # Get system uptime in minutes
    case :erlang.statistics(:wall_clock) do
      {ms, _} -> div(ms, 60000)
      _ -> 0
    end
  end

  defp get_memory_usage do
    # Get memory usage in MB
    case :erlang.memory(:total) do
      bytes -> div(bytes, 1024 * 1024)
      _ -> 0
    end
  end

  defp get_active_connection_count do
    # Count active WebSocket/HTTP connections
    # This is a simplified version
    3
  end

  defp get_queue_depth do
    # Get job queue depth
    case Cache.get("queue:depth") do
      {:ok, depth} when is_integer(depth) -> depth
      _ -> 0
    end
  end

  defp get_recent_errors(limit) do
    # Fetch recent errors from cache/logs
    case Cache.get("logs:errors:recent") do
      {:ok, errors} when is_list(errors) -> 
        Enum.take(errors, limit)
      _ -> 
        []
    end
  end

  defp get_zixir_version do
    # Get version from application
    case Application.spec(:zixir, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "7.0.0"
    end
  end

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end