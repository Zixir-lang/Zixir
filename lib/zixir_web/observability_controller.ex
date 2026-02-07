defmodule ZixirWeb.ObservabilityController do
  @moduledoc """
  Web dashboard for system observability and monitoring.
  
  Provides real-time visibility into:
  - System metrics and performance
  - Active workflows and their status
  - Agent activities
  - Circuit breaker states
  - LLM usage and costs
  - Vector database health
  """
  
  use ZixirWeb, :controller
  
  alias Zixir.{Observability, Workflow, Agent, CircuitBreaker, LLM}
  
  def index(conn, _params) do
    # Gather all observability data
    dashboard_data = %{
      system_stats: get_system_stats(),
      metrics: get_current_metrics(),
      active_workflows: get_active_workflows(),
      circuit_breakers: get_circuit_breaker_status(),
      llm_usage: get_llm_usage_stats(),
      recent_traces: get_recent_traces(),
      alerts: get_active_alerts()
    }
    
    render(conn, :index, dashboard_data)
  end
  
  def metrics(conn, _params) do
    metrics = %{
      timestamp: DateTime.utc_now(),
      system: get_system_metrics(),
      workflows: get_workflow_metrics(),
      agents: get_agent_metrics(),
      llm: get_llm_metrics()
    }
    
    json(conn, metrics)
  end
  
  def traces(conn, _params) do
    traces = get_recent_traces()
    json(conn, %{traces: traces})
  end
  
  def alerts(conn, _params) do
    alerts = get_active_alerts()
    json(conn, %{alerts: alerts})
  end
  
  def export_prometheus(conn, _params) do
    prometheus_output = Observability.export_metrics_prometheus()
    
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, prometheus_output)
  end
  
  # Private helper functions
  
  defp get_system_stats do
    %{
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      memory: get_memory_stats(),
      processes: :erlang.system_info(:process_count),
      atoms: :erlang.system_info(:atom_count)
    }
  end
  
  defp get_memory_stats do
    memory = :erlang.memory()
    
    %{
      total: format_bytes(memory[:total]),
      processes: format_bytes(memory[:processes]),
      atoms: format_bytes(memory[:atom]),
      binary: format_bytes(memory[:binary]),
      ets: format_bytes(memory[:ets])
    }
  end
  
  defp format_bytes(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 2)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 2)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 2)} KB"
      true -> "#{bytes} B"
    end
  end
  
  defp get_current_metrics do
    case Process.whereis(Observability) do
      nil -> %{}
      _pid -> Observability.get_metrics()
    end
  end
  
  defp get_active_workflows do
    # Get workflow status from State module
    checkpoint_dir = Application.get_env(:zixir, :workflow_checkpoint_dir, "_zixir_workflows")
    
    if File.dir?(checkpoint_dir) do
      case File.ls(checkpoint_dir) do
        {:ok, workflows} ->
          workflows
          |> Enum.map(fn wf_id ->
            %{id: wf_id, status: Workflow.status(wf_id)}
          end)
          |> Enum.take(10)
        
        _ -> []
      end
    else
      []
    end
  end
  
  defp get_circuit_breaker_status do
    # Get all circuit breaker states
    case Registry.select(:zixir_circuit_breaker_registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [] -> []
      names ->
        Enum.map(names, fn name ->
          case CircuitBreaker.metrics(name) do
            metrics when is_map(metrics) ->
              %{
                name: name,
                state: metrics.state,
                failure_count: metrics.failure_count,
                total_calls: metrics.metrics[:total_calls] || 0
              }
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  end
  
  defp get_llm_usage_stats do
    usage = LLM.all_usage()
    
    %{
      providers: usage,
      total_cost: calculate_total_cost(usage),
      total_requests: calculate_total_requests(usage)
    }
  end
  
  defp calculate_total_cost(usage) do
    usage
    |> Map.values()
    |> Enum.map(& &1[:cost] || 0.0)
    |> Enum.sum()
    |> Float.round(4)
  end
  
  defp calculate_total_requests(usage) do
    usage
    |> Map.values()
    |> Enum.map(& &1[:requests] || 0)
    |> Enum.sum()
  end
  
  defp get_recent_traces do
    case Process.whereis(Observability) do
      nil -> []
      _pid ->
        case Observability.get_active_spans() do
          spans when is_map(spans) ->
            spans
            |> Enum.map(fn {id, span} ->
              %{
                id: id,
                name: span.name,
                status: span.status,
                duration_ms: span.duration_ms,
                metadata: span.metadata
              }
            end)
            |> Enum.take(20)
          
          _ -> []
        end
    end
  end
  
  defp get_active_alerts do
    # Check for various alert conditions
    alerts = []
    
    # Check circuit breakers
    alerts = alerts ++ check_circuit_breaker_alerts()
    
    # Check LLM budget
    alerts = alerts ++ check_llm_budget_alerts()
    
    # Check memory usage
    alerts = alerts ++ check_memory_alerts()
    
    alerts
  end
  
  defp check_circuit_breaker_alerts do
    case Registry.select(:zixir_circuit_breaker_registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [] -> []
      names ->
        Enum.flat_map(names, fn name ->
          case CircuitBreaker.state(name) do
            :open ->
              [%{
                level: :error,
                message: "Circuit breaker '#{name}' is OPEN",
                timestamp: DateTime.utc_now()
              }]
            
            :half_open ->
              [%{
                level: :warning,
                message: "Circuit breaker '#{name}' is testing recovery",
                timestamp: DateTime.utc_now()
              }]
            
            _ -> []
          end
        end)
    end
  end
  
  defp check_llm_budget_alerts do
    total_cost = get_llm_usage_stats().total_cost
    budget = Application.get_env(:zixir, :llm_budget, 100.0)
    
    if total_cost > budget * 0.9 do
      [%{
        level: if(total_cost > budget, do: :error, else: :warning),
        message: "LLM budget at #{Float.round(total_cost / budget * 100, 1)}%",
        timestamp: DateTime.utc_now()
      }]
    else
      []
    end
  end
  
  defp check_memory_alerts do
    memory = :erlang.memory()
    total = memory[:total]
    threshold = 1_000_000_000  # 1GB
    
    if total > threshold do
      [%{
        level: :warning,
        message: "High memory usage: #{format_bytes(total)}",
        timestamp: DateTime.utc_now()
      }]
    else
      []
    end
  end
  
  defp get_system_metrics do
    %{
      cpu_usage: get_cpu_usage(),
      memory_usage: :erlang.memory()[:total],
      process_count: :erlang.system_info(:process_count),
      uptime: :erlang.statistics(:wall_clock) |> elem(0)
    }
  end
  
  defp get_workflow_metrics do
    case get_active_workflows() do
      workflows ->
        %{
          active_count: length(workflows),
          completed_today: 0,  # Would need to track this
          failed_today: 0     # Would need to track this
        }
    end
  end
  
  defp get_agent_metrics do
    case Registry.select(:zixir_agent_registry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
      [] -> %{active_count: 0, total_tasks: 0}
      _ids -> %{active_count: length(_ids), total_tasks: 0}
    end
  end
  
  defp get_llm_metrics do
    usage = LLM.all_usage()
    
    %{
      total_tokens: calculate_total_tokens(usage),
      total_cost: calculate_total_cost(usage),
      active_providers: Map.keys(usage)
    }
  end
  
  defp calculate_total_tokens(usage) do
    usage
    |> Map.values()
    |> Enum.reduce(0, fn stats, acc ->
      acc + (stats[:input_tokens] || 0) + (stats[:output_tokens] || 0)
    end)
  end
  
  defp get_cpu_usage do
    # Simple approximation using reductions
    {reductions, _} = :erlang.statistics(:reductions)
    Process.sleep(100)
    {new_reductions, _} = :erlang.statistics(:reductions)
    
    # Convert to rough percentage
    min(100, div(new_reductions - reductions, 1000))
  end
end
